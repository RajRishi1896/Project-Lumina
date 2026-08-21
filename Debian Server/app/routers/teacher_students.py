"""Student listing, analytics, and teacher profile management routes."""
import asyncio
import sqlite3
import logging
import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.dependencies import hash_password, verify_teacher, verify_admin, invalidate_tokens_for_user
from app.models import TeacherCreate, NameUpdate, DepartmentUpdate, StudentListResponse, StudentAnalyticsResponse, TeacherSummary, TeacherCreateResponse, StatusResponse, TeacherProfileResponse
from app.audit import audit, Action

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
    try:
        conditions = ["(u.role IS NULL OR u.role = 'student')"]
        params = []
        if grade:
            conditions.append("s.grade = ?")
            params.append(grade)
        where_clause = "WHERE " + " AND ".join(conditions)
        rows = await db_fetch(f"""
            SELECT s.id, s.name, s.username, s.grade,
                   COALESCE(w.total_seconds, 0) AS week_secs,
                   COALESCE(w.streak_days, 0) AS streak_days,
                   COALESCE(sv.saved, 0) AS saved,
                   w.updated_at AS last_active
            FROM scholars s
            LEFT JOIN weekly_study w ON w.scholar_id = s.id
            LEFT JOIN (SELECT scholar_id, COUNT(*) AS saved FROM scholar_downloads GROUP BY scholar_id) sv ON sv.scholar_id = s.id
            LEFT JOIN users u ON u.scholar_id = s.id
            {where_clause}
            ORDER BY last_active DESC NULLS LAST, s.name ASC
        """, tuple(params))
        students = []
        for row in rows:
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
        logging.error(f"teacher_list_students: {e}")
        raise HTTPException(status_code=500, detail="Failed to load students")  # i18n: user-facing error message

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
    row = await db_fetch_one("""
        SELECT s.name, COALESCE(w.total_seconds, 0), COALESCE(w.streak_days, 0),
               COALESCE(dl.cnt, 0)
        FROM scholars s
        LEFT JOIN weekly_study w ON w.scholar_id = s.id
        LEFT JOIN (SELECT scholar_id, COUNT(*) AS cnt FROM scholar_downloads GROUP BY scholar_id) dl
               ON dl.scholar_id = s.id
        WHERE s.id = ?
    """, (scholar_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Student not found")  # i18n: user-facing error message
    week_secs = row[1]
    streak = row[2]
    saved = row[3]
    subjects_rows = await db_fetch(
        "SELECT subject_name, minutes FROM subject_minutes WHERE scholar_id = ? ORDER BY minutes DESC",
        (scholar_id,))
    subjects = [{"name": row[0], "minutes": row[1]} for row in subjects_rows]
    quiz_rows = await db_fetch("""
        SELECT qb.resource_id, COALESCE(r.title, cr.title, '') as title,
               qb.best_score, COALESCE(qa.cnt, 0) as attempts_count
        FROM quiz_best_scores qb
        LEFT JOIN resources r ON r.id = qb.resource_id AND qb.course_id = ''
        LEFT JOIN course_resources cr ON cr.id = qb.resource_id AND qb.course_id != ''
        LEFT JOIN (SELECT resource_id, COUNT(*) as cnt FROM quiz_attempts WHERE student_id = ? GROUP BY resource_id) qa
               ON qa.resource_id = qb.resource_id
        WHERE qb.scholar_id = ?
        ORDER BY qb.updated_at DESC
    """, (scholar_id, scholar_id))
    quiz_scores = [{"resource_id": r[0], "title": r[1], "best_score": r[2], "attempts_count": r[3]} for r in quiz_rows]
    return {
        "study_minutes_this_week": week_secs // 60,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": subjects,
        "quiz_scores": quiz_scores,
    }


@router.get("/teachers", response_model=list[TeacherSummary],
            summary="List teacher profiles",
            description="Returns all teacher profiles except the default admin, with name, department, and scholar_id. Admin-only: usernames and departments are staff information.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def get_teachers(admin_user: str = Depends(verify_admin)):
    """List all teacher profiles.

    Returns:
        List of dicts with username, name, department, scholar_id, and reset_required.
    """
    rows = await db_fetch(
        "SELECT username, name, department, scholar_id, reset_required FROM users WHERE username != 'admin' ORDER BY name ASC")
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "General", "scholar_id": r[3] or "", "reset_required": r[4] or 0} for r in rows]


@router.post("/teacher/profiles", response_model=TeacherCreateResponse,
             summary="Create a teacher profile",
             description="Creates a new teacher user and a corresponding scholar record. Admin-only.",
             tags=["Teacher"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_teacher_profile(teacher: TeacherCreate, request: Request = None, admin_user: str = Depends(verify_admin)):
    """Create a teacher profile and associated scholar record.

    Args:
        teacher: Teacher creation payload.

    Returns:
        Dict with status, username, name, department, and scholar_id.
    """
    try:
        display_name = teacher.name or teacher.username
        dept = teacher.department or "General"
        unique_suffix = uuid.uuid4().hex
        full_id = f"LUMINA_01-T{unique_suffix}"
        hashed_pwd = await asyncio.to_thread(hash_password, teacher.password)

        # Race-safe: users.username is the PRIMARY KEY, so a concurrent
        # create with the same username loses the INSERT and gets a 400.
        def _create_teacher(conn):
            """Insert the scholar and user rows within one transaction."""
            conn.execute("INSERT INTO scholars (id, name) VALUES (?, ?)", (full_id, display_name))
            conn.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id) VALUES (?, ?, ?, ?, ?)",
                         (teacher.username, hashed_pwd, display_name, dept, full_id))
            conn.commit()
        try:
            await db_run(_create_teacher)
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="Username already exists.")  # i18n: user-facing error message
        await audit(action=Action.CREATE_ACCOUNT, username=admin_user, resource_type="account",
                    resource_id=teacher.username, resource_name=display_name, role="teacher", request=request)
        return {"status": "success", "username": teacher.username, "name": display_name, "department": dept, "scholar_id": full_id}
    except Exception as e:
        logging.error(f"create_teacher_profile: {e}")
        raise HTTPException(status_code=400, detail="Failed to create teacher profile")  # i18n: user-facing error message


@router.delete("/teacher/profiles/{username}", response_model=StatusResponse,
               summary="Delete a teacher profile",
               description="Deletes a teacher user by username. The default admin account cannot be deleted.",
               tags=["Teacher"],
               responses={400: {"description": "Cannot delete admin account"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def delete_teacher_profile(username: str, request: Request = None, admin_user: str = Depends(verify_admin)):
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
    await db_exec("DELETE FROM users WHERE username = ?", (username,))
    # Purge the deleted teacher's sessions and in-memory cache entries so
    # their old tokens stop authenticating immediately.
    await invalidate_tokens_for_user(username)
    await audit(action=Action.DELETE_ACCOUNT, username=admin_user, resource_type="account",
                resource_id=username, role="teacher", request=request)
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
    row = await db_fetch_one(
        "SELECT name, department, scholar_id, reset_required FROM users WHERE username = ?",
        (teacher_user,))
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
async def update_teacher_name(data: NameUpdate, request: Request = None, teacher_user: str = Depends(verify_teacher)):
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
    await db_exec("UPDATE users SET name = ? WHERE username = ?", (data.name.strip(), teacher_user))
    await audit(action=Action.CHANGE_SETTINGS, username=teacher_user, resource_type="profile",
                resource_name="name", changes={"name": {"new": data.name.strip()}}, request=request)
    return {"status": "ok"}


@router.post("/teacher/profile/department", response_model=StatusResponse,
             summary="Update department",
             description="Updates the department for the currently authenticated teacher.",
             tags=["Teacher"],
             responses={401: {"description": "Unauthorized"}})
async def update_teacher_department(data: DepartmentUpdate, request: Request = None, teacher_user: str = Depends(verify_teacher)):
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
    await db_exec("UPDATE users SET department = ? WHERE username = ?", (data.department.strip(), teacher_user))
    await audit(action=Action.CHANGE_SETTINGS, username=teacher_user, resource_type="profile",
                resource_name="department", changes={"department": {"new": data.department.strip()}}, request=request)
    return {"status": "ok"}
