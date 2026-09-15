"""Student routes: sync, analytics, profile, password."""
import os
import re
import base64
import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse
import logging
from app.database import PROFILE_ICONS_DIR
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.models import StudyTimeSync, SubjectTimeSync, StudentChangePasswordRequest, StatusResponse, StudentAnalyticsResponse, IconUploadResponse, StudentProfileResponse, BookmarkSync, QuizBestScoreResponse, QuizBestScoreUpdate
from app.dependencies import verify_student, verify_user, hash_password, verify_password, validate_password_strength, invalidate_tokens_for_user
from app.audit import audit, Action

router = APIRouter()


@router.post("/student/sync-study-time", response_model=StatusResponse, summary="Sync weekly study time", description="Updates the student's total study seconds and streak days for the current week. Uses an upsert pattern against the weekly_study table.", tags=["Sync"], responses={200: {"description": "Study time synced successfully"}})
async def sync_study_time(data: StudyTimeSync, student_id: str = Depends(verify_student)):
    """Sync a student's weekly study time and streak.

    Args:
        data: Study time payload including total_seconds and streak_days.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.
    """
    await db_exec(
        "INSERT INTO weekly_study (scholar_id, total_seconds, streak_days, updated_at) VALUES (?, ?, ?, datetime('now')) ON CONFLICT(scholar_id) DO UPDATE SET total_seconds = ?, streak_days = ?, updated_at = datetime('now')",
        (student_id, data.total_seconds, data.streak_days, data.total_seconds, data.streak_days),
    )
    return {"status": "ok"}


@router.post("/student/sync-subject-time", response_model=StatusResponse, summary="Sync per-subject study minutes", description="Replaces the student's subject-level study minutes breakdown with the provided data. Limited to 30 subjects per request.", tags=["Sync"], responses={200: {"description": "Subject time synced successfully"}, 400: {"description": "Too many subjects (max 30)"}})
async def sync_subject_time(data: SubjectTimeSync, student_id: str = Depends(verify_student)):
    """Sync a student's per-subject study minutes.

    Args:
        data: Subject time payload containing a list of subject name and minutes pairs.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.

    Raises:
        HTTPException 400: If more than 30 subjects are provided.
    """
    if len(data.subjects) > 30:
        raise HTTPException(status_code=400, detail="Too many subjects (max 30)")  # i18n: user-facing error message
    def _replace_subject_minutes(conn):
        """Swap the student's subject-minute rows for the synced list in one transaction."""
        c = conn.cursor()
        c.execute("DELETE FROM subject_minutes WHERE scholar_id = ?", (student_id,))
        c.executemany("INSERT INTO subject_minutes (scholar_id, subject_name, minutes, seconds) VALUES (?, ?, ?, ?)",
                      [(student_id, subj.name, subj.minutes, subj.seconds or subj.minutes * 60) for subj in data.subjects])
        conn.commit()
    await db_run(_replace_subject_minutes)
    return {"status": "ok"}


@router.get("/student/analytics", response_model=StudentAnalyticsResponse, summary="Get student analytics", description="Returns aggregated study minutes this week, streak days, total resources saved, and a per-subject breakdown of study minutes.", tags=["Student"], responses={200: {"description": "Analytics retrieved successfully"}})
async def get_analytics(student_id: str = Depends(verify_student)):
    """Get aggregated analytics for a student.

    Args:
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with study_minutes_this_week, streak_days, resources_saved, and a subjects list.
    """
    row = await db_fetch_one("""
        SELECT COALESCE(w.total_seconds, 0), COALESCE(w.streak_days, 0),
               COALESCE(dl.cnt, 0)
        FROM scholars s
        LEFT JOIN weekly_study w ON w.scholar_id = s.id
        LEFT JOIN (SELECT scholar_id, COUNT(*) AS cnt FROM scholar_downloads GROUP BY scholar_id) dl
               ON dl.scholar_id = s.id
        WHERE s.id = ?
    """, (student_id,))
    week_secs = row[0] if row else 0
    streak = row[1] if row else 0
    saved = row[2] if row else 0
    subject_rows = await db_fetch("SELECT subject_name, minutes, COALESCE(seconds, minutes * 60) FROM subject_minutes WHERE scholar_id = ? ORDER BY minutes DESC", (student_id,))
    subjects = [{"name": row[0], "minutes": row[1], "seconds": row[2]} for row in subject_rows]
    return {
        "study_minutes_this_week": week_secs // 60,
        "study_seconds_this_week": week_secs,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": subjects,
    }


@router.post("/student/profile/update", response_model=StatusResponse, summary="Update student profile", description="Updates the student's display name and/or grade. Only provided fields are updated.", tags=["Profile"], responses={200: {"description": "Profile updated successfully"}, 400: {"description": "Failed to update profile"}})
async def update_student_profile(data: dict, student_id: str = Depends(verify_student), request: Request = None):
    """Update a student's display name and grade.

    Args:
        data: Dict with optional name and grade fields.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.

    Raises:
        HTTPException 400: If the update operation fails.
    """
    name = data.get("name")
    grade = data.get("grade")
    ok = True
    def _update_profile(conn):
        """Apply the name/grade updates, recording success into ``ok``."""
        nonlocal ok
        try:
            c = conn.cursor()
            if name:
                c.execute("UPDATE scholars SET name = ? WHERE id = ?", (name.strip(), student_id))
            if grade is not None:
                c.execute("UPDATE scholars SET grade = ? WHERE id = ?", (grade.strip(), student_id))
            conn.commit()
        except Exception:
            ok = False
    await db_run(_update_profile)
    await audit(action=Action.CHANGE_SETTINGS, username=student_id, resource_type="profile",
                changes={"name": name, "grade": grade})
    if not ok:
        raise HTTPException(status_code=400, detail="Failed to update profile.")  # i18n: user-facing error message
    return {"status": "success"}


@router.post("/student/profile/icon", response_model=IconUploadResponse, summary="Upload profile icon", description="Uploads a base64-encoded profile image for the student. Validates file magic bytes to confirm the format and enforces a 500KB size limit. Supports PNG, JPG, GIF, and WebP.", tags=["Profile"], responses={200: {"description": "Icon uploaded successfully"}, 400: {"description": "Invalid image data, format, or size exceeded"}})
async def upload_profile_icon(data: dict, student_id: str = Depends(verify_student), request: Request = None):
    """Upload a base64-encoded profile icon for a student.

    Args:
        data: Icon upload payload with base64 image data and file extension.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with status and the saved filename.

    Raises:
        HTTPException 400: If the image data is invalid, too large, or the format is not allowed.
    """
    try:
        raw = base64.b64decode(data.get('image_data'))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data.")  # i18n: user-facing error message
    if len(raw) > 500 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 500KB)")  # i18n: user-facing error message
    ext = (data.get('image_ext') or 'png').replace(".", "")
    ALLOWED_MAGIC = {
        b'\x89PNG\r\n\x1a\n': 'png',
        b'\xff\xd8\xff': 'jpg',
        b'GIF89a': 'gif',
        b'GIF87a': 'gif',
        b'RIFF': 'webp',
    }
    if ext.lower() == 'jpeg':
        ext = 'jpg'
    is_valid = False
    for magic, fmt in ALLOWED_MAGIC.items():
        if raw[:len(magic)] == magic:
            if fmt == ext.lower():
                is_valid = True
                break
    if not is_valid:
        raise HTTPException(status_code=400, detail="Invalid image format")  # i18n: user-facing error message
    if ext not in ("png", "jpg", "gif", "webp"):
        ext = "png"
    safe_id = re.sub(r'[^A-Za-z0-9_-]', '_', student_id)
    filename = f"{safe_id}_icon.{ext}"
    filepath = os.path.join(PROFILE_ICONS_DIR, filename)
    def _write_icon():
        """Persist the decoded icon bytes to the profile_icons directory."""
        with open(filepath, "wb") as f:
            f.write(raw)
    await asyncio.to_thread(_write_icon)
    await audit(action=Action.CHANGE_SETTINGS, username=student_id, resource_type="profile",
                resource_name="icon", context={"filename": filename})
    return {"status": "ok", "filename": filename}


@router.get("/student/profile/icon/{scholar_id}", summary="Get profile icon", description="Returns the profile icon image file for the given scholar ID. Searches for PNG, JPG, JPEG, GIF, and WebP extensions.", tags=["Profile"], responses={200: {"description": "Profile icon image file"}, 404: {"description": "No profile icon found for the given scholar"}})
async def get_profile_icon(scholar_id: str, user: str = Depends(verify_user)):
    """Get a student's profile icon image.

    Args:
        scholar_id: The scholar ID to look up the icon for.

    Returns:
        FileResponse with the icon image.

    Raises:
        HTTPException 404: If no icon file exists for the given scholar ID.
    """
    safe_id = re.sub(r'[^A-Za-z0-9_-]', '_', scholar_id)
    for ext in ("png", "jpg", "jpeg", "gif", "webp"):
        path = os.path.join(PROFILE_ICONS_DIR, f"{safe_id}_icon.{ext}")
        if await asyncio.to_thread(os.path.exists, path):
            return FileResponse(path, media_type=f"image/{ext}")
    raise HTTPException(status_code=404, detail="No profile icon found.")  # i18n: user-facing error message


@router.post("/student/change-password", response_model=StatusResponse, summary="Change student password", description="Changes the student's password. When reset_required is set, old password is not needed. Otherwise verifies the current password. Clears the reset-required flag on success.", tags=["Auth", "Profile"], responses={200: {"description": "Password changed successfully"}, 400: {"description": "Incorrect current password, password not set, or change failed"}})
async def student_change_password(data: StudentChangePasswordRequest, student_id: str = Depends(verify_student), request: Request = None):
    """Change a student's password.

    Args:
        data: Change password request with new password. Old password is optional when reset_required is set.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.

    Raises:
        HTTPException 400: If the current password is incorrect, password is not set, or the update fails.
    """
    try:
        row = await db_fetch_one("SELECT hashed_password, reset_required FROM scholars WHERE id = ?", (student_id,))
        if not row or not row[0]:
            raise HTTPException(status_code=400, detail="Password not set. Contact your teacher.")
        reset_required = row["reset_required"]
        if not reset_required:
            if not data.old_password:
                raise HTTPException(status_code=400, detail="Current password is required.")
            password_ok = await asyncio.to_thread(verify_password, data.old_password, row[0])
            if not password_ok:
                raise HTTPException(status_code=400, detail="Incorrect current password.")
        valid, msg = validate_password_strength(data.new_password)
        if not valid:
            raise HTTPException(status_code=400, detail=msg)
        hashed = await asyncio.to_thread(hash_password, data.new_password)
        await db_exec("UPDATE scholars SET hashed_password = ?, reset_required = 0 WHERE id = ?", (hashed, student_id))
        await invalidate_tokens_for_user(student_id)
        await audit(action=Action.CHANGE_PASSWORD, username=student_id, resource_type="account",
                    severity="notice")
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"student_change_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to change password")


@router.get("/student/profile", response_model=StudentProfileResponse, summary="Get student profile", description="Returns the student's display name, grade, and scholar ID.", tags=["Profile"], responses={200: {"description": "Profile retrieved successfully"}, 404: {"description": "Student not found"}})
async def get_student_profile(student_id: str = Depends(verify_student)):
    """Get a student's profile information.

    Args:
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with name, grade, and scholar_id.

    Raises:
        HTTPException 404: If the student record is not found.
    """
    row = await db_fetch_one("SELECT name, grade, id FROM scholars WHERE id = ?", (student_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Student not found")  # i18n: user-facing error message
    return {"name": row[0], "grade": row[1] or "", "scholar_id": row[2]}


@router.post("/student/sync-bookmarks", response_model=StatusResponse, summary="Sync bookmarks", description="Replaces all server-side bookmarks with the provided list, then prunes rows that can never resolve again (deleted/missing resources, archived/missing courses). Draft courses are kept.", tags=["Sync"], responses={200: {"description": "Bookmarks synced successfully"}, 401: {"description": "Unauthorized"}})
async def sync_bookmarks(data: BookmarkSync, student_id: str = Depends(verify_student)):
    """Replace the student's server-side bookmarks with the synced list.

    Course saves (resource_type 'course') are stored opaquely with no
    validation on write. After replacing, prune tombstoned rows: resource
    bookmarks missing from resources or with status 'deleted', and course
    bookmarks missing from courses or with published = -1. Draft courses
    (published = 0) are kept since unpublish is reversible.
    """
    def _replace(conn):
        """Delete old bookmarks, insert the synced ones, then prune tombstones."""
        c = conn.cursor()
        c.execute("DELETE FROM student_bookmarks WHERE scholar_id = ?", (student_id,))
        if data.bookmarks:
            c.executemany("INSERT INTO student_bookmarks (scholar_id, resource_id, title, subject, grade, resource_type) VALUES (?, ?, ?, ?, ?, ?)",
                [(student_id, b.resource_id, b.title, b.subject, b.grade, b.resource_type) for b in data.bookmarks])
        c.execute("DELETE FROM student_bookmarks WHERE scholar_id = ? AND COALESCE(resource_type, '') != 'course' AND resource_id NOT IN (SELECT id FROM resources WHERE status != 'deleted')", (student_id,))
        c.execute("DELETE FROM student_bookmarks WHERE scholar_id = ? AND resource_type = 'course' AND resource_id NOT IN (SELECT id FROM courses WHERE published != -1)", (student_id,))
        conn.commit()
    await db_run(_replace)
    return {"status": "ok"}


@router.get("/student/bookmarks", response_model=BookmarkSync, summary="Get bookmarks", description="Returns the student's synced bookmarks, including course saves stored as resource_type 'course'.", tags=["Sync"], responses={200: {"description": "Bookmarks retrieved successfully"}, 401: {"description": "Unauthorized"}})
async def get_bookmarks(student_id: str = Depends(verify_student)):
    """Return the student's server-side bookmarks.

    Args:
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a bookmarks list of resource_id, title, subject, grade, and resource_type.
    """
    rows = await db_fetch("SELECT resource_id, title, subject, grade, resource_type FROM student_bookmarks WHERE scholar_id = ? ORDER BY saved_at", (student_id,))
    return {"bookmarks": [{"resource_id": r[0], "title": r[1] or "", "subject": r[2] or "", "grade": r[3] or "", "resource_type": r[4] or ""} for r in rows]}


@router.get("/student/quiz-best-score/{course_id}/{resource_id}", response_model=QuizBestScoreResponse, summary="Get best quiz score", description="Returns the student's best score, best attempt id, and total attempt count for a quiz.", tags=["Student"], responses={401: {"description": "Unauthorized"}})
async def get_quiz_best_score(course_id: str, resource_id: str, student_id: str = Depends(verify_student)):
    """Return the student's best recorded score for a quiz and how many attempts were made."""
    best = await db_fetch_one("SELECT best_score, best_attempt_id FROM quiz_best_scores WHERE scholar_id = ? AND course_id = ? AND resource_id = ?", (student_id, course_id, resource_id))
    count_row = await db_fetch_one("SELECT COUNT(*) FROM quiz_attempts WHERE student_id = ? AND course_id = ? AND resource_id = ?", (student_id, course_id, resource_id))
    return {
        "best_score": best["best_score"] if best else 0.0,
        "best_attempt_id": best["best_attempt_id"] if best else "",
        "attempts_count": count_row[0] if count_row else 0,
    }


@router.post("/student/quiz-best-score/{course_id}/{resource_id}", response_model=StatusResponse, summary="Update best quiz score", description="Upserts the student's best score, keeping the existing value when the new score is not higher. The referenced attempt must exist, belong to this student, and match this course/quiz; the accepted score never exceeds the server-graded attempt score.", tags=["Student"], responses={401: {"description": "Unauthorized"}, 403: {"description": "Attempt belongs to another student or course/quiz"}, 404: {"description": "Attempt not found"}})
async def update_quiz_best_score(course_id: str, resource_id: str, data: QuizBestScoreUpdate, student_id: str = Depends(verify_student)):
    """Record a new best score for a quiz if it beats the stored one.

    The client-reported score is never trusted outright: it is clamped to
    the server-graded score of the referenced attempt, which must exist,
    belong to this student, and match this course and quiz resource.

    Raises:
        HTTPException 404: If no attempt with this attempt_id exists.
        HTTPException 403: If the attempt belongs to another student or a
            different course/quiz than this endpoint is scoring.
    """
    attempt = await db_fetch_one(
        "SELECT student_id, course_id, resource_id, score FROM quiz_attempts WHERE id = ?",
        (data.attempt_id,))
    if attempt is None:
        raise HTTPException(status_code=404, detail="Attempt not found.")  # i18n: user-facing error message
    if (attempt["student_id"] != student_id or attempt["course_id"] != course_id
            or attempt["resource_id"] != resource_id):
        raise HTTPException(status_code=403, detail="Attempt does not belong to this student.")  # i18n: user-facing error message

    accepted_score = min(data.score, attempt["score"] if attempt["score"] is not None else 0.0)
    existing = await db_fetch_one("SELECT best_score FROM quiz_best_scores WHERE scholar_id = ? AND course_id = ? AND resource_id = ?", (student_id, course_id, resource_id))
    if existing and (existing["best_score"] or 0) >= accepted_score:
        return {"status": "ok"}
    await db_exec(
        "INSERT INTO quiz_best_scores (scholar_id, course_id, resource_id, best_score, best_attempt_id, updated_at) VALUES (?, ?, ?, ?, ?, datetime('now')) ON CONFLICT(scholar_id, course_id, resource_id) DO UPDATE SET best_score = ?, best_attempt_id = ?, updated_at = datetime('now')",
        (student_id, course_id, resource_id, accepted_score, data.attempt_id, accepted_score, data.attempt_id))
    return {"status": "ok"}
