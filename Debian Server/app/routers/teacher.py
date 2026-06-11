"""Teacher/admin routes — scholars, students, subjects, uploads, analytics, admin actions, streaming."""
import os
import re
import uuid
import time
import shutil
import zipfile
import sqlite3
import asyncio
import logging
import subprocess
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Response, Query, status
from fastapi.responses import FileResponse, StreamingResponse
from app.database import DB_PATH, UPLOAD_DIR, THUMBNAILS_DIR, _startup_time, _admin_log_lock, log_admin_action
from app.async_db import db_conn
from app.models import (
    SubjectCreate, SubjectDeleteRequest, TeacherCreate, AdminStudentCreate,
    NameUpdate, DepartmentUpdate,
    ChangePasswordRequest, ForceChangePasswordRequest, LogRetentionUpdate,
    TimeSync,
)
from app.dependencies import hash_password, verify_password, validate_password_strength, verify_teacher, verify_admin
from app.encryption import _invalidate_tokens_for_user

router = APIRouter()

_thumbnail_semaphore = asyncio.Semaphore(2)


async def get_zim_upload_max_size():
    """Calculate max ZIM upload size (total disk minus 1 GB reserve)."""
    try:
        _disk = await asyncio.to_thread(shutil.disk_usage, "/")
        return max(0, _disk.total - 1024 * 1024 * 1024)
    except Exception:
        return 5000 * 1024 * 1024


def _find_video_thumb_time(file_path: str, max_search: int = 30) -> float:
    """Find a suitable thumbnail timestamp by skipping black intros via ffmpeg blackdetect.

    Args:
        file_path: Path to the video file.
        max_search: Maximum seconds into the video to search.

    Returns:
        Timestamp in seconds for the thumbnail, defaulting to 2.0 on failure.
    """
    try:
        result = subprocess.run(
            ["ffmpeg", "-i", file_path, "-vf", "blackdetect=d=0.3:pix_th=0.1",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=30
        )
        black_end = None
        for m in re.finditer(r'black_duration:([\d.]+)\s*black_start:([\d.]+)',
                             result.stderr):
            duration = float(m.group(1))
            start = float(m.group(2))
            end = start + duration
            if end > (black_end or 0):
                black_end = end
        if black_end is not None:
            t = black_end + 1.0
            return min(t, float(max_search))
    except Exception:
        pass
    return 2.0


# ---- Teacher: Students / Scholars ----


@router.get("/teacher/scholars",
            summary="List all scholars",
            description="Returns a list of all scholars ordered by name, with reset_required flag.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}})
async def get_scholars(teacher_user: str = Depends(verify_teacher)):
    """List all scholars.

    Returns:
        List of dicts with id, name, and reset_required fields.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT id, name, reset_required FROM scholars ORDER BY name ASC")
            rows = c.fetchall()
        except sqlite3.OperationalError:
            c.execute("SELECT id, name FROM scholars ORDER BY name ASC")
            rows = [(*r, 0) for r in c.fetchall()]
    return [{"id": r[0], "name": r[1], "reset_required": r[2] or 0} for r in rows]


@router.post("/teacher/scholars/reset-password/{scholar_id}",
             summary="Reset student password",
             description="Resets a scholar's password to the default and marks reset_required.",
             tags=["Teacher"],
             responses={400: {"description": "Failed to reset password"}, 401: {"description": "Unauthorized"}})
async def teacher_reset_student_password(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    """Reset a scholar's password to the default value.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Status dict indicating success.
    """
    hashed = hash_password("lumina2026")
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 1 WHERE id = ?", (hashed, scholar_id))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"teacher_reset_student_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to reset password")


@router.delete("/teacher/scholars/{scholar_id}",
               summary="Delete a scholar",
               description="Deletes a scholar and all associated activity logs and downloads.",
               tags=["Teacher"],
               responses={400: {"description": "Failed to delete student"}, 401: {"description": "Unauthorized"}})
async def teacher_delete_student(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    """Delete a scholar and related records.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Status dict indicating success.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("DELETE FROM scholars WHERE id = ?", (scholar_id,))
            c.execute("DELETE FROM activity_logs WHERE scholar_id = ?", (scholar_id,))
            c.execute("DELETE FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"teacher_delete_student: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete student")


@router.get("/teacher/students",
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
                {grade_filter}
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
            raise HTTPException(status_code=500, detail=f"Database error: {e}")

    return {"students": students}


@router.get("/teacher/student/{scholar_id}/analytics",
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
        c.execute("SELECT name FROM scholars WHERE id = ?", (scholar_id,))
        scholar = c.fetchone()
        if not scholar:
            raise HTTPException(status_code=404, detail="Student not found")
        c.execute("SELECT total_seconds, streak_days FROM weekly_study WHERE scholar_id = ?", (scholar_id,))
        row = c.fetchone()
        week_secs = row[0] if row else 0
        streak = row[1] if row and len(row) > 1 else 0
        c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
        saved = c.fetchone()[0]
        c.execute("SELECT subject_name, minutes FROM subject_minutes WHERE scholar_id = ? ORDER BY minutes DESC", (scholar_id,))
        subjects = [{"name": row[0], "minutes": row[1]} for row in c.fetchall()]
    return {
        "study_minutes_this_week": week_secs // 60,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": subjects,
    }


# ---- Subjects ----


@router.get("/subjects",
            summary="List all subjects",
            description="Returns all subjects with id, name, symbol, and class_name.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def get_subjects(teacher_user: str = Depends(verify_teacher)):
    """List all subjects ordered by class and name.

    Returns:
        List of dicts with id, name, symbol, and class_name.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT id, name, symbol, class_name FROM subjects ORDER BY class_name ASC, name ASC")
            rows = c.fetchall()
            return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": r[3] or "All Classes"} for r in rows]
        except sqlite3.OperationalError:
            c.execute("SELECT id, name, symbol FROM subjects ORDER BY name ASC")
            rows = c.fetchall()
            return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": "All Classes"} for r in rows]


@router.post("/teacher/subjects",
             summary="Create a subject",
             description="Creates a new subject with name, symbol, and optional class_name.",
             tags=["Subjects"],
             responses={400: {"description": "Failed to create subject"}, 401: {"description": "Unauthorized"}})
async def create_subject(subject: SubjectCreate, teacher_user: str = Depends(verify_teacher)):
    """Create a new subject.

    Args:
        subject: Subject creation payload.

    Returns:
        Dict with status, id, name, symbol, and class_name.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            class_val = subject.class_name or "All Classes"
            subj_id = f"SUBJ-{uuid.uuid4().hex[:8]}"
            c.execute("INSERT INTO subjects (id, name, symbol, class_name) VALUES (?, ?, ?, ?)",
                      (subj_id, subject.name, subject.symbol, class_val))
            conn.commit()
            return {"status": "success", "id": subj_id, "name": subject.name, "symbol": subject.symbol, "class_name": class_val}
        except Exception as e:
            logging.error(f"create_subject: {e}")
            raise HTTPException(status_code=400, detail="Failed to create subject")


@router.post("/teacher/subjects/delete",
             summary="Delete a subject",
             description="Deletes a subject by id or name, optionally transferring resources to another subject.",
             tags=["Subjects"],
             responses={400: {"description": "Invalid request or target subject missing"}, 401: {"description": "Unauthorized"}, 404: {"description": "Subject not found"}})
async def delete_subject(data: SubjectDeleteRequest, teacher_user: str = Depends(verify_teacher)):
    """Delete a subject and optionally transfer its resources.

    Args:
        data: Delete request with id/name and optional transfer_to.

    Returns:
        Status dict indicating success.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            if data.id:
                c.execute("SELECT name FROM subjects WHERE id = ?", (data.id,))
            else:
                c.execute("SELECT name FROM subjects WHERE name = ?", (data.name,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Subject not found.")
            subject_name = row[0]

            if data.transfer_to:
                c.execute("SELECT COUNT(*) FROM subjects WHERE name = ?", (data.transfer_to,))
                if c.fetchone()[0] == 0:
                    raise HTTPException(status_code=400, detail="Target subject does not exist.")
                c.execute("UPDATE resources SET subject = ? WHERE subject = ?", (data.transfer_to, subject_name))
            else:
                c.execute("SELECT file_path FROM resources WHERE subject = ?", (subject_name,))
                files = [r[0] for r in c.fetchall()]
                for fp in files:
                    if await asyncio.to_thread(os.path.exists, fp):
                        try:
                            await asyncio.to_thread(os.remove, fp)
                        except Exception as e:
                            logging.warning(f"Could not remove physical file {fp}: {e}")
                c.execute("DELETE FROM resources WHERE subject = ?", (subject_name,))

            if data.id:
                c.execute("DELETE FROM subjects WHERE id = ?", (data.id,))
            else:
                c.execute("DELETE FROM subjects WHERE name = ?", (data.name,))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"delete_subject: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete subject")


# ---- Teacher Profiles ----


@router.get("/teachers",
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
        try:
            c.execute("SELECT username, name, department, scholar_id, reset_required FROM users WHERE username != 'admin' ORDER BY name ASC")
            rows = c.fetchall()
        except sqlite3.OperationalError:
            c.execute("SELECT username, name, department, scholar_id FROM users WHERE username != 'admin' ORDER BY name ASC")
            rows = [(*r, 0) for r in c.fetchall()]
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "General", "scholar_id": r[3] or "", "reset_required": r[4] or 0} for r in rows]


@router.post("/teacher/profiles",
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
                raise HTTPException(status_code=400, detail="Username already exists.")

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
            raise HTTPException(status_code=400, detail="Failed to create teacher profile")


@router.delete("/teacher/profiles/{username}",
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
        raise HTTPException(status_code=400, detail="Cannot delete admin account.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("DELETE FROM users WHERE username = ?", (username,))
        conn.commit()
    return {"status": "success"}


@router.get("/teacher/me",
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


@router.post("/teacher/profile/name",
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
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET name = ? WHERE username = ?", (data.name.strip(), teacher_user))
        conn.commit()
    return {"status": "ok"}


@router.post("/teacher/profile/department",
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
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET department = ? WHERE username = ?", (data.department.strip(), teacher_user))
        conn.commit()
    return {"status": "ok"}


# ---- Teacher Password ----


@router.post("/teacher/change-password",
             summary="Change password",
             description="Changes the authenticated teacher's password after verifying the current password.",
             tags=["Teacher"],
             responses={400: {"description": "Incorrect password, weak password, or update failed"}, 401: {"description": "Unauthorized"}})
async def change_password(data: ChangePasswordRequest, teacher_user: str = Depends(verify_teacher)):
    """Change the authenticated user's password.

    Args:
        data: Change password request with old and new passwords.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If current password is incorrect or new password is weak.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT hashed_password FROM users WHERE username = ?", (teacher_user,))
        row = c.fetchone()
        if not row or not verify_password(data.old_password, row[0]):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Incorrect current password.")
        valid, msg = validate_password_strength(data.new_password)
        if not valid:
            raise HTTPException(status_code=400, detail=msg)
        new_hash = hash_password(data.new_password)
        c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
        conn.commit()
    await _invalidate_tokens_for_user(teacher_user)
    return {"status": "success"}


@router.post("/teacher/force-change-password",
             summary="Force change password",
             description="Changes password when reset_required is set (used for first-login forced password reset).",
             tags=["Teacher"],
             responses={400: {"description": "Reset not required, weak password, or update failed"}, 401: {"description": "Unauthorized"}})
async def force_change_password(data: ForceChangePasswordRequest, teacher_user: str = Depends(verify_teacher)):
    """Force a password change when reset is required.

    Args:
        data: Force change request with new password.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If reset is not required or new password is weak.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT reset_required FROM users WHERE username = ?", (teacher_user,))
            row = c.fetchone()
            if not row or not row[0]:
                raise HTTPException(status_code=400, detail="Password reset not required.")
            valid, msg = validate_password_strength(data.new_password)
            if not valid:
                raise HTTPException(status_code=400, detail=msg)
            new_hash = hash_password(data.new_password)
            c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
            conn.commit()
            await _invalidate_tokens_for_user(teacher_user)
            return {"status": "success"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"force_change_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to change password")


@router.post("/teacher/reset-password/{username}",
             summary="Admin reset teacher password",
             description="Resets a teacher's password to the default and marks reset_required. Admin-only.",
             tags=["Admin"],
             responses={400: {"description": "Cannot reset default admin or reset failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def force_reset_teacher_password(username: str, admin_user: str = Depends(verify_admin)):
    """Admin-only: reset a teacher's password to the default.

    Args:
        username: The teacher's username.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If username is 'admin' or the reset fails.
    """
    if username == "admin":
        raise HTTPException(status_code=400, detail="Cannot reset the default admin password. Use the Settings page to re-enable the default admin account.")
    hashed = hash_password("lumina2026")
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("UPDATE users SET hashed_password = ?, reset_required = 1 WHERE username = ?", (hashed, username))
            conn.commit()
            await _invalidate_tokens_for_user(username)
            await log_admin_action(admin_user, f"reset password for teacher {username}")
            return {"status": "success"}
        except Exception as e:
            logging.error(f"force_reset_teacher_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to reset password")


# ---- Default Admin ----


@router.post("/teacher/disable-default-admin",
             summary="Disable default admin",
             description="Disables the default admin account by setting its password to DISABLED. Requires at least one other teacher profile.",
             tags=["Admin"],
             responses={400: {"description": "No teacher profiles exist"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def disable_default_admin(admin_user: str = Depends(verify_admin)):
    """Disable the default admin account.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If no other teacher profiles exist.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT count(*) FROM users WHERE username != 'admin'")
        count = c.fetchone()[0]
        if count == 0:
            raise HTTPException(status_code=400, detail="Cannot disable default admin: No teacher profiles exist.")
        c.execute("UPDATE users SET hashed_password = 'DISABLED' WHERE username = 'admin'")
        conn.commit()
    await log_admin_action(admin_user, "disabled the default admin account")
    return {"status": "success"}


@router.post("/teacher/enable-default-admin",
             summary="Enable default admin",
             description="Re-enables the default admin account by resetting its password to the default.",
             tags=["Admin"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def enable_default_admin(admin_user: str = Depends(verify_admin)):
    """Re-enable the default admin account.

    Returns:
        Status dict indicating success.
    """
    hashed = hash_password("lumina2026")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET hashed_password = ? WHERE username = 'admin'", (hashed,))
        conn.commit()
    await log_admin_action(admin_user, "enabled the default admin account")
    return {"status": "success"}


@router.get("/teacher/default-admin-status",
            summary="Check default admin status",
            description="Returns whether the default admin account is currently enabled or disabled.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def default_admin_status(admin_user: str = Depends(verify_admin)):
    """Check if the default admin account is enabled.

    Returns:
        Dict with enabled boolean.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT hashed_password FROM users WHERE username = 'admin'")
        row = c.fetchone()
    if row and row[0] == 'DISABLED':
        return {"enabled": False}
    return {"enabled": True}


# ---- Resources / Catalog ----


@router.get("/resources",
            summary="List all resources",
            description="Returns the full resource catalog with id, title, file path, type, subject, grade, and modification time. Also mounted at /api/catalog for backward compatibility.",
            tags=["Resources"])
@router.get("/api/catalog",
            summary="List all resources (alias)",
            description="Alias for /resources — returns the full resource catalog. Kept for backward compatibility with legacy clients.",
            tags=["Resources"])
async def list_resources():
    """List all resources in the catalog.

    Returns:
        List of dicts with id, title, pdfUrl, type, subject, grade, and mtime.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT id, title, file_path, type, subject, grade FROM resources")
        except sqlite3.OperationalError:
            try:
                c.execute("SELECT id, title, file_path, type, subject, '' as grade FROM resources")
            except sqlite3.OperationalError:
                c.execute("SELECT id, title, file_path, type, 'General' as subject, '' as grade FROM resources")
        rows = c.fetchall()

    result = []
    for r in rows:
        fpath = r[2]
        mtime = 0.0
        try:
            mtime = await asyncio.to_thread(os.path.getmtime, fpath)
        except OSError:
            mtime = 0.0
        result.append({
            "id": r[0], "title": r[1],
            "pdfUrl": f"/files/{os.path.basename(fpath)}",
            "type": r[3], "subject": r[4] or "General",
            "grade": r[5] or "", "mtime": mtime,
        })
    return result


@router.get("/api/files",
            summary="List uploaded files",
            description="Returns a list of files in the upload directory with name and size.",
            tags=["Resources"],
            responses={401: {"description": "Unauthorized"}})
async def list_files(teacher_user: str = Depends(verify_teacher)):
    """List all files in the upload directory.

    Returns:
        List of dicts with name and size for each file.
    """
    if not os.path.exists(UPLOAD_DIR):
        return []
    return await asyncio.to_thread(lambda: [
        {"name": f, "size": os.path.getsize(os.path.join(UPLOAD_DIR, f))}
        for f in os.listdir(UPLOAD_DIR)
        if os.path.isfile(os.path.join(UPLOAD_DIR, f))
    ])


@router.get("/api/limits",
            summary="Get upload limits",
            description="Returns the maximum allowed ZIM upload size based on available disk space.",
            tags=["Resources"],
            responses={401: {"description": "Unauthorized"}})
async def get_limits(teacher_user: str = Depends(verify_teacher)):
    """Get upload size limits.

    Returns:
        Dict with zim_upload_max_size in bytes.
    """
    return {"zim_upload_max_size": await get_zim_upload_max_size()}


# ---- Uploads ----


@router.post("/teacher/upload",
             summary="Upload a resource",
             description="Uploads a file as a learning resource with title, type, subject, and optional grade. Rejects uploads when disk is below 2 GB free.",
             tags=["Resources"],
             responses={400: {"description": "File too large or invalid"}, 401: {"description": "Unauthorized"}, 499: {"description": "Client disconnected"}, 507: {"description": "Insufficient storage"}})
async def upload_resource(title: str, type: str, subject: str = "General", grade: str = "",
                          file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Upload a file as a learning resource.

    Args:
        title: Display title for the resource.
        type: Resource type (textbook, videos, notes, pyq, pastPaper, kiwix).
        subject: Subject name (defaults to "General").
        grade: Optional grade level.
        file: The uploaded file (max 100 MB).
        request: FastAPI request object for disconnect detection.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 507: If disk space is below 2 GB.
        HTTPException 400: If file exceeds 100 MB.
        HTTPException 499: If client disconnects mid-upload.
    """
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    free_gb = free // (2**30)
    if free_gb < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'unnamed_file')
    file_path = os.path.join(UPLOAD_DIR, safe_filename)
    chunk_size = 64 * 1024
    total_size = 0
    with open(file_path, "wb") as f:
        while True:
            chunk = await file.read(chunk_size)
            if not chunk:
                break
            total_size += len(chunk)
            if total_size > 100 * 1024 * 1024:
                raise HTTPException(status_code=400, detail="File too large")
            await asyncio.to_thread(f.write, chunk)
    if request and await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
        await file.close()
        try:
            c.execute("INSERT INTO resources (title, file_path, type, subject, grade) VALUES (?, ?, ?, ?, ?)",
                      (title, file_path, type, subject, grade))
        except sqlite3.OperationalError:
            try:
                c.execute("INSERT INTO resources (title, file_path, type, subject) VALUES (?, ?, ?, ?)",
                          (title, file_path, type, subject))
            except sqlite3.OperationalError:
                c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)",
                          (title, file_path, type))
        conn.commit()
    return {"status": "success"}


@router.post("/teacher/upload-zim",
             summary="Upload ZIM archive",
             description="Uploads and extracts a ZIM archive (as a ZIP) into the zim_pages directory. Rejects uploads when disk is below 2 GB free or file exceeds the computed limit.",
             tags=["Resources"],
             responses={400: {"description": "Invalid archive or filename"}, 401: {"description": "Unauthorized"}, 413: {"description": "File too large"}, 499: {"description": "Client disconnected"}, 507: {"description": "Insufficient storage"}})
async def upload_zim(file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Upload and extract a ZIM archive.

    Args:
        file: The zipped ZIM archive.
        request: FastAPI request object for disconnect detection.

    Returns:
        Dict with status and list of imported filenames.
    Raises:
        HTTPException 507: If disk space is below 2 GB.
        HTTPException 413: If file exceeds the max upload size.
        HTTPException 400: If the ZIP is invalid or contains path traversal.
        HTTPException 499: If client disconnects.
    """
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    free_gb = free // (2**30)
    if free_gb < 2:
        raise HTTPException(status_code=507, detail="Insufficient storage space for ZIM upload.")
    if not file.filename:
        raise HTTPException(status_code=400, detail="Uploaded file has no filename.")

    tmp_dir = os.path.join(UPLOAD_DIR, f"tmp_{uuid.uuid4().hex}")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zip')
    archive_path = os.path.join(tmp_dir, safe_filename)
    os.makedirs(tmp_dir, exist_ok=True)

    chunk_size = 64 * 1024
    total_size = 0
    max_size = await get_zim_upload_max_size()
    with open(archive_path, "wb") as f:
        while True:
            chunk = await file.read(chunk_size)
            if not chunk:
                break
            total_size += len(chunk)
            if total_size > max_size:
                raise HTTPException(
                    status_code=413,
                    detail=f"ZIM upload exceeds maximum size limit of {max_size // (1024 * 1024)} MiB."
                )
            await asyncio.to_thread(f.write, chunk)
    if request and await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")

    def _process_archive():
        """Extract ZIP, validate paths, move HTML files to zim_pages dir. Runs in worker thread."""
        try:
            with zipfile.ZipFile(archive_path, "r") as zip_ref:
                for entry in zip_ref.namelist():
                    if '..' in entry or entry.startswith('/'):
                        raise HTTPException(status_code=400, detail="ZIP contains invalid path entries.")
                zip_ref.extractall(tmp_dir)
            imported = []
            zim_target_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "zim_pages")
            os.makedirs(zim_target_dir, exist_ok=True)
            for root, _, files in os.walk(tmp_dir):
                for fname in files:
                    if not fname.lower().endswith('.html'):
                        continue
                    src = os.path.join(root, fname)
                    if "__" not in fname:
                        article_id = uuid.uuid4().hex[:8].upper()
                        title = os.path.splitext(fname)[0]
                        dest_name = f"{article_id}__{title}.html"
                    else:
                        dest_name = fname
                    dest_path = os.path.join(zim_target_dir, dest_name)
                    shutil.move(src, dest_path)
                    imported.append(dest_name)
            return imported
        except zipfile.BadZipFile:
            raise HTTPException(status_code=400, detail="Invalid ZIM/ZIP archive.")
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=400, detail="Failed to extract archive.")
        finally:
            if os.path.exists(tmp_dir):
                shutil.rmtree(tmp_dir, ignore_errors=True)

    imported = await asyncio.to_thread(_process_archive)
    return {"status": "success", "imported": imported}


@router.post("/teacher/import-server-file",
             summary="Import server-side file",
             description="Registers an already-uploaded file on the server as a learning resource in the database.",
             tags=["Resources"],
             responses={400: {"description": "Invalid filename"}, 401: {"description": "Unauthorized"}, 404: {"description": "File not found on server"}})
async def import_server_file(filename: str, title: str, type: str, subject: str = "General", teacher_user: str = Depends(verify_teacher)):
    """Register an existing server file as a resource.

    Args:
        filename: Name of the file (must not contain path traversal).
        title: Display title for the resource.
        type: Resource type.
        subject: Subject name (defaults to "General").

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If filename contains invalid characters.
        HTTPException 404: If file does not exist on the server.
    """
    if '..' in filename or '/' in filename or '\\' in filename:
        raise HTTPException(status_code=400, detail="Invalid filename.")
    file_path = os.path.join(UPLOAD_DIR, os.path.basename(filename))
    if not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found on server.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
        try:
            c.execute("INSERT INTO resources (title, file_path, type, subject) VALUES (?, ?, ?, ?)",
                      (title, file_path, type, subject))
        except sqlite3.OperationalError:
            c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)",
                      (title, file_path, type))
        conn.commit()
    return {"status": "success"}


@router.delete("/teacher/resources/{resource_id}",
               summary="Delete a resource",
               description="Deletes a resource by id, including its physical file and associated download records.",
               tags=["Resources"],
               responses={400: {"description": "Failed to delete resource"}, 401: {"description": "Unauthorized"}, 404: {"description": "Resource not found"}})
async def delete_resource(resource_id: int, teacher_user: str = Depends(verify_teacher)):
    """Delete a resource and its physical file.

    Args:
        resource_id: The resource database id.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 404: If resource does not exist.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT file_path FROM resources WHERE id = ?", (resource_id,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Resource not found.")
            file_path = row[0]
            if await asyncio.to_thread(os.path.exists, file_path):
                try:
                    await asyncio.to_thread(os.remove, file_path)
                except Exception as e:
                    logging.warning(f"Could not remove physical file {file_path}: {e}")
            c.execute("DELETE FROM resources WHERE id = ?", (resource_id,))
            c.execute("DELETE FROM scholar_downloads WHERE resource_id = ?", (str(resource_id),))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"delete_resource: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete resource")


# ---- Grades ----


@router.get("/grades",
            summary="List all grades",
            description="Returns all grade levels ordered by name.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def get_grades(teacher_user: str = Depends(verify_teacher)):
    """List all grade levels.

    Returns:
        List of dicts with name for each grade.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT name FROM grades ORDER BY name ASC")
        rows = c.fetchall()
    return [{"name": r[0]} for r in rows]


@router.post("/grades",
             summary="Create a grade",
             description="Creates a new grade level with a unique name (max 50 characters).",
             tags=["Subjects"],
             responses={400: {"description": "Missing name, too long, or duplicate"}, 401: {"description": "Unauthorized"}})
async def create_grade(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Create a new grade level.

    Args:
        data: Dict with a name field.

    Returns:
        Dict with status and the created name.
    Raises:
        HTTPException 400: If name is missing, too long, or already exists.
    """
    name = data.get("name", "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Grade name is required.")
    if len(name) > 50:
        raise HTTPException(status_code=400, detail="Grade name too long (max 50 characters).")
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("INSERT INTO grades (name) VALUES (?)", (name,))
            conn.commit()
            return {"status": "success", "name": name}
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="Grade already exists.")


@router.delete("/grades/{name}",
               summary="Delete a grade",
               description="Deletes a grade level, optionally transferring resources to another grade first.",
               tags=["Subjects"],
               responses={400: {"description": "Target grade not found"}, 401: {"description": "Unauthorized"}})
async def delete_grade(name: str, transfer_to: str = None, teacher_user: str = Depends(verify_teacher)):
    """Delete a grade level.

    Args:
        name: The grade name to delete.
        transfer_to: Optional grade to transfer resources to before deletion.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If target grade does not exist.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        if transfer_to:
            c.execute("SELECT COUNT(*) FROM grades WHERE name = ?", (transfer_to,))
            if c.fetchone()[0] == 0:
                raise HTTPException(status_code=400, detail="Target grade does not exist.")
            c.execute("UPDATE resources SET grade = ? WHERE grade = ?", (transfer_to, name))
        else:
            c.execute("SELECT file_path FROM resources WHERE grade = ?", (name,))
            files = c.fetchall()
            for (fp,) in files:
                if await asyncio.to_thread(os.path.exists, fp):
                    await asyncio.to_thread(os.remove, fp)
            c.execute("DELETE FROM resources WHERE grade = ?", (name,))
        c.execute("DELETE FROM grades WHERE name = ?", (name,))
        conn.commit()
    return {"status": "success"}


# ---- Streaming & Thumbnails ----


@router.get("/api/stream/{filename:path}",
            summary="Stream a file",
            description="Streams a file with HTTP Range support for partial content (206). Used for video playback with seek support.",
            tags=["Resources"],
            responses={404: {"description": "File not found"}, 416: {"description": "Range not satisfiable"}})
async def stream_file(filename: str, request: Request):
    """Stream a file with HTTP Range support.

    Args:
        filename: Relative path within the upload directory.
        request: FastAPI request for Range header inspection.

    Returns:
        StreamingResponse (206 Partial Content) or FileResponse (200).
    Raises:
        HTTPException 404: If the file does not exist.
        HTTPException 416: If the Range header is invalid.
    """
    file_path = os.path.join(UPLOAD_DIR, filename)
    if not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")
    file_size = await asyncio.to_thread(os.path.getsize, file_path)
    range_header = request.headers.get("range")
    if range_header:
        range_val = range_header.replace("bytes=", "")
        if range_val.startswith("-"):
            suffix = int(range_val[1:])
            start = max(0, file_size - suffix)
            end = file_size - 1
        else:
            start_str, _, end_str = range_val.partition("-")
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else file_size - 1
        if start >= file_size:
            raise HTTPException(status_code=416, detail="Range not satisfiable")
        content_length = end - start + 1

        async def _stream_chunk():
            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = content_length
                while remaining > 0:
                    chunk = await asyncio.to_thread(f.read, min(65536, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk

        return StreamingResponse(
            _stream_chunk(),
            status_code=206,
            media_type="application/octet-stream",
            headers={
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(content_length),
                "Accept-Ranges": "bytes",
            }
        )
    return FileResponse(file_path, headers={"Accept-Ranges": "bytes"})


@router.get("/api/thumbnail/{resource_id}",
            summary="Get resource thumbnail",
            description="Returns a cached or generated thumbnail for a resource. Supports PDF (via PyMuPDF) and video (via ffmpeg with black-intro skip).",
            tags=["Resources"],
            responses={404: {"description": "Resource, file, or thumbnail not found"}, 500: {"description": "Thumbnail generation error"}})
async def resource_thumbnail(resource_id: int):
    """Get a thumbnail image for a resource.

    Args:
        resource_id: The resource database id.

    Returns:
        PNG image (FileResponse) or 404.
    Raises:
        HTTPException 404: If resource, file, or thumbnail is unavailable.
        HTTPException 500: If thumbnail generation fails unexpectedly.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT file_path, type FROM resources WHERE id = ?", (resource_id,))
        row = c.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found")
    file_path, rtype = row
    thumb_path = os.path.join(THUMBNAILS_DIR, f"{resource_id}.png")
    if await asyncio.to_thread(os.path.exists, thumb_path):
        return FileResponse(thumb_path, media_type="image/png")
    if not await asyncio.to_thread(os.path.exists, file_path):
        raise HTTPException(status_code=404, detail="File not found")
    async with _thumbnail_semaphore:
        try:
            if rtype in ("textbook", "notes", "pyq", "pastPaper"):
                try:
                    import fitz

                    def _gen_pdf_thumb(fp, tp):
                        """Generate a 0.3x PNG thumbnail from the first page of a PDF. Runs in worker thread."""
                        doc = fitz.open(fp)
                        try:
                            pix = doc[0].get_pixmap(matrix=fitz.Matrix(0.3, 0.3))
                            pix.save(tp)
                        finally:
                            doc.close()
                    await asyncio.to_thread(_gen_pdf_thumb, file_path, thumb_path)
                except ImportError:
                    raise HTTPException(status_code=404, detail="Thumbnail unavailable (PyMuPDF not installed)")
            elif rtype == "videos":
                thumb_time = await asyncio.to_thread(_find_video_thumb_time, file_path)
                ss = f"{int(thumb_time // 3600):02d}:{int((thumb_time % 3600) // 60):02d}:{int(thumb_time % 60):02d}"
                result = await asyncio.to_thread(lambda: subprocess.run(
                    ["ffmpeg", "-i", file_path, "-ss", ss, "-vframes", "1", "-vf", "scale=320:-1", thumb_path, "-y"],
                    capture_output=True, timeout=15
                ))
                if result.returncode != 0 or not os.path.exists(thumb_path):
                    raise HTTPException(status_code=404, detail="Thumbnail generation failed")
            else:
                raise HTTPException(status_code=404, detail="No thumbnail for this type")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Thumbnail error: {e}")
    return FileResponse(thumb_path, media_type="image/png")


# ---- Stats ----


@router.get("/stats",
            summary="Get hub statistics",
            description="Returns scholar count, resource count, subject count, disk usage, battery percentage, and server uptime.",
            tags=["System"])
async def get_stats():
    """Get aggregate hub statistics.

    Returns:
        Dict with scholars, resources, subjects counts, storage info,
        battery_percent, uptime string, and disk_usage.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT COUNT(*) FROM scholars")
            scholar_count = c.fetchone()[0]
        except Exception:
            scholar_count = 0
        try:
            c.execute("SELECT COUNT(*) FROM resources")
            resource_count = c.fetchone()[0]
        except Exception:
            resource_count = 0
        try:
            c.execute("SELECT COUNT(*) FROM subjects")
            subject_count = c.fetchone()[0]
        except Exception:
            subject_count = 0
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    battery_percent = 100
    try:
        if await asyncio.to_thread(os.path.exists, "/sys/class/power_supply/BAT0/capacity"):
            def _read_battery():
                """Read battery percentage from sysfs. Runs in worker thread."""
                with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
                    return int(f.read().strip())
            battery_percent = await asyncio.to_thread(_read_battery)
    except Exception:
        pass
    uptime_secs = int(time.time() - _startup_time)
    hours, rem = divmod(uptime_secs, 3600)
    mins, secs = divmod(rem, 60)
    uptime_str = f"{hours}h {mins}m" if hours else f"{mins}m {secs}s"
    du = used
    dt = total
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if du < 1024:
            used_str = f"{du:.1f} {unit}"
            total_str = f"{dt:.1f} {unit}"
            break
        du /= 1024
        dt /= 1024
    return {"scholars": scholar_count, "resources": resource_count, "subjects": subject_count,
            "storage": f"{used_str} / {total_str}", "storage_percent": (used / total) * 100,
            "battery_percent": battery_percent, "uptime": uptime_str, "disk_usage": f"{used_str} / {total_str}"}


@router.get("/system/stats",
            summary="System health check",
            description="Simple health-check endpoint returning a healthy status. Requires teacher authentication.",
            tags=["System"],
            responses={401: {"description": "Unauthorized"}})
async def system_stats(teacher_user: str = Depends(verify_teacher)):
    """Simple system health check.

    Returns:
        Dict with status set to "healthy".
    """
    return {"status": "healthy"}


@router.post("/system/sync-time",
             summary="Sync server time",
             description="Sets the server system time via the date command. Admin-only.",
             tags=["System"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def sync_time(data: TimeSync, admin_user: str = Depends(verify_admin)):
    """Synchronise the server's system clock.

    Args:
        data: TimeSync payload with current_time in YYYY-MM-DD HH:MM:SS format.

    Returns:
        Dict with status ("ok" on success, "failed" on invalid input or error).
    """
    try:
        if not data.current_time or len(data.current_time) >= 64:
            return {"status": "failed"}
        if not re.match(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$', data.current_time):
            return {"status": "failed"}
        proc = await asyncio.create_subprocess_exec(
            "date", "-s", data.current_time,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        logging.info(f"Time Synced: {data.current_time}")
        return {"status": "ok"}
    except Exception:
        return {"status": "failed"}


# ---- Admin Log ----


@router.get("/admin/log",
            summary="View admin audit log",
            description="Returns the most recent admin action log entries. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def admin_log(limit: int = 20, admin_user: str = Depends(verify_admin)):
    """Read the admin audit log.

    Args:
        limit: Maximum number of log lines to return (default 20).

    Returns:
        Dict with a log list of trimmed log lines.
    """
    async with _admin_log_lock:
        try:
            def _read_log():
                """Read the last N lines from the admin audit log. Runs in worker thread."""
                try:
                    with open("data/admin_actions.log", "r") as f:
                        return [line.strip() for line in f.readlines()[-limit:]]
                except FileNotFoundError:
                    return []
            log_lines = await asyncio.to_thread(_read_log)
            return {"log": log_lines}
        except FileNotFoundError:
            return {"log": []}


@router.get("/api/admin/settings",
            summary="Get admin settings",
            description="Returns current admin settings (log retention policy). Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def get_admin_settings(admin_user: str = Depends(verify_admin)):
    """Get current admin settings.

    Returns:
        Dict with log_retention policy value (defaults to "30d").
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT value FROM settings WHERE key = 'log_retention'")
        row = c.fetchone()
    return {"log_retention": row[0] if row else "30d"}


@router.post("/api/admin/settings",
             summary="Update admin settings",
             description="Updates the log retention policy. Admin-only. Valid policies: 24h, 7d, 30d, 3m, 6m, never, none.",
             tags=["Admin"],
             responses={400: {"description": "Invalid retention policy"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def set_admin_settings(data: LogRetentionUpdate, admin_user: str = Depends(verify_admin)):
    """Update the log retention policy.

    Args:
        data: LogRetentionUpdate with a policy field.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If the policy value is not recognized.
    """
    if data.policy not in ("24h", "7d", "30d", "3m", "6m", "never", "none"):
        raise HTTPException(status_code=400, detail="Invalid log retention policy.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('log_retention', ?)", (data.policy,))
        conn.commit()
    await log_admin_action(admin_user, f"changed log retention policy to {data.policy}")
    return {"status": "success"}


@router.get("/api/admin/admins",
            summary="List admin accounts",
            description="Returns all admin user profiles. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def list_admins(admin_user: str = Depends(verify_admin)):
    """List all admin users.

    Returns:
        List of dicts with username, name, department, and reset_required.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT username, name, department, reset_required FROM users WHERE role = 'admin' ORDER BY name ASC")
            rows = c.fetchall()
        except sqlite3.OperationalError:
            c.execute("SELECT username, name, department, '' as reset_required FROM users WHERE username != 'admin' ORDER BY name ASC")
            rows = c.fetchall()
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "System", "reset_required": r[3] or 0} for r in rows]


@router.post("/api/admin/create",
             summary="Create admin account",
             description="Creates a new admin user. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_admin(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a new admin account.

    Args:
        data: TeacherCreate payload with username, password, name, and department.

    Returns:
        Dict with status, username, name, and scholar_id.
    Raises:
        HTTPException 400: If the username is already taken.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT username FROM users WHERE username = ?", (data.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")
            display_name = data.name or data.username
            dept = data.department or "System"
            admin_id = f"LUMINA_01-T{uuid.uuid4().hex}"
            hashed_pwd = hash_password(data.password)
            c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'admin')",
                      (data.username, hashed_pwd, display_name, dept, admin_id))
            conn.commit()
            await log_admin_action(admin_user, f"created admin account '{data.username}'")
            return {"status": "success", "username": data.username, "name": display_name, "scholar_id": admin_id}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"create_admin: {e}")
            raise HTTPException(status_code=400, detail="Failed to create admin account")


@router.post("/api/admin/create-teacher",
             summary="Create teacher account (admin)",
             description="Creates a new teacher user with the teacher role. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_teacher(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a new teacher account (admin action).

    Args:
        data: TeacherCreate payload with username, password, name, and department.

    Returns:
        Dict with status, username, name, and scholar_id.
    Raises:
        HTTPException 400: If the username is already taken.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT username FROM users WHERE username = ?", (data.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")
            display_name = data.name or data.username
            dept = data.department or "General"
            teacher_id = f"LUMINA_01-T{uuid.uuid4().hex}"
            hashed_pwd = hash_password(data.password)
            c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'teacher')",
                      (data.username, hashed_pwd, display_name, dept, teacher_id))
            conn.commit()
            await log_admin_action(admin_user, f"created teacher account '{data.username}'")
            return {"status": "success", "username": data.username, "name": display_name, "scholar_id": teacher_id}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"create_teacher: {e}")
            raise HTTPException(status_code=400, detail="Failed to create teacher account")


@router.post("/api/admin/create-student",
             summary="Create student account (admin)",
             description="Creates a new student scholar account. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_student(data: AdminStudentCreate, admin_user: str = Depends(verify_admin)):
    """Create a new student account (admin action).

    Args:
        data: AdminStudentCreate payload with username, optional password, name, and grade.

    Returns:
        Dict with status, username, name, and scholar_id.
    Raises:
        HTTPException 400: If the username is already taken or creation fails.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT id FROM scholars WHERE username = ?", (data.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")
            display_name = data.name or data.username
            scholar_id = f"LUMINA_01-{uuid.uuid4().hex}"
            pwd = data.password or "lumina2026"
            hashed_pwd = hash_password(pwd)
            if data.grade:
                c.execute("INSERT INTO scholars (id, username, name, hashed_password, reset_required, grade) VALUES (?, ?, ?, ?, 0, ?)",
                          (scholar_id, data.username, display_name, hashed_pwd, data.grade))
            else:
                c.execute("INSERT INTO scholars (id, username, name, hashed_password, reset_required) VALUES (?, ?, ?, ?, 0)",
                          (scholar_id, data.username, display_name, hashed_pwd))
            conn.commit()
            await log_admin_action(admin_user, f"created student account '{data.username}'")
            return {"status": "success", "username": data.username, "name": display_name, "scholar_id": scholar_id}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"create_student: {e}")
            raise HTTPException(status_code=400, detail="Failed to create student account")


@router.get("/api/admin/logs/download",
            summary="Download admin audit logs",
            description="Downloads admin action logs as a plain-text file, optionally filtered by duration. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def download_admin_logs(duration: str = "all", admin_user: str = Depends(verify_admin)):
    """Download admin audit log entries as a text file.

    Args:
        duration: Filter duration ("24h", "7d", "30d", "3m", "6m", or "all").

    Returns:
        Plain-text Response with log content and Content-Disposition header.
    """
    if not await asyncio.to_thread(os.path.exists, "data/admin_actions.log"):
        return Response(content="No logs found.", media_type="text/plain")

    ALLOWED_DURATIONS = {"24h", "7d", "30d", "3m", "6m", "all"}
    if duration not in ALLOWED_DURATIONS:
        duration = "all"

    cutoff = None
    now = datetime.now().timestamp()
    if duration == "24h":
        cutoff = now - 24 * 3600
    elif duration == "7d":
        cutoff = now - 7 * 24 * 3600
    elif duration == "30d":
        cutoff = now - 30 * 24 * 3600
    elif duration == "3m":
        cutoff = now - 90 * 24 * 3600
    elif duration == "6m":
        cutoff = now - 180 * 24 * 3600

    def _filter_log_file():
        """Read and filter admin audit log by duration cutoff. Runs in worker thread."""
        try:
            result = []
            with open("data/admin_actions.log", "r") as f:
                for line in f:
                    if cutoff is None:
                        result.append(line)
                    else:
                        parts = line.split(" - ", 1)
                        try:
                            log_time = datetime.fromisoformat(parts[0])
                            if log_time.timestamp() >= cutoff:
                                result.append(line)
                        except Exception:
                            result.append(line)
            return "".join(result)
        except FileNotFoundError:
            return ""

    content = await asyncio.to_thread(_filter_log_file)
    if not content:
        return Response(content="No logs found.", media_type="text/plain")
    return Response(
        content=content,
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=admin_logs_{duration}.txt"}
    )
