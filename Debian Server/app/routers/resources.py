"""Resource management, upload, and file listing routes."""
import os
import uuid
import sqlite3
import asyncio
import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query
from app.database import UPLOAD_DIR, log_admin_action, gen_composite_uid
from app.async_db import db_conn, db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.models import CatalogResourceResponse, FileEntryResponse, LimitsResponse, UploadResponse, DeleteResourceResponse

router = APIRouter()


async def _zim_upload_max_size():
    from app.routers.resource_zim import _zim_upload_max_size as _inner
    return await _inner()


@router.get("/resources", response_model=list[CatalogResourceResponse],
            summary="List all resources", tags=["Resources"])
@router.get("/api/catalog", response_model=list[CatalogResourceResponse],
            summary="List all resources (alias)", tags=["Resources"])
async def list_resources(
    subject: Optional[str] = Query(None, description="Filter by subject"),
    grade: Optional[int] = Query(None, description="Filter by grade"),
    language: Optional[str] = Query(None, description="Filter by language (ISO 639-1)"),
    resource_type: Optional[str] = Query(None, description="Filter by resource type"),
    search: Optional[str] = Query(None, description="Search by title substring"),
    include_deprecated: bool = Query(False, description="Include deprecated resources"),
):
    conditions = []
    params = []
    if not include_deprecated:
        conditions.append("status != 'deprecated'")
    if subject:
        conditions.append("subject = ?")
        params.append(subject)
    if grade is not None:
        conditions.append("grade = ?")
        params.append(grade)
    if language:
        conditions.append("language = ?")
        params.append(language)
    if resource_type:
        conditions.append("resource_type = ?")
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
            "grade": r[5] or "", "mtime": mtimes.get(r[0], 0.0),
            "downloads": r[10] if len(r) > 10 else 0,
            "topic_name": r[12] if len(r) > 12 else "",
        })
    return result


@router.get("/api/files", response_model=list[FileEntryResponse],
            summary="List uploaded files", tags=["Resources"])
async def list_files(teacher_user: str = Depends(verify_teacher)):
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
    return {"zim_upload_max_size": await _zim_upload_max_size()}


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
    total, used, free = await asyncio.to_thread(_check_disk_space)
    if free // (2**30) < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")
    original_filename = file.filename or 'unnamed_file'
    ext = os.path.splitext(original_filename)[1]
    uuid_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(UPLOAD_DIR, uuid_name)

    db_subject = await db_fetch_one("SELECT name FROM subjects WHERE name = ?", (subject,))
    if not db_subject:
        raise HTTPException(status_code=400, detail=f"Subject '{subject}' not found in the system.")

    if not force_upload:
        try:
            existing = await db_fetch_one("""SELECT id FROM resources
                WHERE title = ? AND subject = ? AND grade = ? AND language = ? AND resource_type = ? AND status != 'deprecated'""",
                (title, subject, grade, language, type))
        except sqlite3.OperationalError:
            existing = await db_fetch_one("""SELECT id FROM resources
                WHERE title = ? AND subject = ? AND grade = ? AND status != 'deprecated'""",
                (title, subject, grade))
        if existing:
            raise HTTPException(status_code=409, detail=f"Duplicate resource exists (id={existing[0]}). Use force_upload=true to override.")

    chunk_size = 64 * 1024
    total_size = 0
    chunk_buffer = b""
    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        chunk_buffer += chunk
        total_size += len(chunk)
        if total_size > 100 * 1024 * 1024:
            try:
                await asyncio.to_thread(os.remove, file_path)
            except FileNotFoundError:
                pass
            raise HTTPException(status_code=400, detail="File too large")
        if len(chunk_buffer) >= 4 * 1024 * 1024:
            buf = chunk_buffer
            await asyncio.to_thread(lambda: open(file_path, "ab" if os.path.exists(file_path) else "wb").write(buf))
            chunk_buffer = b""
    if chunk_buffer:
        await asyncio.to_thread(lambda: open(file_path, "ab" if os.path.exists(file_path) else "wb").write(chunk_buffer))
    if request and await request.is_disconnected():
        try:
            await asyncio.to_thread(os.remove, file_path)
        except FileNotFoundError:
            pass
        raise HTTPException(status_code=499, detail="Client disconnected")
    await file.close()
    async with db_conn() as conn:
        resource_id = gen_composite_uid(conn, grade, subject, 'RES')
        conn.execute("""INSERT INTO resources
            (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, status, topic_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?)""",
            (resource_id, title, subject, grade, language, type, uuid_name, original_filename, source, license, teacher_user, topic_id))
        conn.commit()
    return {"status": "success", "filename": uuid_name, "original_name": original_filename}


@router.put("/teacher/resources/{resource_id}",
            summary="Edit a resource", tags=["Resources"])
async def update_resource(resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    allowed = {"title", "subject", "grade", "type", "language", "topic_id"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM resources WHERE id = ?", (resource_id,))
        if not c.fetchone():
            raise HTTPException(status_code=404, detail="Resource not found.")
        if "subject" in fields:
            subj = await db_fetch_one("SELECT name FROM subjects WHERE name = ?", (fields["subject"],))
            if not subj:
                raise HTTPException(status_code=400, detail=f"Subject '{fields['subject']}' not found.")
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
    import shutil as _shutil
    return _shutil.disk_usage("/")


@router.delete("/teacher/resources/{resource_id}", response_model=DeleteResourceResponse,
               summary="Delete a resource", tags=["Resources"])
async def delete_resource(resource_id: str, teacher_user: str = Depends(verify_teacher)):
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT id, filename, title FROM resources WHERE id = ?", (resource_id,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Resource not found.")
            db_id, db_filename, db_title = row
            file_path = os.path.join(UPLOAD_DIR, db_filename) if db_filename else None
            c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE resource_id = ?", (resource_id,))
            download_count = c.fetchone()[0]
            if download_count > 0:
                try:
                    c.execute("UPDATE resources SET status = 'deprecated', superseded_by = NULL WHERE id = ?", (resource_id,))
                    conn.commit()
                except sqlite3.OperationalError:
                    c.execute("UPDATE resources SET status = 'deprecated' WHERE id = ?", (resource_id,))
                    conn.commit()
                await log_admin_action(teacher_user, f"soft-deprecated resource id={resource_id} '{db_title}' ({download_count} active downloads)")
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
                await log_admin_action(teacher_user, f"hard-deleted resource id={resource_id} '{db_title}'")
                return {"status": "success", "action": "hard_deleted"}
        except Exception as e:
            logging.error(f"delete_resource: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete resource")
