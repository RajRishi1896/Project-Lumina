"""Resource management, upload, and file listing routes."""
import os
import uuid
import asyncio
import logging
import shutil
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query
from app.database import UPLOAD_DIR, gen_composite_uid
from app.audit import audit, Action
from app.async_db import db_conn, db_fetch, db_fetch_one
from app.dependencies import verify_teacher, verify_user
from app.models import CatalogResourceResponse, FileEntryResponse, LimitsResponse, UploadResponse, DeleteResourceResponse
from app.routers.teacher_courses import _write_chunked

router = APIRouter()


@router.get("/resources", response_model=list[CatalogResourceResponse],
            summary="List all resources", tags=["Resources"])
@router.get("/api/catalog", response_model=list[CatalogResourceResponse],
            summary="List all resources (alias)", tags=["Resources"])
async def list_resources(
    _: str = Depends(verify_user),
    subject: Optional[str] = Query(None, description="Filter by subject"),
    grade: Optional[int] = Query(None, description="Filter by grade"),
    language: Optional[str] = Query(None, description="Filter by language (ISO 639-1)"),
    resource_type: Optional[str] = Query(None, description="Filter by resource type"),
    search: Optional[str] = Query(None, description="Search by title substring"),
    include_deprecated: bool = Query(False, description="Include deprecated resources"),
):
    """List approved resources with optional filters.

    Supports combined filtering by subject, grade, language, resource_type,
    and title substring.  Deprecated resources are excluded by default.
    File modification times are batched into a single thread call.
    """
    conditions = []
    params = []
    if not include_deprecated:
        conditions.append("r.status != 'deprecated'")
    if subject:
        conditions.append("r.subject = ?")
        params.append(subject)
    if grade is not None:
        conditions.append("r.grade = ?")
        params.append(grade)
    if language:
        conditions.append("r.language = ?")
        params.append(language)
    if resource_type:
        conditions.append("r.resource_type = ?")
        params.append(resource_type)
    if search:
        conditions.append("title LIKE ?")
        params.append(f"%{search}%")
    where_clause = ""
    if conditions:
        where_clause = " WHERE " + " AND ".join(conditions)

    query = f"""SELECT r.id, r.title, r.filename, r.resource_type, r.subject, r.grade, r.language, r.source, r.license, r.status,
        COALESCE(sd.dl_count, 0) AS downloads, r.topic_id,
        COALESCE(rt.name, '') AS topic_name
        FROM resources r
        LEFT JOIN (SELECT resource_id, COUNT(*) AS dl_count FROM scholar_downloads GROUP BY resource_id) sd
            ON sd.resource_id = r.id
        LEFT JOIN resource_topics rt ON rt.id = r.topic_id
        {where_clause}"""
    rows = await db_fetch(query, tuple(params))

    def _get_all_mtimes():
        mtimes = {}
        for r in rows:
            try:
                mtimes[r[0]] = os.path.getmtime(r[2]) if r[2] and os.path.exists(r[2]) else 0.0
            except OSError:
                mtimes[r[0]] = 0.0
        return mtimes

    mtimes = await asyncio.to_thread(_get_all_mtimes)
    result = []
    for r in rows:
        result.append({
            "id": r[0], "title": r[1],
            "pdfUrl": f"/files/{os.path.basename(r[2])}" if r[2] else "",
            "type": r[3], "subject": r[4] or "General",
            "grade": str(r[5]) if r[5] is not None else "", "mtime": mtimes.get(r[0], 0.0),
            "downloads": r[10] if len(r) > 10 else 0,
            "topic_name": r[12] if len(r) > 12 else "",
        })
    return result


@router.get("/api/files", response_model=list[FileEntryResponse],
            summary="List uploaded files", tags=["Resources"])
async def list_files(teacher_user: str = Depends(verify_teacher)):
    """List all uploaded files in the uploads directory with sizes.

    Runs the directory scan in a worker thread to avoid blocking the
    event loop.
    """
    if not os.path.exists(UPLOAD_DIR):
        return []
    return await asyncio.to_thread(lambda: [
        {"name": f, "size": os.path.getsize(os.path.join(UPLOAD_DIR, f))}
        for f in os.listdir(UPLOAD_DIR)
        if os.path.isfile(os.path.join(UPLOAD_DIR, f))
    ])


@router.get("/api/limits", response_model=LimitsResponse,
            summary="Get upload limits", tags=["Resources"])
async def get_limits(teacher_user: str = Depends(verify_teacher)):
    """Return the maximum allowed ZIM upload size in bytes.

    Calculated as free disk space minus a 2 GB safety reserve.
    """
    _, _, free = await asyncio.to_thread(shutil.disk_usage, "/")
    return {"zim_upload_max_size": max(0, free - 2 * 1024 * 1024 * 1024)}


@router.post("/teacher/upload", response_model=UploadResponse,
             summary="Upload a resource", tags=["Resources"])
async def upload_resource(title: str = Query(..., description="Display title"),
                          type: str = Query(..., description="Resource type"),
                          subject: str = Query("General", description="Subject"),
                          grade: int = Query(0, description="Grade level (1-13)"),
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
    ALLOWED_EXTENSIONS = {
        '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.odt', '.ods', '.odp',
        '.txt', '.rtf', '.csv', '.json',
        '.mp4', '.webm', '.mkv', '.avi', '.mov', '.flv',
        '.mp3', '.wav', '.ogg', '.m4a',
        '.jpg', '.jpeg', '.png', '.gif', '.svg', '.webp', '.bmp',
        '.epub', '.zim',
    }
    if ext and ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"File type '{ext}' is not allowed. Allowed types: {', '.join(sorted(ALLOWED_EXTENSIONS))}")  # i18n: user-facing error message
    uuid_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(UPLOAD_DIR, uuid_name)

    db_subject = await db_fetch_one("SELECT name FROM subjects WHERE name = ?", (subject,))
    if not db_subject:
        raise HTTPException(status_code=400, detail=f"Subject '{subject}' not found in the system.")  # i18n: user-facing error message

    if not force_upload:
        existing = await db_fetch_one("""SELECT id FROM resources
            WHERE title = ? AND subject = ? AND grade = ? AND language = ? AND resource_type = ? AND status != 'deprecated'""",
            (title, subject, grade, language, type))
        if existing:
            raise HTTPException(status_code=409, detail=f"Duplicate resource exists (id={existing[0]}). Use force_upload=true to override.")  # i18n: user-facing error message

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
    async with db_conn() as conn:
        resource_id = gen_composite_uid(conn, grade, subject, 'RES')
        conn.execute("""INSERT INTO resources
            (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, status, topic_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?)""",
            (resource_id, title, subject, grade, language, type, uuid_name, original_filename, source, license, teacher_user, topic_id))
        conn.commit()
    from app.metrics import incr
    incr("upload")
    return {"status": "success", "filename": uuid_name, "original_name": original_filename}


@router.put("/teacher/resources/{resource_id}",
            summary="Edit a resource", tags=["Resources"])
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
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM resources WHERE id = ?", (resource_id,))
        if not c.fetchone():
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
        c.execute(f"UPDATE resources SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
        conn.commit()
    return {"status": "ok"}


def _check_disk_space():
    """Return disk usage tuple (total, used, free) for the root partition."""
    import shutil as _shutil
    return _shutil.disk_usage("/")


@router.delete("/teacher/resources/{resource_id}", response_model=DeleteResourceResponse,
               summary="Delete a resource", tags=["Resources"])
async def delete_resource(resource_id: str, teacher_user: str = Depends(verify_teacher)):
    """Soft-deprecate or hard-delete a resource.

    If the resource has active student downloads, it is soft-deprecated
    (status set to ``deprecated``).  Otherwise the file is removed from disk
    and the DB row deleted.  Logs the action to the audit log.

    Returns:
        Dict with status and action taken (``soft_deprecated`` or ``hard_deleted``).

    Raises:
        HTTPException: 404 if resource not found, 400 on failure.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT id, filename, title FROM resources WHERE id = ?", (resource_id,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Resource not found.")  # i18n: user-facing error message
            db_id, db_filename, db_title = row
            file_path = os.path.join(UPLOAD_DIR, db_filename) if db_filename else None
            c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE resource_id = ?", (resource_id,))
            download_count = c.fetchone()[0]
            if download_count > 0:
                c.execute("UPDATE resources SET status = 'deprecated', superseded_by = NULL WHERE id = ?", (resource_id,))
                conn.commit()
                await audit(action=Action.DEPRECATE_RESOURCE, username=teacher_user, resource_type="resource",
                            resource_id=resource_id, resource_name=db_title,
                            context={"download_count": download_count})
                return {"status": "success", "action": "soft_deprecated", "download_count": download_count}
            else:
                if file_path and await asyncio.to_thread(os.path.exists, file_path):
                    try:
                        await asyncio.to_thread(os.remove, file_path)
                    except Exception as e:
                        logging.warning(f"Could not remove physical file {file_path}: {e}")
                c.execute("DELETE FROM resources WHERE id = ?", (resource_id,))
                c.execute("DELETE FROM scholar_downloads WHERE resource_id = ?", (resource_id,))
                conn.commit()
                await audit(action=Action.DELETE_RESOURCE, username=teacher_user, resource_type="resource",
                            resource_id=resource_id, resource_name=db_title)
                return {"status": "success", "action": "hard_deleted"}
        except Exception as e:
            logging.error(f"delete_resource: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete resource")  # i18n: user-facing error message


@router.post("/teacher/upload-quiz", response_model=UploadResponse,
             summary="Create a standalone quiz resource",
             description="Saves quiz questions as a JSON file and registers it as a resource.",
             tags=["Resources"])
async def upload_quiz(request: Request, teacher_user: str = Depends(verify_teacher)):
    """Create a standalone quiz resource from JSON payload.

    Args:
        request: The incoming request with JSON body containing quiz data.
        teacher_user: Authenticated teacher username.

    Returns:
        Dict with status, filename, and original_name.
    """
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body.")  # i18n: user-facing error message
    title = (data.get("title") or "Quiz").strip()[:120]
    questions = data.get("questions", [])
    if not questions:
        raise HTTPException(status_code=400, detail="Quiz must have at least one question.")  # i18n: user-facing error message
    subject = data.get("subject") or "General"
    topic_id = data.get("topic_id") or ""
    time_limit = data.get("time_limit_minutes") or 0
    pass_threshold = data.get("pass_threshold") or 60
    max_attempts = data.get("max_attempts") or 0
    shuffle = bool(data.get("shuffle", False))
    grade = data.get("grade") or 0
    language = data.get("language") or "en"
    quiz_payload = {
        "title": title,
        "questions": questions,
        "time_limit_minutes": time_limit,
        "pass_threshold": pass_threshold,
        "max_attempts": max_attempts,
        "shuffle": shuffle,
        "quiz_version": 1,
    }
    async with db_conn() as conn:
        uid = gen_composite_uid(conn, grade, subject, "RES")
        fname = f"{uid}.json"
        fpath = os.path.join(UPLOAD_DIR, fname)
        def _write_quiz():
            with open(fpath, "w", encoding="utf-8") as f:
                import json as _json
                _json.dump(quiz_payload, f, ensure_ascii=False)
        await asyncio.to_thread(_write_quiz)
        topic_val = topic_id if topic_id else None
        c = conn.cursor()
        c.execute(
            "INSERT INTO resources (id, title, filename, original_name, resource_type, subject, grade, language, source, license, uploaded_by, status, topic_id) VALUES (?, ?, ?, ?, 'quiz', ?, ?, ?, 'Teacher-Created', 'Internal Only', ?, 'approved', ?)",
            (uid, title, fname, title, subject, grade, language, teacher_user, topic_val),
        )
        conn.commit()
    await audit(action=Action.CREATE_QUIZ, username=teacher_user, resource_type="quiz",
                resource_id=uid, resource_name=title, context={"question_count": len(questions)})
    return {"status": "success", "filename": fname, "original_name": title}
