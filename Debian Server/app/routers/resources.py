"""Resource management, upload, and file listing routes."""
import os
import re
import uuid
import shutil
import zipfile
import sqlite3
import asyncio
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
from app.database import UPLOAD_DIR
from app.async_db import db_conn
from app.dependencies import verify_teacher
from app.thumb_utils import get_zim_upload_max_size

router = APIRouter()


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






