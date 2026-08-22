"""Resource upload, edit, soft-delete, and standalone quiz creation routes."""
import os
import uuid
import asyncio
import logging
import shutil
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query
from app.database import UPLOAD_DIR, gen_composite_uid
from app.audit import audit, Action
from app.async_db import db_exec, db_fetch_one, db_run
from app.dependencies import verify_teacher
from app.models import UploadResponse, DeleteResourceResponse
from app.routers.resource_catalog import invalidate_catalog_cache
from app.routers.teacher_courses import _write_chunked

router = APIRouter()

# Shared upload allowlists (also imported by teacher_course_resources.py).
# No .svg/.html/.js: those render as executable content when served.
ALLOWED_EXTENSIONS = {
    '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.odt', '.ods', '.odp',
    '.txt', '.rtf', '.csv', '.json',
    '.mp4', '.webm', '.mkv', '.avi', '.mov', '.flv',
    '.mp3', '.wav', '.ogg', '.m4a',
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp',
    '.epub', '.zim',
}
ALLOWED_RESOURCE_TYPES = {"textbook", "videos", "pyq", "notes", "pastPaper", "kiwix"}
ALLOWED_LANGUAGES = {"en", "hi", "kn", "fr"}
_TYPE_ALIASES = {"khan": "videos", "video": "videos", "textbooks": "textbook",
                 "past_paper": "pastPaper", "pastpaper": "pastPaper"}


@router.post("/teacher/upload", response_model=UploadResponse,
             summary="Upload a resource", tags=["Resources"],
             description="Uploads a resource file with metadata. Validates extension, subject, grade, language, and type; enforces duplicate detection unless force_upload is set.",
             responses={400: {"description": "Validation or upload failure"}, 401: {"description": "Unauthorized"}, 409: {"description": "Duplicate resource (use force_upload to override)"}, 499: {"description": "Client disconnected"}, 507: {"description": "Hub storage full"}})
async def upload_resource(title: str = Query(..., description="Display title"),
                          type: str = Query(..., description="Resource type"),
                          subject: str = Query("General", description="Subject"),
                          grade: str = Query("General", description="Grade level"),
                          language: str = Query("en", description="Language code (ISO 639-1)"),
                          source: str = Query("Unknown", description="Originating institution"),
                          license: str = Query("Internal Only", description="License identifier"),
                          topic_id: str = Query("", description="Topic ID to assign"),
                          force_upload: bool = Query(False, description="Override duplicate check"),
                          file: UploadFile = File(...),
                          teacher_user: str = Depends(verify_teacher),
                          request: Request = None):
    """Upload a resource file with metadata and duplicate detection.

    Checks disk space (rejects if < 2 GB free), validates the subject exists,
    checks for duplicate title+subject+grade+language+type unless force_upload
    is set, writes the file in chunks, and registers the resource in the DB.

    Raises:
        HTTPException: 400 for validation errors, 409 for duplicates,
            413 if disk full, 499 on client disconnect.
    """
    _, _, free = await asyncio.to_thread(_check_disk_space)
    if free // (2**30) < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")  # i18n: user-facing error message
    original_filename = file.filename or 'unnamed_file'
    ext = os.path.splitext(original_filename)[1].lower()
    if not ext or ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"File type '{ext}' is not allowed. Allowed types: {', '.join(sorted(ALLOWED_EXTENSIONS))}")  # i18n: user-facing error message
    uuid_name = f"{uuid.uuid4().hex}{ext}"

    type = _TYPE_ALIASES.get(type.lower(), type)

    if len(title) > 120:
        raise HTTPException(status_code=400, detail="Title must be 120 characters or fewer.")  # i18n: user-facing validation message
    if grade != "General" and not (grade.isdigit() and 0 <= int(grade) <= 13):
        grade_row = await db_fetch_one("SELECT name FROM grades WHERE name = ?", (grade,))
        if not grade_row:
            raise HTTPException(status_code=400, detail=f"Grade '{grade}' is not valid.")  # i18n: user-facing validation message
    if language not in ALLOWED_LANGUAGES:
        raise HTTPException(status_code=400, detail=f"Language '{language}' is not supported.")  # i18n: user-facing validation message
    if type not in ALLOWED_RESOURCE_TYPES:
        raise HTTPException(status_code=400, detail=f"Resource type '{type}' is not supported.")  # i18n: user-facing validation message

    subj_row = await db_fetch_one("SELECT name, id FROM subjects WHERE name = ?", (subject,))
    if not subj_row:
        raise HTTPException(status_code=400, detail=f"Subject '{subject}' not found in the system.")  # i18n: user-facing error message
    subject_id = subj_row["id"]

    if not force_upload:
        existing = await db_fetch_one("""SELECT id FROM resources
            WHERE title = ? AND subject = ? AND grade = ? AND language = ? AND resource_type = ? AND status NOT IN ('deprecated', 'deleted')""",
            (title, subject, grade, language, type))
        if existing:
            raise HTTPException(status_code=409, detail=f"Duplicate resource exists (id={existing[0]}). Use force_upload=true to override.")  # i18n: user-facing error message

    file_path = os.path.join(UPLOAD_DIR, uuid_name)
    try:
        await _write_chunked(file_path, file, 100 * 1024 * 1024)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Upload failed")  # i18n: user-facing error message
    if request and await request.is_disconnected():
        try:
            await asyncio.to_thread(os.remove, file_path)
        except FileNotFoundError:
            pass
        raise HTTPException(status_code=499, detail="Client disconnected")  # i18n: user-facing error message
    def _insert_resource(conn):
        """Insert the approved resource row and return its composite id."""
        resource_id = gen_composite_uid(conn, grade, subject, 'RES')
        conn.execute("""INSERT INTO resources
            (id, title, subject, subject_id, grade, language, resource_type, filename, original_name, source, license, uploaded_by, status, topic_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?)""",
            (resource_id, title, subject, subject_id, grade, language, type, uuid_name, original_filename, source, license, teacher_user, topic_id))
        conn.commit()
        return resource_id
    resource_id = await db_run(_insert_resource)
    invalidate_catalog_cache()
    await audit(action=Action.UPLOAD_RESOURCE, username=teacher_user, resource_type="resource",
                resource_id=resource_id, resource_name=title,
                context={"subject": subject, "grade": grade, "type": type})
    return {"status": "success", "filename": uuid_name, "original_name": original_filename}


@router.put("/teacher/resources/{resource_id}", response_model=dict,
            summary="Edit a resource", tags=["Resources"],
            description="Updates resource metadata fields (title, subject, grade, type, language, topic_id). Subject must exist.",
            responses={400: {"description": "No valid fields or subject not found"}, 401: {"description": "Unauthorized"}, 404: {"description": "Resource not found"}})
async def update_resource(resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Update resource metadata fields (title, subject, grade, type, language, topic_id).

    Only allowed fields are updated. Subject is validated against the DB.

    Raises:
        HTTPException: 400 if no valid fields or subject not found,
            404 if resource does not exist.
    """
    allowed = {"title", "subject", "grade", "type", "language", "topic_id"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")  # i18n: user-facing error message
    row = await db_fetch_one("SELECT id FROM resources WHERE id = ?", (resource_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found.")  # i18n: user-facing error message
    if "subject" in fields:
        subj = await db_fetch_one("SELECT name FROM subjects WHERE name = ?", (fields["subject"],))
        if not subj:
            raise HTTPException(status_code=400, detail=f"Subject '{fields['subject']}' not found.")  # i18n: user-facing error message
    set_parts = []
    params = []
    col_map = {"title": "title", "subject": "subject", "grade": "grade", "type": "resource_type", "language": "language", "topic_id": "topic_id"}
    for k, v in fields.items():
        set_parts.append(f"{col_map[k]} = ?")
        params.append(v)
    params.append(resource_id)
    await db_exec(f"UPDATE resources SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
    invalidate_catalog_cache()
    await audit(action=Action.UPDATE_RESOURCE, username=teacher_user, resource_type="resource",
                resource_id=resource_id, resource_name=fields.get("title", ""), changes=fields)
    return {"status": "ok"}


def _check_disk_space():
    """Return disk usage tuple (total, used, free) for the root partition."""
    import shutil as _shutil
    return _shutil.disk_usage("/")


@router.delete("/teacher/resources/{resource_id}", response_model=DeleteResourceResponse,
               summary="Delete a resource", tags=["Resources"],
               description="Soft-deletes a resource into the 30-day recycle bin; the file and row are purged by the hourly background task.",
               responses={400: {"description": "Delete failed"}, 401: {"description": "Unauthorized"}, 404: {"description": "Resource not found"}})
async def delete_resource(resource_id: str, teacher_user: str = Depends(verify_teacher)):
    """Move a resource to the recycle bin (soft delete).

    Sets status to ``deleted`` and records ``deleted_at``. The file, DB row,
    and related records stay untouched until the hourly purge hard-deletes
    them after 30 days.

    Returns:
        Dict with status and action (``recycled``).

    Raises:
        HTTPException: 404 if resource not found, 400 on failure.
    """
    try:
        def _recycle(conn):
            """Mark the resource deleted with a timestamp; returns its title or None."""
            row = conn.execute("SELECT title FROM resources WHERE id = ?", (resource_id,)).fetchone()
            if not row:
                return None
            conn.execute("UPDATE resources SET status = 'deleted', deleted_at = datetime('now') WHERE id = ?", (resource_id,))
            conn.commit()
            return row[0]

        db_title = await db_run(_recycle)
        if db_title is None:
            raise HTTPException(status_code=404, detail="Resource not found.")  # i18n: user-facing error message
        invalidate_catalog_cache()
        await audit(action=Action.DELETE_RESOURCE, username=teacher_user, resource_type="resource",
                    resource_id=resource_id, resource_name=db_title,
                    context={"soft_delete": True, "purge_days": 30})
        return {"status": "success", "action": "recycled"}
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"delete_resource: {e}")
        raise HTTPException(status_code=400, detail="Failed to delete resource")  # i18n: user-facing error message