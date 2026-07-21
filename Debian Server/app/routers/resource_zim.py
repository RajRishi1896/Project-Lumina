"""ZIM archive upload and processing."""
import os
import re
import uuid
import hashlib
import shutil
import sqlite3
import asyncio
import logging
import zipfile
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request
from app.database import UPLOAD_DIR, DB_PATH
from app.async_db import db_exec, db_fetch
from app.dependencies import verify_teacher

router = APIRouter()

_MIN_FREE_GB = 2  # reject uploads that leave less than this free


def _zim_target_dir():
    return os.path.join(os.path.dirname(os.path.dirname(__file__)), "zim_pages")


def _thumbs_dir():
    return os.path.join(_zim_target_dir(), "thumbs")


def _check_zim_magic(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b'ZIM\x00'
    except Exception:
        return False


@router.post("/teacher/upload-zim",
             summary="Upload ZIM archive", tags=["Resources"])
async def upload_zim(file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Upload and process a ZIM archive.

    Validates disk space, writes the file in chunks to a temp directory,
    then processes it using libzim (binary ZIM) or ZIP fallback. Extracted
    HTML articles are stored in ``zim_pages/`` and indexed in ``zim_articles``.
    Thumbnails are extracted from the ZIM ``I`` namespace when available.

    Returns:
        Dict with status and list of imported article filenames.

    Raises:
        HTTPException: 400 for bad format, 413 if too large, 499 on disconnect.
    """
    _, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    if free // (2**30) < _MIN_FREE_GB:
        raise HTTPException(status_code=507, detail=f"Insufficient storage. Need at least {_MIN_FREE_GB} GB free for ZIM upload.")  # i18n: user-facing error message
    if not file.filename:
        raise HTTPException(status_code=400, detail="Uploaded file has no filename.")  # i18n: user-facing error message

    tmp_dir = os.path.join(UPLOAD_DIR, f"tmp_{uuid.uuid4().hex}")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zim')
    archive_path = os.path.join(tmp_dir, safe_filename)
    os.makedirs(tmp_dir, exist_ok=True)

    chunk_size = 64 * 1024
    total_size = 0
    max_size = free - (_MIN_FREE_GB * 1024 * 1024 * 1024)

    def _flush_chunks(chunks):
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
            await asyncio.to_thread(shutil.rmtree, tmp_dir, True)
            raise HTTPException(status_code=413, detail=f"Upload too large. Must leave at least {_MIN_FREE_GB} GB free on disk.")  # i18n: user-facing error message
        if len(buf) >= 64:
            await asyncio.to_thread(_flush_chunks, buf)
            buf = []
    if buf:
        await asyncio.to_thread(_flush_chunks, buf)
    if request and await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")  # i18n: user-facing error message

    try:
        result = await asyncio.to_thread(_process_zim_archive, archive_path, safe_filename, teacher_user, tmp_dir)
        return {"status": "success", "imported": result}
    finally:
        await asyncio.to_thread(shutil.rmtree, tmp_dir, True)


def _process_zim_archive(archive_path: str, filename: str, teacher_user: str, tmp_dir: str):
    """Try libzim first (binary ZIM). If that fails, try ZIP extraction. Reject if neither works."""
    try:
        imported = _process_with_libzim(archive_path, filename, teacher_user)
        return imported
    except HTTPException:
        raise
    except Exception:
        logging.info(f"libzim failed for '{filename}', trying ZIP fallback")
        try:
            imported = _process_with_zip(archive_path, tmp_dir)
            return imported
        except (HTTPException, zipfile.BadZipFile):
            raise
        except Exception:
            raise HTTPException(status_code=400, detail="Unsupported file format. Upload a valid ZIM archive (.zim).")  # i18n: user-facing error message


def _process_with_libzim(archive_path: str, filename: str, teacher_user: str):
    """Parse a ZIM archive using python-libzim (handles binary ZIM files)."""
    import libzim
    zim_target_dir = _zim_target_dir()
    thumbs_dir = _thumbs_dir()
    os.makedirs(zim_target_dir, exist_ok=True)
    os.makedirs(thumbs_dir, exist_ok=True)

    archive_id = f"ZIM-{uuid.uuid4().hex[:12]}"
    file_size = os.path.getsize(archive_path)
    imported = []
    zim_stored_path = os.path.join(UPLOAD_DIR, f"{archive_id}.zim")
    shutil.move(archive_path, zim_stored_path)

    archive = libzim.Archive(zim_stored_path)

    archive_title = getattr(archive, 'title', None) or os.path.splitext(filename)[0]
    archive_lang = getattr(archive, 'language', 'en') or 'en'
    article_count = getattr(archive, 'article_count', 0)
    thumb_count = 0

    ns_i_index: dict[str, object] = {}
    for ns_entry in archive:
        if ns_entry.namespace == 'I' and ns_entry.path:
            ns_i_index[ns_entry.path.lower()] = ns_entry

    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute(
            "INSERT INTO zim_archives (id, filename, title, article_count, language, uploaded_by, file_size, zim_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (archive_id, filename, archive_title, article_count, archive_lang, teacher_user, file_size, zim_stored_path))

        for entry in archive:
            if entry.namespace != 'A':
                continue
            article_path = entry.path
            article_title = entry.title or article_path
            article_id = hashlib.md5(article_path.encode()).hexdigest()[:8].upper()
            try:
                item = entry.get_item()
                html_bytes = item.data if hasattr(item, 'data') else item.content
                if isinstance(html_bytes, memoryview):
                    html_bytes = bytes(html_bytes)
                html_content = html_bytes.decode('utf-8', errors='replace')
            except Exception:
                html_content = f"<html><body><h1>{article_title}</h1><p>Failed to extract article content.</p></body></html>"

            dest_name = f"{article_id}__{article_title}.html"
            dest_path = os.path.join(zim_target_dir, dest_name)
            with open(dest_path, 'w', encoding='utf-8') as f:
                f.write(html_content)

            has_thumb = 0
            try:
                search_key = article_path.lower().rsplit('.', 1)[0]
                for ns_path, ns_entry in ns_i_index.items():
                    if search_key in ns_path:
                        thumb_item = ns_entry.get_item()
                        thumb_data = thumb_item.data if hasattr(thumb_item, 'data') else thumb_item.content
                        if isinstance(thumb_data, memoryview):
                            thumb_data = bytes(thumb_data)
                        thumb_path = os.path.join(thumbs_dir, f"{article_id}.png")
                        with open(thumb_path, 'wb') as tf:
                            tf.write(thumb_data)
                        has_thumb = 1
                        thumb_count += 1
                        break
            except Exception:
                pass

            conn.execute(
                "INSERT INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                (archive_id, article_id, article_title, article_path, 'A', has_thumb))
            imported.append(dest_name)

        conn.commit()
    except sqlite3.Error as e:
        logging.error(f"ZIM DB insert failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to index ZIM archive.")  # i18n: user-facing error message
    finally:
        conn.close()

    logging.info(f"ZIM indexed: {len(imported)} articles, {thumb_count} thumbnails from '{filename}'")
    return imported


def _process_with_zip(archive_path: str, tmp_dir: str):
    """Extract HTML articles from a ZIP-based ZIM archive."""
    with zipfile.ZipFile(archive_path, "r") as zip_ref:
        for entry in zip_ref.namelist():
            info = zip_ref.getinfo(entry)
            if '..' in entry or entry.startswith('/') or (entry.endswith('/') and os.path.islink(entry)):
                raise HTTPException(status_code=400, detail="ZIP contains invalid path entries.")  # i18n: user-facing error message
            if info.external_attr >> 28 == 0o120000:
                raise HTTPException(status_code=400, detail="ZIP contains symlinks, rejected.")  # i18n: user-facing error message
        zip_ref.extractall(tmp_dir)
    imported = []
    zim_target_dir = _zim_target_dir()
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


@router.delete("/teacher/zim/{archive_id}",
               summary="Delete a ZIM archive", tags=["Resources"])
async def delete_zim_archive(archive_id: str, teacher_user: str = Depends(verify_teacher)):
    """Delete a ZIM archive and all its extracted content.

    Removes article HTML files, thumbnails, and database records for both
    ``zim_articles`` and ``zim_archives``.

    Raises:
        HTTPException: 404 if archive not found.
    """
    archive = await db_fetch("SELECT * FROM zim_archives WHERE id = ?", (archive_id,))
    if not archive:
        raise HTTPException(status_code=404, detail="Archive not found.")  # i18n: user-facing error message
    archive = archive[0]
    articles = await db_fetch("SELECT article_id FROM zim_articles WHERE archive_id = ?", (archive_id,))
    zim_target_dir = _zim_target_dir()
    thumbs_dir = _thumbs_dir()
    for a in articles:
        aid = a["article_id"]
        import glob as glob_mod
        for fp in await asyncio.to_thread(glob_mod.glob, os.path.join(zim_target_dir, f"{aid}__*")):
            await asyncio.to_thread(os.remove, fp)
        thumb_fp = os.path.join(thumbs_dir, f"{aid}.png")
        if await asyncio.to_thread(os.path.exists, thumb_fp):
            await asyncio.to_thread(os.remove, thumb_fp)
    await db_exec("DELETE FROM zim_articles WHERE archive_id = ?", (archive_id,))
    await db_exec("DELETE FROM zim_archives WHERE id = ?", (archive_id,))
    return {"status": "success"}
