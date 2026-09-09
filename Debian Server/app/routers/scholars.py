"""Scholar management routes: list, reset password, delete."""
import asyncio
import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.dependencies import hash_password, verify_teacher, verify_admin, invalidate_tokens_for_user
from app.models import StatusResponse, ScholarListItem
from app.audit import audit, Action

router = APIRouter()

# Fixed default a force-reset scholar logs in with. The account is marked
# reset_required, so the student must choose their own password immediately
# on next login: the window where a known password works is one login.
# Matches the documented "resets to the default" contract and the hub's
# default admin/hotspot credential. SECURITY NOTE: anyone who knows a reset
# just happened can log in as that student until they complete the forced
# change; acceptable on a single-classroom offline hub, never expose this
# endpoint beyond the teacher role (verify_teacher enforced below).
DEFAULT_RESET_PASSWORD = "lumina2026"


@router.get("/teacher/scholars", response_model=list[ScholarListItem],
            summary="List all scholars",
            description="Returns a list of all scholars ordered by name, with reset_required flag.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}})
async def get_scholars(teacher_user: str = Depends(verify_teacher)):
    """List all scholars.

    Returns:
        List of dicts with id, name, and reset_required fields.
    """
    rows = await db_fetch("SELECT id, name, reset_required, username FROM scholars ORDER BY name ASC")
    return [{"id": r[0], "name": r[1], "reset_required": r[2] or 0, "username": r[3] or ""} for r in rows]


@router.post("/teacher/scholars/reset-password/{scholar_id}", response_model=StatusResponse,
             summary="Reset student password",
             description="Resets a scholar's password to the default and marks reset_required.",
             tags=["Teacher"],
             responses={400: {"description": "Failed to reset password"}, 401: {"description": "Unauthorized"}})
async def teacher_reset_student_password(scholar_id: str, request: Request = None, teacher_user: str = Depends(verify_teacher)):
    """Reset a scholar's password to the default value.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Status dict indicating success.
    """
    row = await db_fetch_one("SELECT id, username FROM scholars WHERE id = ?", (scholar_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Scholar not found.")  # i18n: user-facing error message
    hashed = await asyncio.to_thread(hash_password, DEFAULT_RESET_PASSWORD)
    try:
        await db_exec(
            "UPDATE scholars SET hashed_password = ?, reset_required = 1 WHERE id = ?",
            (hashed, scholar_id),
        )
        # Kill all existing sessions so the old password stops authenticating immediately.
        await invalidate_tokens_for_user(row["id"])
        await audit(action=Action.RESET_PASSWORD, username=teacher_user, resource_type="account",
                    resource_id=scholar_id, target_user=scholar_id)
        return {"status": "success", "temporary_password": DEFAULT_RESET_PASSWORD}
    except Exception as e:
        logging.error(f"teacher_reset_student_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to reset password")  # i18n: user-facing error message


@router.delete("/teacher/scholars/{scholar_id}", response_model=StatusResponse,
               summary="Delete a scholar",
               description="Deletes a scholar and all associated activity logs and downloads. Admin-only: hard deletion of a student account is an admin action.",
               tags=["Teacher"],
               responses={400: {"description": "Failed to delete student"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}, 404: {"description": "Scholar not found"}})
async def teacher_delete_student(scholar_id: str, request: Request = None, admin_user: str = Depends(verify_admin)):
    """Delete a scholar and related records.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Status dict indicating success.
    """
    row = await db_fetch_one("SELECT id, username FROM scholars WHERE id = ?", (scholar_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Scholar not found.")  # i18n: user-facing error message
    # Kill all existing sessions before removing the account so old tokens
    # stop authenticating immediately.
    await invalidate_tokens_for_user(row["id"])
    try:
        def _delete_scholar(conn):
            """Delete the scholar and all dependent rows in one transaction."""
            conn.execute("DELETE FROM scholars WHERE id = ?", (scholar_id,))
            conn.execute("DELETE FROM activity_logs WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM subject_minutes WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM weekly_study WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM study_sessions WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM course_progress WHERE student_id = ?", (scholar_id,))
            conn.execute("DELETE FROM student_bookmarks WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM quiz_attempts WHERE student_id = ?", (scholar_id,))
            conn.execute("DELETE FROM quiz_best_scores WHERE scholar_id = ?", (scholar_id,))
            conn.execute("DELETE FROM flashcard_submissions WHERE student_id = ?", (scholar_id,))
            # Decrement enrollment counts for courses this student was enrolled in
            enrolled_courses = conn.execute("SELECT course_id FROM course_progress WHERE student_id = ?", (scholar_id,)).fetchall()
            for (cid,) in enrolled_courses:
                conn.execute("UPDATE courses SET enrollment_count = MAX(0, enrollment_count - 1) WHERE id = ?", (cid,))
            conn.execute("DELETE FROM course_progress WHERE student_id = ?", (scholar_id,))
            conn.execute("UPDATE users SET scholar_id = NULL WHERE scholar_id = ?", (scholar_id,))
            conn.commit()
        await db_run(_delete_scholar)
        # Remove profile icon files from disk
        import os
        from app.database import PROFILE_ICONS_DIR
        for ext in ('png', 'jpg', 'jpeg', 'webp'):
            icon_path = os.path.join(PROFILE_ICONS_DIR, f"{scholar_id}.{ext}")
            try:
                if os.path.exists(icon_path):
                    os.remove(icon_path)
            except OSError:
                pass
        await audit(action=Action.DELETE_ACCOUNT, username=admin_user, resource_type="account",
                    resource_id=scholar_id, target_user=scholar_id)
        return {"status": "success"}
    except Exception as e:
        logging.error(f"teacher_delete_student: {e}")
        raise HTTPException(status_code=400, detail="Failed to delete student")  # i18n: user-facing error message
