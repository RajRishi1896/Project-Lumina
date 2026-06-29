"""Resource management, upload, and file listing routes."""
import os
import re
import uuid
import shutil
import zipfile
import sqlite3
import asyncio
import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query
from app.database import UPLOAD_DIR, log_admin_action
from app.async_db import db_conn, db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.thumb_utils import get_zim_upload_max_size
from app.models import CatalogResourceResponse, FileEntryResponse, LimitsResponse, UploadResponse, ZimUploadResponse, DeleteResourceResponse

router = APIRouter()

APPROVED_SUBJECTS = {
    'math', 'sci', 'phy', 'chem', 'bio', 'eng', 'hin', 'kan',
    'soc', 'his', 'geo', 'civ', 'cs', 'eco', 'com', 'gen',
}

def _check_disk_space():
    """Check available disk space. Returns (total, used, free) bytes. Run via asyncio.to_thread."""
    return shutil.disk_usage("/")


@router.get("/resources", response_model=list[CatalogResourceResponse],
            summary="List all resources",
            description="Returns the full resource catalog with id, title, file path, type, subject, grade, and modification time. Also mounted at /api/catalog for backward compatibility.",
            tags=["Resources"])
@router.get("/api/catalog", response_model=list[CatalogResourceResponse],
            summary="List all resources (alias)",
            description="Alias for /resources — returns the full resource catalog. Kept for backward compatibility with legacy clients.",
            tags=["Resources"])
async def list_resources(
    subject: Optional[str] = Query(None, description="Filter by subject"),
    grade: Optional[int] = Query(None, description="Filter by grade"),
    language: Optional[str] = Query(None, description="Filter by language (ISO 639-1)"),
    resource_type: Optional[str] = Query(None, description="Filter by resource type"),
    search: Optional[str] = Query(None, description="Search by title substring"),
    include_deprecated: bool = Query(False, description="Include deprecated resources"),
):
    """List all resources in the catalog with optional filters.

    Returns:
        List of dicts with id, title, pdfUrl, type, subject, grade, and mtime.
    """
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

    query = f"SELECT id, title, filename, resource_type, subject, grade, language, source, license, status FROM resources{where_clause}"
    rows = await db_fetch(query, tuple(params))

    result = []
    # Batch get all mtimes in one thread call
    def _get_all_mtimes():
        mtimes = {}
        for r in rows:
            fpath = r[2]
            try:
                mtimes[r[0]] = os.path.getmtime(fpath) if os.path.exists(fpath) else 0.0
            except OSError:
                mtimes[r[0]] = 0.0
        return mtimes

    mtimes = await asyncio.to_thread(_get_all_mtimes)

    for r in rows:
        result.append({
            "id": r[0], "title": r[1],
            "pdfUrl": f"/files/{os.path.basename(r[2])}" if r[2] else "",
            "type": r[3], "subject": r[4] or "General",
            "grade": r[5] or "", "mtime": mtimes.get(r[0], 0.0),
        })
    return result


@router.get("/api/files", response_model=list[FileEntryResponse],
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


@router.get("/api/limits", response_model=LimitsResponse,
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


@router.post("/teacher/upload", response_model=UploadResponse,
             summary="Upload a resource",
             description="Uploads a file as a learning resource with title, type, subject, and optional grade. Rejects uploads when disk is below 2 GB free.",
             tags=["Resources"],
             responses={400: {"description": "File too large or invalid"}, 401: {"description": "Unauthorized"}, 409: {"description": "Duplicate resource"}, 499: {"description": "Client disconnected"}, 507: {"description": "Insufficient storage"}})
async def upload_resource(title: str = Query(..., description="Display title"),
                          type: str = Query(..., description="Resource type"),
                          subject: str = Query("General", description="Subject from approved taxonomy"),
                          grade: int = Query(0, description="Grade level (1-13)"),
                          language: str = Query("en", description="Language code (ISO 639-1)"),
                          source: str = Query("Unknown", description="Originating institution or author"),
                          license: str = Query("Internal Only", description="License identifier"),
                          force_upload: bool = Query(False, description="Override duplicate check"),
                          file: UploadFile = File(...),
                          teacher_user: str = Depends(verify_teacher),
                          request: Request = None):
    """Upload a file as a learning resource.

    Args:
        title: Display title for the resource.
        type: Resource type (textbook, videos, notes, pyq, pastPaper, kiwix).
        subject: Subject from approved taxonomy.
        grade: Grade level (1-13).
        language: Language code (ISO 639-1).
        source: Originating institution or author.
        license: License identifier.
        force_upload: If true, skip duplicate check.
        file: The uploaded file (max 100 MB).
        request: FastAPI request object for disconnect detection.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 507: If disk space is below 2 GB.
        HTTPException 400: If file exceeds 100 MB, invalid subject, or invalid params.
        HTTPException 409: If a duplicate resource exists and force_upload is not set.
        HTTPException 499: If client disconnects mid-upload.
    """
    total, used, free = await asyncio.to_thread(_check_disk_space)
    free_gb = free // (2**30)
    if free_gb < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")

    normalized = subject.lower().strip().replace(' ', '_')
    if normalized not in APPROVED_SUBJECTS:
        raise HTTPException(status_code=400, detail=f"Invalid subject '{subject}'. Allowed: {', '.join(sorted(APPROVED_SUBJECTS))}")
    validated_subject = normalized

    original_filename = file.filename or 'unnamed_file'
    ext = os.path.splitext(original_filename)[1]
    uuid_name = f"{uuid.uuid4().hex}{ext}"
    file_path = os.path.join(UPLOAD_DIR, uuid_name)

    # Duplicate check
    if not force_upload:
        try:
            existing = await db_fetch_one("""SELECT id FROM resources
                WHERE title = ? AND subject = ? AND grade = ?
                AND language = ? AND resource_type = ?
                AND status != 'deprecated'
            """, (title, validated_subject, grade, language, type))
        except sqlite3.OperationalError:
            existing = await db_fetch_one("""SELECT id FROM resources
                WHERE title = ? AND subject = ? AND grade = ?
                AND status != 'deprecated'
            """, (title, validated_subject, grade))
        if existing:
            raise HTTPException(
                status_code=409,
                detail=f"Duplicate resource exists (id={existing[0]}). Use force_upload=true to override."
            )

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
    await db_exec("""INSERT INTO resources
        (title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'approved')
    """, (title, validated_subject, grade, language, type, uuid_name, original_filename, source, license, teacher_user))
    return {"status": "success", "filename": uuid_name, "original_name": original_filename}


@router.post("/teacher/upload-zim", response_model=ZimUploadResponse,
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
    total, used, free = await asyncio.to_thread(_check_disk_space)
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

    def _flush_chunks(chunks):
        """Append chunks to file in a single open/write/close. Runs in worker thread."""
        with open(archive_path, "ab") as f:
            for c in chunks:
                f.write(c)

    buf = []
    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        buf.append(chunk)
        total_size += len(chunk)
        if total_size > max_size:
            raise HTTPException(
                status_code=413,
                detail=f"ZIM upload exceeds maximum size limit of {max_size // (1024 * 1024)} MiB."
            )
        if len(buf) >= 64:  # flush every ~4MB
            await asyncio.to_thread(_flush_chunks, buf)
            buf = []
    if buf:
        await asyncio.to_thread(_flush_chunks, buf)
    if request and await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")

    def _process_archive():
        """Extract ZIP, validate paths, move HTML files to zim_pages dir. Runs in worker thread."""
        try:
            with zipfile.ZipFile(archive_path, "r") as zip_ref:
                for entry in zip_ref.namelist():
                    info = zip_ref.getinfo(entry)
                    if '..' in entry or entry.startswith('/') or (entry.endswith('/') and os.path.islink(entry)):
                        raise HTTPException(status_code=400, detail="ZIP contains invalid path entries.")
                    if info.external_attr >> 28 == 0o120000:  # symlink
                        raise HTTPException(status_code=400, detail="ZIP contains symlinks, rejected.")
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


@router.delete("/teacher/resources/{resource_id}", response_model=DeleteResourceResponse,
               summary="Delete a resource",
               description="Deletes a resource by id. If any student has the resource in their downloads, soft-deprecates instead of hard-deleting. Logs the action.",
               tags=["Resources"],
               responses={400: {"description": "Failed to delete resource"}, 401: {"description": "Unauthorized"}, 404: {"description": "Resource not found"}})
async def delete_resource(resource_id: int, teacher_user: str = Depends(verify_teacher)):
    """Delete or deprecate a resource.

    Soft-deprecates if any student has the resource in their downloads,
    otherwise hard-deletes the file and DB record.

    Args:
        resource_id: The resource database id.

    Returns:
        Status dict indicating success and whether it was soft-deprecated.
    Raises:
        HTTPException 404: If resource does not exist.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT id, filename, file_path, title FROM resources WHERE id = ?", (resource_id,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Resource not found.")
            db_id, db_filename, db_file_path, db_title = row
            file_path = db_file_path or (os.path.join(UPLOAD_DIR, db_filename) if db_filename else None)

            # Check if any student has this resource in their downloads
            c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE resource_id = ?", (str(resource_id),))
            download_count = c.fetchone()[0]

            if download_count > 0:
                # Soft-deprecate — keep file and DB record
                try:
                    c.execute("UPDATE resources SET status = 'deprecated', superseded_by = NULL WHERE id = ?", (resource_id,))
                    conn.commit()
                except sqlite3.OperationalError:
                    c.execute("UPDATE resources SET status = 'deprecated' WHERE id = ?", (resource_id,))
                    conn.commit()
                await log_admin_action(teacher_user, f"soft-deprecated resource id={resource_id} '{db_title}' ({download_count} active downloads)")
                return {"status": "success", "action": "soft_deprecated", "download_count": download_count}
            else:
                # Hard-delete
                if file_path and await asyncio.to_thread(os.path.exists, file_path):
                    try:
                        await asyncio.to_thread(os.remove, file_path)
                    except Exception as e:
                        logging.warning(f"Could not remove physical file {file_path}: {e}")
                c.execute("DELETE FROM resources WHERE id = ?", (resource_id,))
                c.execute("DELETE FROM scholar_downloads WHERE resource_id = ?", (str(resource_id),))
                conn.commit()
                await log_admin_action(teacher_user, f"hard-deleted resource id={resource_id} '{db_title}'")
                return {"status": "success", "action": "hard_deleted"}
        except Exception as e:
            logging.error(f"delete_resource: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete resource")





