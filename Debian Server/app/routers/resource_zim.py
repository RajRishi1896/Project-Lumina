"""ZIM archive upload and processing.

Upload flow:
    1. Receive ZIM via HTTP upload
    2. Move to uploads/{archive_id}.zim
    3. Index article titles in zim_articles (for search)

No HTML extraction to disk. Articles are served lazily from the ZIM binary
via zim_handler.get_zim_page().
"""
import os
import re
import uuid
import hashlib
import shutil
import sqlite3
import asyncio
import logging
from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, File, Request
from app.database import UPLOAD_DIR, DB_PATH, gen_composite_uid
from app.async_db import db_exec, db_fetch
from app.dependencies import verify_teacher
from zim_handler import invalidate_zim_cache
from app.audit import audit, Action

router = APIRouter()

_MIN_FREE_GB = 2


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
async def upload_zim(file: UploadFile = File(...), title: str = Form(""), teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Upload and index a ZIM archive.

    Articles are indexed in the database for search, but HTML content is
    NOT extracted to disk. Articles are served lazily from the ZIM binary.

    Returns:
        Dict with status and article count.
    """
    _, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    if free // (2**30) < _MIN_FREE_GB:
        raise HTTPException(status_code=507, detail=f"Insufficient storage. Need at least {_MIN_FREE_GB} GB free.")
    if not file.filename:
        raise HTTPException(status_code=400, detail="Uploaded file has no filename.")

    tmp_dir = os.path.join(UPLOAD_DIR, f"tmp_{uuid.uuid4().hex}")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zim')
    archive_path = os.path.join(tmp_dir, safe_filename)
    part_path = f"{archive_path}.part"
    os.makedirs(tmp_dir, exist_ok=True)

    chunk_size = 64 * 1024
    total_size = 0
    max_size = free - (_MIN_FREE_GB * 1024 * 1024 * 1024)

    existing_bytes = 0
    content_range = request.headers.get("content-range") if request else None
    if await asyncio.to_thread(os.path.exists, part_path):
        if content_range:
            try:
                range_spec = content_range.split(" ", 1)[1]
                byte_range, _total = range_spec.split("/")
                start_str, _end_str = byte_range.split("-")
                existing_bytes = int(start_str)
            except Exception:
                existing_bytes = await asyncio.to_thread(os.path.getsize, part_path)
        else:
            existing_bytes = await asyncio.to_thread(os.path.getsize, part_path)
    total_size = existing_bytes

    def _flush_chunks(chunks):
        with open(part_path, "ab") as f:
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
            raise HTTPException(status_code=413, detail=f"Upload too large.")
        if len(buf) >= 64:
            await asyncio.to_thread(_flush_chunks, buf)
            buf = []
    if buf:
        await asyncio.to_thread(_flush_chunks, buf)
    if request and await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")

    await asyncio.to_thread(os.rename, part_path, archive_path)

    try:
        result = await asyncio.to_thread(_process_zim_archive, archive_path, safe_filename, teacher_user, tmp_dir, title, file.filename)
        await audit(action=Action.UPLOAD_ZIM, username=teacher_user, resource_type="zim_archive",
                    resource_name=file.filename, context={"article_count": result["article_count"]})
        return {"status": "success", "article_count": result["article_count"], "archive_id": result["archive_id"]}
    finally:
        await asyncio.to_thread(shutil.rmtree, tmp_dir, True)


def _process_zim_archive(archive_path: str, filename: str, teacher_user: str, tmp_dir: str, title: str = "", original_name: str = ""):
    """Index ZIM archive in DB. No HTML extraction."""
    try:
        return _process_with_libzim(archive_path, filename, teacher_user, title, original_name)
    except Exception as e:
        logging.error(f"ZIM processing failed for '{filename}': {e}")
        raise HTTPException(status_code=400, detail=f"Failed to process ZIM archive: {e}")


def _process_with_libzim(archive_path: str, filename: str, teacher_user: str, title: str = "", original_name: str = ""):
    """Index a ZIM archive: register in DB, index article titles."""
    import libzim

    archive_id = f"ZIM-{uuid.uuid4().hex[:12]}"
    file_size = os.path.getsize(archive_path)
    zim_stored_path = os.path.join(UPLOAD_DIR, f"{archive_id}.zim")
    shutil.move(archive_path, zim_stored_path)

    archive = libzim.Archive(zim_stored_path)

    archive_title = getattr(archive, 'title', None) or os.path.splitext(filename)[0]
    archive_lang = getattr(archive, 'language', 'en') or 'en'
    article_count = getattr(archive, 'article_count', 0)

    try:
        conn = sqlite3.connect(DB_PATH)

        # Aggressive PRAGMAs for bulk insert (MUST be before any writes)
        conn.execute("PRAGMA journal_mode = OFF")
        conn.execute("PRAGMA synchronous = OFF")
        conn.execute("PRAGMA cache_size = -64000")

        conn.execute("DROP INDEX IF EXISTS idx_zim_articles_archive")
        conn.execute("DROP INDEX IF EXISTS idx_zim_articles_title")
        conn.execute(
            "INSERT INTO zim_archives (id, filename, title, article_count, language, uploaded_by, file_size, zim_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (archive_id, filename, archive_title, article_count, archive_lang, teacher_user, file_size, zim_stored_path))

        batch = []
        total_indexed = 0
        try:
            entries_iter = archive.iter()
        except AttributeError:
            entries_iter = None
        if entries_iter is not None:
            for entry in entries_iter:
                article_path = entry.path
                raw_title = entry.title or article_path
                article_title = raw_title.replace('_', ' ') if raw_title else article_path
                article_id = hashlib.sha256(article_path.encode()).hexdigest()[:16].upper()
                batch.append((archive_id, article_id, article_title, article_path, 'A', 0))
                if len(batch) >= 5000:
                    conn.executemany(
                        "INSERT OR IGNORE INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                        batch)
                    total_indexed += len(batch)
                    if total_indexed % 100000 < 5000:
                        logging.info(f"ZIM indexing progress: {total_indexed} articles indexed from '{filename}'")
                    batch = []
        else:
            # Fallback for older libzim builds without iter()
            for i in range(archive.article_count):
                entry = archive._get_entry_by_id(i)
                article_path = entry.path
                raw_title = entry.title or article_path
                article_title = raw_title.replace('_', ' ') if raw_title else article_path
                article_id = hashlib.sha256(article_path.encode()).hexdigest()[:16].upper()
                batch.append((archive_id, article_id, article_title, article_path, 'A', 0))
                if len(batch) >= 5000:
                    conn.executemany(
                        "INSERT OR IGNORE INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                        batch)
                    total_indexed += len(batch)
                    if total_indexed % 100000 < 5000:
                        logging.info(f"ZIM indexing progress: {total_indexed} articles indexed from '{filename}'")
                    batch = []

        if batch:
            conn.executemany(
                "INSERT OR IGNORE INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                batch)
            total_indexed += len(batch)

        conn.execute("CREATE INDEX idx_zim_articles_archive ON zim_articles(archive_id)")
        conn.execute("CREATE INDEX idx_zim_articles_title ON zim_articles(title)")

        # Bridge into resources table so ZIM archives appear in content manager
        from datetime import datetime
        resource_title = title or archive_title or filename
        resource_id = gen_composite_uid(conn, 0, 'General', 'RES')
        conn.execute("""INSERT INTO resources
            (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, uploaded_at, status)
            VALUES (?, ?, 'General', 0, ?, 'kiwix', ?, ?, 'Kiwix', 'CC BY-SA 4.0', ?, ?, 'approved')""",
            (resource_id, resource_title, archive_lang, filename,
             original_name or filename, teacher_user, datetime.utcnow().isoformat()))

        conn.commit()

        # Revert PRAGMAs after commit
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA cache_size = -8000")

        # Create FTS5 trigram index for fast title search.
        # Commit FTS5 data BEFORE ANALYZE — ANALYZE on 19M trigram rows can
        # take minutes; if it hangs, the FTS5 data must already be on disk.
        try:
            conn.execute("DROP TABLE IF EXISTS zim_articles_fts")
            conn.execute("""
                CREATE VIRTUAL TABLE zim_articles_fts USING fts5(
                    title, content='zim_articles', content_rowid='id', tokenize='trigram'
                )
            """)
            conn.execute("""
                INSERT INTO zim_articles_fts(rowid, title)
                SELECT id, title FROM zim_articles
            """)
            conn.commit()
            logging.info(f"FTS5 trigram index created")
        except sqlite3.Error as e:
            logging.warning(f"FTS5 index creation failed (search will use LIKE fallback): {e}")

        # ANALYZE is optional — improves query planner stats but is not
        # required for FTS5 to function. Run after commit so a slow
        # ANALYZE cannot prevent FTS5 data from being persisted.
        try:
            conn.execute("ANALYZE")
            conn.commit()
        except Exception:
            pass
    except sqlite3.Error as e:
        logging.error(f"ZIM DB insert failed: {e}")
        raise
    finally:
        conn.close()

    logging.info(f"ZIM indexed: {article_count} articles from '{filename}'")
    return {"article_count": article_count, "archive_id": archive_id}


@router.post("/teacher/import-local-zim",
             summary="Import a ZIM file already on disk", tags=["Resources"])
async def import_local_zim(
    filename: str,
    teacher_user: str = Depends(verify_teacher),
):
    """Import a ZIM file that's already on the server filesystem.

    The file must be in the uploads/ directory. This avoids uploading
    100GB+ files through HTTP.
    """
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', filename)
    archive_path = os.path.join(UPLOAD_DIR, safe_filename)
    if not await asyncio.to_thread(os.path.isfile, archive_path):
        raise HTTPException(status_code=404, detail=f"File not found: {safe_filename}")

    if not await asyncio.to_thread(_check_zim_magic, archive_path):
        raise HTTPException(status_code=400, detail="Not a valid ZIM archive.")

    result = await asyncio.to_thread(_process_zim_archive, archive_path, safe_filename, teacher_user, UPLOAD_DIR)
    await audit(action=Action.UPLOAD_ZIM, username=teacher_user, resource_type="zim_archive",
                resource_name=safe_filename, context={"article_count": result["article_count"]})
    return {"status": "success", "article_count": result["article_count"], "archive_id": result["archive_id"]}


@router.post("/teacher/reindex-zim",
             summary="Re-index articles for an already-registered ZIM archive", tags=["Resources"])
async def reindex_zim(
    archive_id: str = Form(...),
    teacher_user: str = Depends(verify_teacher),
):
    """Re-index articles from a ZIM file that's already in zim_archives.

    Use this when articles weren't indexed (e.g. manual DB insert) or when
    the FTS5 index was lost. The ZIM file must already exist on disk.
    """
    archive = await db_fetch("SELECT id, filename, zim_path, title FROM zim_archives WHERE id = ?", (archive_id,))
    if not archive:
        raise HTTPException(status_code=404, detail="Archive not found.")
    arch = archive[0]
    zim_path = arch.get("zim_path", "")
    if not zim_path or not await asyncio.to_thread(os.path.isfile, zim_path):
        raise HTTPException(status_code=404, detail="ZIM file not found on disk.")

    result = await asyncio.to_thread(_reindex_zim_articles, zim_path, archive_id, arch.get("title", ""))
    return {"status": "success", "article_count": result["article_count"]}


def _reindex_zim_articles(zim_path: str, archive_id: str, archive_title: str):
    """Re-index articles for an existing archive and rebuild FTS5."""
    import libzim
    import hashlib

    archive = libzim.Archive(zim_path)
    article_count = getattr(archive, 'article_count', 0)

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA journal_mode = OFF")
        conn.execute("PRAGMA synchronous = OFF")
        conn.execute("PRAGMA cache_size = -64000")

        # Clear old articles for this archive
        conn.execute("DELETE FROM zim_articles WHERE archive_id = ?", (archive_id,))

        batch = []
        total_indexed = 0
        try:
            entries_iter = archive.iter()
        except AttributeError:
            entries_iter = None
        if entries_iter is not None:
            for entry in entries_iter:
                article_path = entry.path
                raw_title = entry.title or article_path
                article_title = raw_title.replace('_', ' ') if raw_title else article_path
                article_id = hashlib.sha256(article_path.encode()).hexdigest()[:16].upper()
                batch.append((archive_id, article_id, article_title, article_path, 'A', 0))
                if len(batch) >= 5000:
                    conn.executemany(
                        "INSERT OR IGNORE INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                        batch)
                    total_indexed += len(batch)
                    if total_indexed % 100000 < 5000:
                        logging.info(f"ZIM reindex progress: {total_indexed} articles from '{archive_id}'")
                    batch = []
        else:
            # Fallback for older libzim builds without iter()
            for i in range(archive.article_count):
                entry = archive._get_entry_by_id(i)
                article_path = entry.path
                raw_title = entry.title or article_path
                article_title = raw_title.replace('_', ' ') if raw_title else article_path
                article_id = hashlib.sha256(article_path.encode()).hexdigest()[:16].upper()
                batch.append((archive_id, article_id, article_title, article_path, 'A', 0))
                if len(batch) >= 5000:
                    conn.executemany(
                        "INSERT OR IGNORE INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                        batch)
                    total_indexed += len(batch)
                    if total_indexed % 100000 < 5000:
                        logging.info(f"ZIM reindex progress: {total_indexed} articles from '{archive_id}'")
                    batch = []

        if batch:
            conn.executemany(
                "INSERT OR IGNORE INTO zim_articles (archive_id, article_id, title, path, namespace, has_thumbnail) VALUES (?, ?, ?, ?, ?, ?)",
                batch)
            total_indexed += len(batch)

        conn.execute("CREATE INDEX IF NOT EXISTS idx_zim_articles_archive ON zim_articles(archive_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_zim_articles_title ON zim_articles(title)")
        conn.commit()

        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA cache_size = -8000")

        # Rebuild FTS5 and commit before ANALYZE
        try:
            conn.execute("DROP TABLE IF EXISTS zim_articles_fts")
            conn.execute("""
                CREATE VIRTUAL TABLE zim_articles_fts USING fts5(
                    title, content='zim_articles', content_rowid='id', tokenize='trigram'
                )
            """)
            conn.execute("INSERT INTO zim_articles_fts(rowid, title) SELECT id, title FROM zim_articles")
            conn.commit()
            logging.info(f"FTS5 rebuilt for archive {archive_id}")
        except sqlite3.Error as e:
            logging.warning(f"FTS5 rebuild failed: {e}")

        try:
            conn.execute("ANALYZE zim_articles_fts")
            conn.commit()
        except Exception:
            pass

        # Update article count in zim_archives
        conn.execute("UPDATE zim_archives SET article_count = ? WHERE id = ?", (total_indexed, archive_id))
        conn.commit()
    finally:
        conn.close()

    logging.info(f"ZIM reindexed: {total_indexed} articles from archive {archive_id}")
    return {"article_count": total_indexed}


@router.get("/teacher/server-zim-files",
            summary="List ZIM files on disk not yet indexed", tags=["Resources"])
async def list_server_zim_files(teacher_user: str = Depends(verify_teacher)):
    """Scan uploads/ for .zim files and show which ones are already indexed."""
    existing = await db_fetch("SELECT filename FROM zim_archives")
    indexed = {r["filename"] for r in existing}

    files = []
    for f in await asyncio.to_thread(os.listdir, UPLOAD_DIR):
        if not f.lower().endswith(".zim"):
            continue
        full = os.path.join(UPLOAD_DIR, f)
        size = await asyncio.to_thread(os.path.getsize, full)
        files.append({
            "filename": f,
            "size_bytes": size,
            "indexed": f in indexed,
            "archive_id": next((r.get("id") for r in existing if r["filename"] == f), None),
        })

    files.sort(key=lambda x: (-x["indexed"], x["filename"].lower()))
    return files


@router.delete("/teacher/zim/{archive_id}",
               summary="Delete a ZIM archive", tags=["Resources"])
async def delete_zim_archive(archive_id: str, teacher_user: str = Depends(verify_teacher)):
    """Delete a ZIM archive and all its indexed data."""
    archive = await db_fetch("SELECT * FROM zim_archives WHERE id = ?", (archive_id,))
    if not archive:
        raise HTTPException(status_code=404, detail="Archive not found.")
    archive = archive[0]

    # Delete thumbnails
    articles = await db_fetch("SELECT article_id FROM zim_articles WHERE archive_id = ?", (archive_id,))
    thumbs_dir = _thumbs_dir()
    for a in articles:
        aid = a["article_id"]
        thumb_fp = os.path.join(thumbs_dir, f"{aid}.png")
        if await asyncio.to_thread(os.path.exists, thumb_fp):
            await asyncio.to_thread(os.remove, thumb_fp)

    await db_exec("DELETE FROM zim_articles WHERE archive_id = ?", (archive_id,))
    await db_exec("DELETE FROM zim_archives WHERE id = ?", (archive_id,))
    await db_exec("DELETE FROM resources WHERE resource_type = 'kiwix' AND filename = ?", (archive["filename"],))

    # Delete the ZIM file from disk
    zim_path = archive.get("zim_path", "")
    if zim_path and await asyncio.to_thread(os.path.isfile, zim_path):
        await asyncio.to_thread(os.remove, zim_path)

    invalidate_zim_cache(archive_id)
    await audit(action=Action.DELETE_ZIM, username=teacher_user, resource_type="zim_archive",
                resource_id=archive_id, resource_name=archive.get("title", ""))
    return {"status": "success"}
