"""Student routes — sync, analytics, profile, password."""
import os
import re
import base64
import asyncio
import sqlite3
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from app.database import DB_PATH, PROFILE_ICONS_DIR, auto_register_if_new
from app.async_db import db_conn, db_execute, db_fetchone, db_fetchall
from app.models import StudyTimeSync, SubjectTimeSync, ProfileUpdate, IconUpload, StudentChangePasswordRequest
from app.dependencies import verify_student, hash_password, verify_password
from app.encryption import _invalidate_tokens_for_user

router = APIRouter()


@router.post("/sync/downloads", summary="Sync downloaded resource IDs", description="Records which resources the student has downloaded. Used for offline sync and restore across devices. Auto-registers the student if not already in the database.", tags=["Sync"], responses={200: {"description": "Download IDs recorded successfully"}})
async def sync_downloads(resource_ids: list[str], student_id: str = Depends(verify_student)):
    """Record downloaded resource IDs for a student.

    Args:
        resource_ids: List of resource IDs the student has downloaded.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.
    """
    await auto_register_if_new(student_id)
    async with db_conn() as conn:
        c = conn.cursor()
        for rid in resource_ids:
            c.execute("INSERT OR IGNORE INTO scholar_downloads (scholar_id, resource_id) VALUES (?, ?)", (student_id, rid))
        conn.commit()
    return {"status": "ok"}


@router.get("/sync/restore", summary="Restore download history", description="Returns the list of resource IDs previously downloaded by the student. Used to restore offline content on a new device or after reinstalling the app.", tags=["Sync"], responses={200: {"description": "Download history retrieved successfully"}})
async def restore_profile(student_id: str = Depends(verify_student)):
    """Restore a student's download history.

    Args:
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a download_history list of resource IDs.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT resource_id FROM scholar_downloads WHERE scholar_id = ?", (student_id,))
        downloads = [r[0] for r in c.fetchall()]
    return {"download_history": downloads}


@router.post("/student/sync-study-time", summary="Sync weekly study time", description="Updates the student's total study seconds and streak days for the current week. Uses an upsert pattern against the weekly_study table.", tags=["Sync"], responses={200: {"description": "Study time synced successfully"}})
async def sync_study_time(data: StudyTimeSync, student_id: str = Depends(verify_student)):
    """Sync a student's weekly study time and streak.

    Args:
        data: Study time payload including total_seconds and streak_days.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.
    """
    await auto_register_if_new(student_id)
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("INSERT INTO weekly_study (scholar_id, total_seconds, streak_days, updated_at) VALUES (?, ?, ?, datetime('now')) ON CONFLICT(scholar_id) DO UPDATE SET total_seconds = ?, streak_days = ?, updated_at = datetime('now')",
                  (student_id, data.total_seconds, data.streak_days, data.total_seconds, data.streak_days))
        conn.commit()
    return {"status": "ok"}


@router.post("/student/sync-subject-time", summary="Sync per-subject study minutes", description="Replaces the student's subject-level study minutes breakdown with the provided data. Limited to 30 subjects per request.", tags=["Sync"], responses={200: {"description": "Subject time synced successfully"}, 400: {"description": "Too many subjects (max 30)"}})
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
        raise HTTPException(status_code=400, detail="Too many subjects (max 30)")
    await auto_register_if_new(student_id)
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("DELETE FROM subject_minutes WHERE scholar_id = ?", (student_id,))
        for subj in data.subjects:
            c.execute("INSERT INTO subject_minutes (scholar_id, subject_name, minutes) VALUES (?, ?, ?)",
                      (student_id, subj.name, subj.minutes))
        conn.commit()
    return {"status": "ok"}


@router.get("/student/analytics", summary="Get student analytics", description="Returns aggregated study minutes this week, streak days, total resources saved, and a per-subject breakdown of study minutes.", tags=["Student"], responses={200: {"description": "Analytics retrieved successfully"}})
async def get_analytics(student_id: str = Depends(verify_student)):
    """Get aggregated analytics for a student.

    Args:
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with study_minutes_this_week, streak_days, resources_saved, and a subjects list.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT total_seconds, streak_days FROM weekly_study WHERE scholar_id = ?", (student_id,))
        row = c.fetchone()
        week_secs = row[0] if row else 0
        streak = row[1] if row and len(row) > 1 else 0
        c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE scholar_id = ?", (student_id,))
        saved = c.fetchone()[0]
        c.execute("SELECT subject_name, minutes FROM subject_minutes WHERE scholar_id = ? ORDER BY minutes DESC", (student_id,))
        subjects = [{"name": row[0], "minutes": row[1]} for row in c.fetchall()]
    return {
        "study_minutes_this_week": week_secs // 60,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": subjects,
    }


@router.post("/student/profile/update", summary="Update student profile", description="Updates the student's display name and/or grade. Only provided fields are updated.", tags=["Profile"], responses={200: {"description": "Profile updated successfully"}, 400: {"description": "Failed to update profile"}})
async def update_student_profile(data: dict, student_id: str = Depends(verify_student)):
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
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            if name:
                c.execute("UPDATE scholars SET name = ? WHERE id = ?", (name.strip(), student_id))
            if grade is not None:
                c.execute("UPDATE scholars SET grade = ? WHERE id = ?", (grade.strip(), student_id))
            conn.commit()
            return {"status": "success"}
        except Exception:
            raise HTTPException(status_code=400, detail="Failed to update profile.")


@router.post("/student/profile/icon", summary="Upload profile icon", description="Uploads a base64-encoded profile image for the student. Validates file magic bytes to confirm the format and enforces a 500KB size limit. Supports PNG, JPG, GIF, and WebP.", tags=["Profile"], responses={200: {"description": "Icon uploaded successfully"}, 400: {"description": "Invalid image data, format, or size exceeded"}})
async def upload_profile_icon(data: IconUpload, student_id: str = Depends(verify_student)):
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
        raw = base64.b64decode(data.image_data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data.")
    if len(raw) > 500 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 500KB)")
    ext = data.image_ext.replace(".", "")
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
        raise HTTPException(status_code=400, detail="Invalid image format")
    if ext not in ("png", "jpg", "jpeg", "gif", "webp"):
        ext = "png"
    safe_id = re.sub(r'[^A-Za-z0-9_-]', '_', student_id)
    filename = f"{safe_id}_icon.{ext}"
    filepath = os.path.join(PROFILE_ICONS_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(raw)
    return {"status": "ok", "filename": filename}


@router.get("/student/profile/icon/{scholar_id}", summary="Get profile icon", description="Returns the profile icon image file for the given scholar ID. Searches for PNG, JPG, JPEG, GIF, and WebP extensions.", tags=["Profile"], responses={200: {"description": "Profile icon image file"}, 404: {"description": "No profile icon found for the given scholar"}})
async def get_profile_icon(scholar_id: str):
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
        if os.path.exists(path):
            return FileResponse(path, media_type=f"image/{ext}")
    raise HTTPException(status_code=404, detail="No profile icon found.")


@router.post("/student/change-password", summary="Change student password", description="Changes the student's password after verifying the current password. Clears the reset-required flag on success.", tags=["Auth", "Profile"], responses={200: {"description": "Password changed successfully"}, 400: {"description": "Incorrect current password, password not set, or change failed"}})
async def student_change_password(data: StudentChangePasswordRequest, student_id: str = Depends(verify_student)):
    """Change a student's password.

    Args:
        data: Change password request with old and new passwords.
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with a status field indicating success.

    Raises:
        HTTPException 400: If the current password is incorrect, password is not set, or the update fails.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT hashed_password FROM scholars WHERE id = ?", (student_id,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=400, detail="Password not set. Contact your teacher.")
            if not row[0]:
                raise HTTPException(status_code=400, detail="Password not set. Contact your teacher.")
            if not verify_password(data.old_password, row[0]):
                raise HTTPException(status_code=400, detail="Incorrect current password.")
            hashed = hash_password(data.new_password)
            c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 0 WHERE id = ?", (hashed, student_id))
            conn.commit()
            await _invalidate_tokens_for_user(student_id)
            return {"status": "success"}
        except Exception as e:
            print(f"[ERROR] student_change_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to change password")


@router.get("/student/profile", summary="Get student profile", description="Returns the student's display name, grade, and scholar ID.", tags=["Profile"], responses={200: {"description": "Profile retrieved successfully"}, 404: {"description": "Student not found"}})
async def get_student_profile(student_id: str = Depends(verify_student)):
    """Get a student's profile information.

    Args:
        student_id: The authenticated student's ID, injected by the verify_student dependency.

    Returns:
        Dict with name, grade, and scholar_id.

    Raises:
        HTTPException 404: If the student record is not found.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT name, grade, id FROM scholars WHERE id = ?", (student_id,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Student not found")
        return {"name": row[0], "grade": row[1] or "", "scholar_id": row[2]}
