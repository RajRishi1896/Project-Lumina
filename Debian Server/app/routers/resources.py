"""Resource management, upload, and file listing routes."""
import os
import time
import uuid
import asyncio
import logging
import shutil
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query
from app.database import UPLOAD_DIR, gen_composite_uid
from app.audit import audit, Action
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.dependencies import verify_teacher, verify_user
from app.models import CatalogResourceResponse, FileEntryResponse, LimitsResponse, UploadResponse, DeleteResourceResponse
from app.routers.teacher_courses import _write_chunked

router = APIRouter()

# Catalog response cache. Keyed by the full filter tuple; entries expire after
# _CATALOG_CACHE_TTL seconds. invalidate_catalog_cache() is called from every
# resource-mutating route so uploads appear instantly in a single-worker
# deployment; the TTL bounds staleness across workers.
_catalog_cache: dict = {}
_CATALOG_CACHE_TTL = 30.0


def invalidate_catalog_cache():
    """Clear the cached catalog response. Call after any resource mutation."""
    _catalog_cache.clear()

# Shared upload allowlists (also imported by teacher_course_resources.py).
# No .svg/.html/.js -- those render as executable content when served.
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


@router.get("/resources", response_model=list[CatalogResourceResponse],
            summary="List all resources", tags=["Resources"],
            description="Lists approved resources with combined filters (subject, grade, language, resource_type, title search). Merges cached peer-hub resources; deprecated/deleted items are excluded by default.",
            responses={401: {"description": "Unauthorized"}})
@router.get("/api/catalog", response_model=list[CatalogResourceResponse],
            summary="List all resources (alias)", tags=["Resources"],
            description="Alias of GET /resources for the Flutter client catalog sync.",
            responses={401: {"description": "Unauthorized"}})
async def list_resources(
    _: str = Depends(verify_user),
    subject: Optional[str] = Query(None, description="Filter by subject"),
    grade: Optional[int] = Query(None, description="Filter by grade"),
    language: Optional[str] = Query(None, description="Filter by language (ISO 639-1)"),
    resource_type: Optional[str] = Query(None, description="Filter by resource type"),
    search: Optional[str] = Query(None, description="Search by title substring"),
    include_deprecated: bool = Query(False, description="Include deprecated resources"),
    include_kiwix: bool = Query(False, description="Include kiwix/ZIM archive resources"),
):
    """List approved resources with optional filters.

    Supports combined filtering by subject, grade, language, resource_type,
    and title substring.  Deprecated and deleted (recycle bin) resources are
    excluded by default; ``include_deprecated`` shows both.
    File modification times are batched into a single thread call.
    """
    cache_key = (
        subject, grade, language, resource_type, search,
        include_deprecated, include_kiwix,
    )
    now = time.time()
    hit = _catalog_cache.get(cache_key)
    if hit and now - hit[0] < _CATALOG_CACHE_TTL:
        return hit[1]

    conditions = []
    params = []
    if not include_deprecated:
        conditions.append("r.status NOT IN ('deprecated', 'deleted')")
    if not include_kiwix:
        conditions.append("r.resource_type != 'kiwix'")
    if subject:
        if subject == "General":
            conditions.append("(r.subject = 'General' OR r.grade = 'General')")
        else:
            conditions.append("r.subject = ?")
            params.append(subject)
    if grade is not None:
        # Grade 'General' means "all grades" -- include it in any grade filter
        conditions.append("(r.grade = ? OR r.grade = 'General')")
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
        COALESCE(rt.name, '') AS topic_name,
        r.page_count, r.duration_seconds, r.file_size
        FROM resources r
        LEFT JOIN (SELECT resource_id, COUNT(*) AS dl_count FROM scholar_downloads GROUP BY resource_id) sd
            ON sd.resource_id = r.id
        LEFT JOIN resource_topics rt ON rt.id = r.topic_id
        {where_clause}"""
    rows = await db_fetch(query, tuple(params))

    def _get_all_mtimes():
        """Batch stat every listed file in one call (avoids N+1)."""
        mtimes = {}
        for r in rows:
            try:
                full_path = os.path.join(UPLOAD_DIR, r[2]) if r[2] else None
                mtimes[r[0]] = os.path.getmtime(full_path) if full_path and os.path.exists(full_path) else 0.0
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
            "page_count": r[13] if len(r) > 13 else 0,
            "duration_seconds": r[14] if len(r) > 14 else 0,
            "file_size": r[15] if len(r) > 15 else 0,
        })

    # Merge cached resources from paired peer hubs. Same dict shape as local
    # items; ids are prefixed "peer:{peer_id}:{peer_resource_id}" so they stay
    # unique and the client can route downloads through /peer/file/... . No
    # dedupe against local titles -- v1 shows both (id prefix keeps them apart).
    peer_rows = await db_fetch("""
        SELECT pr.peer_id, pr.peer_resource_id, pr.title, pr.subject, pr.grade,
               pr.resource_type, pr.file_size, pr.page_count, pr.duration_seconds,
               pr.mtime, p.name AS peer_name
        FROM peer_resources pr JOIN peers p ON p.id = pr.peer_id""")
    for pr in peer_rows:
        result.append({
            "id": f"peer:{pr['peer_id']}:{pr['peer_resource_id']}",
            "title": pr["title"],
            "pdfUrl": f"/peer/file/{pr['peer_id']}/{pr['peer_resource_id']}",
            "type": pr["resource_type"], "subject": pr["subject"] or "General",
            "grade": str(pr["grade"]) if pr["grade"] is not None else "",
            "mtime": float(pr["mtime"] or 0.0),
            "downloads": 0,
            "topic_name": "",
            "page_count": pr["page_count"] or 0,
            "duration_seconds": pr["duration_seconds"] or 0,
            "file_size": pr["file_size"] or 0,
        })
    _catalog_cache[cache_key] = (now, result)
    return result


@router.get("/api/files", response_model=list[FileEntryResponse],
            summary="List uploaded files", tags=["Resources"],
            description="Lists every file in uploads/ with its size, for the content manager.",
            responses={401: {"description": "Unauthorized"}})
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
            summary="Get upload limits", tags=["Resources"],
            description="Returns the max ZIM upload size: free disk space minus a 2 GB safety reserve.",
            responses={401: {"description": "Unauthorized"}})
async def get_limits(teacher_user: str = Depends(verify_teacher)):
    """Return the maximum allowed ZIM upload size in bytes.

    Calculated as free disk space minus a 2 GB safety reserve.
    """
    _, _, free = await asyncio.to_thread(shutil.disk_usage, "/")
    return {"zim_upload_max_size": max(0, free - 2 * 1024 * 1024 * 1024)}


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

    _TYPE_ALIASES = {"khan": "videos", "video": "videos", "textbooks": "textbook",
                     "past_paper": "pastPaper", "pastpaper": "pastPaper"}
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

    db_subject = await db_fetch_one("SELECT name FROM subjects WHERE name = ?", (subject,))
    if not db_subject:
        raise HTTPException(status_code=400, detail=f"Subject '{subject}' not found in the system.")  # i18n: user-facing error message
    subj_row = await db_fetch_one("SELECT id FROM subjects WHERE name = ?", (subject,))
    subject_id = subj_row["id"] if subj_row else ""

    if not force_upload:
        existing = await db_fetch_one("""SELECT id FROM resources
            WHERE title = ? AND subject = ? AND grade = ? AND language = ? AND resource_type = ? AND status NOT IN ('deprecated', 'deleted')""",
            (title, subject, grade, language, type))
        if existing:
            raise HTTPException(status_code=409, detail=f"Duplicate resource exists (id={existing[0]}). Use force_upload=true to override.")  # i18n: user-facing error message

    try:
        await _write_chunked(file_path, file, 100 * 1024 * 1024,
                             request=request, support_resume=True)
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
    from app.metrics import incr
    incr("upload")
    return {"status": "success", "filename": uuid_name, "original_name": original_filename}


@router.get("/upload-status/{upload_id}", response_model=dict,
            summary="Check upload resume position", tags=["Resources"],
            description="Returns the byte count of a partial (.part) upload so the client can resume.",
            responses={401: {"description": "Unauthorized"}})
async def upload_status(upload_id: str, teacher_user: str = Depends(verify_teacher)):
    """Return the byte count of a .part file so the client can resume.

    The upload_id is the UUID-based saved filename (without extension).
    Checks for ``{upload_id}.ext.part`` in the uploads directory.

    Args:
        upload_id: The UUID-based saved filename without extension.
        teacher_user: Authenticated teacher username (auth gate).

    Returns:
        Dict with upload_id, bytes_written, and found flag.
    """
    import glob as glob_mod
    matches = await asyncio.to_thread(glob_mod.glob, os.path.join(UPLOAD_DIR, f"{upload_id}*.part"))
    if not matches:
        return {"upload_id": upload_id, "bytes_written": 0, "found": False}
    part_file = matches[0]
    size = await asyncio.to_thread(os.path.getsize, part_file)
    return {"upload_id": upload_id, "bytes_written": size, "found": True}


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


@router.post("/teacher/upload-quiz", response_model=UploadResponse,
             summary="Create a standalone quiz resource",
             description="Saves quiz questions as a JSON file and registers it as a resource.",
             tags=["Resources"],
             responses={400: {"description": "Invalid JSON or empty question list"}, 401: {"description": "Unauthorized"}})
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
    # Normalize: web frontend sends {type, text} instead of {id, type, question}
    for i, q in enumerate(questions):
        if "id" not in q or not q["id"]:
            q["id"] = f"q-{i}"
        if "question" not in q and "text" in q:
            q["question"] = q.pop("text")
        if "image" not in q and "image_data" in q:
            q["image"] = q.pop("image_data")
    subject = data.get("subject") or "General"
    subj_row = await db_fetch_one("SELECT id FROM subjects WHERE name = ?", (subject,))
    subject_id = subj_row["id"] if subj_row else ""
    topic_id = data.get("topic_id") or ""
    time_limit = data.get("time_limit_minutes") or 0
    pass_threshold = data.get("pass_threshold") or 60
    max_attempts = data.get("max_attempts") or 0
    shuffle_mode = data.get("shuffle_mode", "none")
    if isinstance(shuffle_mode, bool):
        shuffle_mode = "both" if shuffle_mode else "none"
    grade = data.get("grade") or 0
    language = data.get("language") or "en"
    quiz_payload = {
        "title": title,
        "questions": questions,
        "time_limit_minutes": time_limit,
        "pass_threshold": pass_threshold,
        "max_attempts": max_attempts,
        "shuffle_mode": shuffle_mode,
        "quiz_version": 1,
    }
    def _create_quiz_resource(conn):
        """Write the quiz JSON to uploads/ and insert the resource row."""
        uid = gen_composite_uid(conn, grade, subject, "RES")
        fname = f"{uid}.json"
        fpath = os.path.join(UPLOAD_DIR, fname)
        with open(fpath, "w", encoding="utf-8") as f:
            import json as _json
            _json.dump(quiz_payload, f, ensure_ascii=False)
        topic_val = topic_id if topic_id else None
        conn.execute(
            "INSERT INTO resources (id, title, filename, original_name, resource_type, subject, subject_id, grade, language, source, license, uploaded_by, status, topic_id) VALUES (?, ?, ?, ?, 'quiz', ?, ?, ?, ?, 'Teacher-Created', 'Internal Only', ?, 'approved', ?)",
            (uid, title, fname, title, subject, subject_id, grade, language, teacher_user, topic_val),
        )
        conn.commit()
        return uid, fname

    uid, fname = await db_run(_create_quiz_resource)
    await audit(action=Action.CREATE_QUIZ, username=teacher_user, resource_type="quiz",
                resource_id=uid, resource_name=title, context={"question_count": len(questions)})
    return {"status": "success", "filename": fname, "original_name": title}
