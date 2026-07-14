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
from app.database import UPLOAD_DIR, log_admin_action
from app.async_db import db_exec, db_fetch
from app.dependencies import verify_teacher

router = APIRouter()


def _zim_target_dir():
    return os.path.join(os.path.dirname(os.path.dirname(__file__)), "zim_pages")


def _thumbs_dir():
    return os.path.join(_zim_target_dir(), "thumbs")


async def _zim_upload_max_size():
    try:
        _disk = await asyncio.to_thread(shutil.disk_usage, "/")
        return max(0, _disk.total - 1024 * 1024 * 1024)
    except Exception:
        return 5000 * 1024 * 1024


@router.post("/teacher/upload-zim",
             summary="Upload ZIM archive", tags=["Resources"])
async def upload_zim(file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher), request: Request = None):
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    if free // (2**30) < 2:
        raise HTTPException(status_code=507, detail="Insufficient storage space for ZIM upload.")
    if not file.filename:
        raise HTTPException(status_code=400, detail="Uploaded file has no filename.")

    tmp_dir = os.path.join(UPLOAD_DIR, f"tmp_{uuid.uuid4().hex}")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zim')
    archive_path = os.path.join(tmp_dir, safe_filename)
    os.makedirs(tmp_dir, exist_ok=True)

    chunk_size = 64 * 1024
    total_size = 0
    max_size = await _zim_upload_max_size()

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
            raise HTTPException(status_code=413, detail=f"ZIM upload exceeds maximum size limit of {max_size // (1024 * 1024)} MiB.")
        if len(buf) >= 64:
            await asyncio.to_thread(_flush_chunks, buf)
            buf = []
    if buf:
        await asyncio.to_thread(_flush_chunks, buf)
    if request and await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")

    is_zim_binary = await asyncio.to_thread(_check_zim_magic, archive_path)
    if not is_zim_binary:
        await asyncio.to_thread(shutil.rmtree, tmp_dir, True)
        raise HTTPException(status_code=400, detail="Unsupported file format. Only ZIM archives (.zim) are accepted. The file does not have the ZIM magic signature.")

    result = await asyncio.to_thread(_process_real_zim, archive_path, safe_filename, teacher_user)
    await asyncio.to_thread(shutil.rmtree, tmp_dir, True)
    return {"status": "success", "imported": result}


def _check_zim_magic(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b'ZIM\x00'
    except Exception:
        return False


def _process_real_zim(archive_path: str, filename: str, teacher_user: str):
    try:
        import libzim
    except ImportError:
        raise HTTPException(status_code=500, detail="ZIM parsing requires python-libzim. Install libzim-dev on the server.")
    zim_target_dir = _zim_target_dir()
    thumbs_dir = _thumbs_dir()
    os.makedirs(zim_target_dir, exist_ok=True)
    os.makedirs(thumbs_dir, exist_ok=True)

    archive_id = f"ZIM-{uuid.uuid4().hex[:12]}"
    file_size = os.path.getsize(archive_path)
    imported = []
    zim_stored_path = os.path.join(UPLOAD_DIR, f"{archive_id}.zim")
    shutil.move(archive_path, zim_stored_path)

    try:
        archive = libzim.Archive(zim_stored_path)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid ZIM archive file.")

    archive_title = getattr(archive, 'title', None) or os.path.splitext(filename)[0]
    archive_lang = getattr(archive, 'language', 'en') or 'en'
    article_count = getattr(archive, 'article_count', 0)
    thumb_count = 0

    ns_i_index: dict[str, object] = {}
    for ns_entry in archive:
        if ns_entry.namespace == 'I' and ns_entry.path:
            ns_i_index[ns_entry.path.lower()] = ns_entry

    try:
        conn = sqlite3.connect(os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "hub.db"))
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
        raise HTTPException(status_code=500, detail="Failed to index ZIM archive.")
    finally:
        conn.close()

    logging.info(f"ZIM indexed: {len(imported)} articles, {thumb_count} thumbnails from '{filename}'")
    return imported


def _process_zip_archive(archive_path: str, tmp_dir: str):
    try:
        with zipfile.ZipFile(archive_path, "r") as zip_ref:
            for entry in zip_ref.namelist():
                info = zip_ref.getinfo(entry)
                if '..' in entry or entry.startswith('/') or (entry.endswith('/') and os.path.islink(entry)):
                    raise HTTPException(status_code=400, detail="ZIP contains invalid path entries.")
                if info.external_attr >> 28 == 0o120000:
                    raise HTTPException(status_code=400, detail="ZIP contains symlinks, rejected.")
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
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Invalid ZIM/ZIP archive.")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Failed to extract archive.")
    finally:
        if os.path.exists(tmp_dir):
            shutil.rmtree(tmp_dir, ignore_errors=True)


@router.delete("/teacher/zim/{archive_id}",
               summary="Delete a ZIM archive", tags=["Resources"])
async def delete_zim_archive(archive_id: str, teacher_user: str = Depends(verify_teacher)):
    archive = await db_fetch("SELECT * FROM zim_archives WHERE id = ?", (archive_id,))
    if not archive:
        raise HTTPException(status_code=404, detail="Archive not found.")
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
