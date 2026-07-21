"""Student listing, analytics, and teacher profile management routes."""
import sqlite3
import logging
import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from app.async_db import db_conn
from app.dependencies import hash_password, verify_teacher, verify_admin
from app.models import TeacherCreate, NameUpdate, DepartmentUpdate, StudentListResponse, StudentAnalyticsResponse, TeacherSummary, TeacherCreateResponse, StatusResponse, TeacherProfileResponse

router = APIRouter()


@router.get("/teacher/students", response_model=StudentListResponse,
            summary="List students with stats",
            description="Returns all registered students with study minutes, streak days, and saved resources.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}, 500: {"description": "Database error"}})
async def teacher_list_students(teacher_user: str = Depends(verify_teacher), grade: Optional[str] = Query(default=None)):
    """List students with weekly study stats.

    Args:
        grade: Optional grade filter.

    Returns:
        Dict with a students list containing id, name, username, grade, study_minutes_this_week, streak_days, resources_saved, last_active.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            grade_filter = "WHERE s.grade = ?" if grade else ""
            params = (grade,) if grade else ()
            c.execute(f"""
                SELECT s.id, s.name, s.username, s.grade,
                       COALESCE(w.total_seconds, 0) AS week_secs,
                       COALESCE(w.streak_days, 0) AS streak_days,
                       COALESCE(sv.saved, 0) AS saved,
                       w.updated_at AS last_active
                FROM scholars s
                LEFT JOIN weekly_study w ON w.scholar_id = s.id
                LEFT JOIN (SELECT scholar_id, COUNT(*) AS saved FROM scholar_downloads GROUP BY scholar_id) sv ON sv.scholar_id = s.id
                LEFT JOIN users u ON u.scholar_id = s.id
                {grade_filter}
                {"AND " if grade else "WHERE "}(u.role IS NULL OR u.role = 'student')
                ORDER BY last_active DESC NULLS LAST, s.name ASC
            """, params)
            students = []
            for row in c.fetchall():
                sid, name, uname, sgrade, week_secs, streak_days, saved, last_active = row
                students.append({
                    "id": sid,
                    "name": name or uname or "",
                    "username": uname or "",
                    "grade": sgrade or "",
                    "study_minutes_this_week": week_secs // 60,
                    "streak_days": streak_days,
                    "resources_saved": saved,
                    "last_active": last_active or "",
                })
        except sqlite3.OperationalError as e:
            raise HTTPException(status_code=500, detail=f"Database error: {e}")  # i18n: user-facing error message

    return {"students": students}


@router.get("/teacher/student/{scholar_id}/analytics", response_model=StudentAnalyticsResponse,
            summary="Get student analytics",
            description="Returns study minutes, streak, saved resources, and per-subject breakdown for a student.",
            tags=["Analytics"],
            responses={401: {"description": "Unauthorized"}, 404: {"description": "Student not found"}})
async def teacher_student_analytics(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    """Get detailed analytics for a single student.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Dict with study_minutes_this_week, streak_days, resources_saved, and subjects list.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("""
            SELECT s.name, COALESCE(w.total_seconds, 0), COALESCE(w.streak_days, 0),
                   COALESCE(dl.cnt, 0)
            FROM scholars s
            LEFT JOIN weekly_study w ON w.scholar_id = s.id
            LEFT JOIN (SELECT scholar_id, COUNT(*) AS cnt FROM scholar_downloads GROUP BY scholar_id) dl
                   ON dl.scholar_id = s.id
            WHERE s.id = ?
        """, (scholar_id,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Student not found")  # i18n: user-facing error message
        week_secs = row[1]
        streak = row[2]
        saved = row[3]
        c.execute("SELECT subject_name, minutes FROM subject_minutes WHERE scholar_id = ? ORDER BY minutes DESC", (scholar_id,))
        subjects = [{"name": row[0], "minutes": row[1]} for row in c.fetchall()]
    return {
        "study_minutes_this_week": week_secs // 60,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": subjects,
    }


@router.get("/teachers", response_model=list[TeacherSummary],
            summary="List teacher profiles",
            description="Returns all teacher profiles except the default admin, with name, department, and scholar_id.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}})
async def get_teachers(teacher_user: str = Depends(verify_teacher)):
    """List all teacher profiles.

    Returns:
        List of dicts with username, name, department, scholar_id, and reset_required.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT username, name, department, scholar_id, reset_required FROM users WHERE username != 'admin' ORDER BY name ASC")
        rows = c.fetchall()
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "General", "scholar_id": r[3] or "", "reset_required": r[4] or 0} for r in rows]


@router.post("/teacher/profiles", response_model=TeacherCreateResponse,
             summary="Create a teacher profile",
             description="Creates a new teacher user and a corresponding scholar record. Admin-only.",
             tags=["Teacher"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_teacher_profile(teacher: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a teacher profile and associated scholar record.

    Args:
        teacher: Teacher creation payload.

    Returns:
        Dict with status, username, name, department, and scholar_id.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT username FROM users WHERE username = ?", (teacher.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")  # i18n: user-facing error message

            display_name = teacher.name or teacher.username
            dept = teacher.department or "General"
            unique_suffix = uuid.uuid4().hex
            full_id = f"LUMINA_01-T{unique_suffix}"
            c.execute("INSERT OR IGNORE INTO scholars (id, name) VALUES (?, ?)", (full_id, display_name))

            hashed_pwd = hash_password(teacher.password)
            c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id) VALUES (?, ?, ?, ?, ?)",
                      (teacher.username, hashed_pwd, display_name, dept, full_id))
            conn.commit()
            return {"status": "success", "username": teacher.username, "name": display_name, "department": dept, "scholar_id": full_id}
        except Exception as e:
            logging.error(f"create_teacher_profile: {e}")
            raise HTTPException(status_code=400, detail="Failed to create teacher profile")  # i18n: user-facing error message


@router.delete("/teacher/profiles/{username}", response_model=StatusResponse,
               summary="Delete a teacher profile",
               description="Deletes a teacher user by username. The default admin account cannot be deleted.",
               tags=["Teacher"],
               responses={400: {"description": "Cannot delete admin account"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def delete_teacher_profile(username: str, admin_user: str = Depends(verify_admin)):
    """Delete a teacher profile.

    Args:
        username: The teacher's username.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If attempting to delete the default admin.
    """
    if username == 'admin':
        raise HTTPException(status_code=400, detail="Cannot delete admin account.")  # i18n: user-facing error message
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("DELETE FROM users WHERE username = ?", (username,))
        conn.commit()
    return {"status": "success"}


@router.get("/teacher/me", response_model=TeacherProfileResponse,
            summary="Get current teacher profile",
            description="Returns the profile of the currently authenticated teacher or admin.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}})
async def get_teacher_me(teacher_user: str = Depends(verify_teacher)):
    """Get the profile of the authenticated user.

    Returns:
        Dict with username, name, department, scholar_id, and reset_required.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT name, department, scholar_id, reset_required FROM users WHERE username = ?", (teacher_user,))
        row = c.fetchone()
        if row:
            reset_val = row[3] or 0
            if teacher_user == "admin":
                reset_val = 0
            return {"username": teacher_user, "name": row[0] or teacher_user, "department": row[1] or "General", "scholar_id": row[2], "reset_required": reset_val}
        return {"username": teacher_user, "reset_required": 0}


@router.post("/teacher/profile/name", response_model=StatusResponse,
             summary="Update display name",
             description="Updates the display name for the currently authenticated teacher or admin.",
             tags=["Teacher"],
             responses={401: {"description": "Unauthorized"}})
async def update_teacher_name(data: NameUpdate, teacher_user: str = Depends(verify_teacher)):
    """Update the display name of the authenticated user.

    Args:
        data: Name update payload.

    Returns:
        Status dict.
    Raises:
        HTTPException 400: If the user is the default admin.
    """
    if teacher_user == "admin":
        raise HTTPException(status_code=400, detail="Cannot modify the default admin profile.")  # i18n: user-facing error message
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET name = ? WHERE username = ?", (data.name.strip(), teacher_user))
        conn.commit()
    return {"status": "ok"}


@router.post("/teacher/profile/department", response_model=StatusResponse,
             summary="Update department",
             description="Updates the department for the currently authenticated teacher.",
             tags=["Teacher"],
             responses={401: {"description": "Unauthorized"}})
async def update_teacher_department(data: DepartmentUpdate, teacher_user: str = Depends(verify_teacher)):
    """Update the department of the authenticated teacher.

    Args:
        data: Department update payload.

    Returns:
        Status dict.
    Raises:
        HTTPException 400: If the user is the default admin.
    """
    if teacher_user == "admin":
        raise HTTPException(status_code=400, detail="Cannot modify the default admin profile.")  # i18n: user-facing error message
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET department = ? WHERE username = ?", (data.department.strip(), teacher_user))
        conn.commit()
    return {"status": "ok"}
