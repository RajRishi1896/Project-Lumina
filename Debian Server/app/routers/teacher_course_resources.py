"""Teacher course resource management -- upload, ZIP import/export."""
import os
import io
import re
import uuid
import json
import asyncio
import sqlite3
import shutil
import zipfile
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query, Request
from fastapi.responses import StreamingResponse
from app.database import UPLOAD_DIR, DB_PATH, gen_composite_uid
from app.audit import audit, Action
from app.async_db import db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.routers.resources import ALLOWED_EXTENSIONS
from app.routers.teacher_courses import (
    COURSES_DIR, _course_to_response, _resources_dir, _assets_dir, _ensure_course_exists, _write_chunked,
)

router = APIRouter()


class _ZipError(Exception):
    """Raised inside _process() threads to carry HTTP status + detail.

    HTTPException raised inside asyncio.to_thread doesn't propagate
    through Starlette middleware -- it becomes a generic 500.  This
    plain exception crosses the thread boundary cleanly; the caller
    translates it to HTTPException.
    """
    def __init__(self, status_code: int, detail: str):
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


@router.post("/api/teacher/courses/{course_id}/upload-resource",
             summary="Upload a resource file to a course", tags=["Teacher Courses"],
             description="Uploads a single resource file to a course. Accepts multipart form data with an optional title and topic assignment.",
             response_model=dict,
             responses={200: {"description": "Uploaded course_resources row"}, 400: {"description": "Disallowed file type"}, 404: {"description": "Course not found"}})
async def upload_course_resource(
    course_id: str,
    resource_type: str = Query(..., description="Resource type"),
    title: str = Query("", description="Display title"),
    topic_id: str = Query("", description="Topic ID to assign"),
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher),
    request: Request = None,
):
    """Upload a single resource file to a course.

    Writes the file in chunks to ``uploads/courses/{id}/resources/``, registers
    it in ``course_resources`` with the next position index, and optionally
    assigns it to a topic.

    Returns:
        The created course_resources row.
    """
    await _ensure_course_exists(course_id)
    original_name = file.filename or "unnamed_file"
    ext = os.path.splitext(original_name)[1].lower()
    if not ext or ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"File type '{ext}' is not allowed.")  # i18n: user-facing error message
    resource_id = str(uuid.uuid4())
    saved_name = f"{resource_id}{ext}"
    dest_path = os.path.join(_resources_dir(course_id), saved_name)

    total_size = await _write_chunked(dest_path, file, 500 * 1024 * 1024,
                                       request=request, support_resume=True)
    disp_title = title if title else original_name

    from app.async_db import db_exec
    await db_exec(
        """INSERT INTO course_resources (id, course_id, resource_type, title, original_name, filename, file_size, position, topic_id)
           SELECT ?, ?, ?, ?, ?, ?, ?, COALESCE(MAX(position), -1) + 1, ?
           FROM course_resources WHERE course_id = ?""",
        (resource_id, course_id, resource_type, disp_title, original_name, saved_name, total_size, topic_id, course_id)
    )
    await audit(action=Action.UPLOAD_COURSE_RESOURCE, username=teacher_user, resource_type="course_resource",
                resource_id=resource_id, resource_name=disp_title,
                context={"course_id": course_id, "file_size": total_size})
    row = await db_fetch_one("SELECT * FROM course_resources WHERE id = ?", (resource_id,))
    return dict(row)


@router.post("/api/teacher/courses/{course_id}/upload-zip",
             summary="Import course content from a ZIP archive", tags=["Teacher Courses"],
             description="Imports resources, assets, and quizzes from a ZIP archive into an existing course.",
             response_model=dict,
             responses={200: {"description": "Extraction counts"}, 400: {"description": "Invalid or oversized ZIP"}, 404: {"description": "Course not found"}})
async def upload_course_zip(
    course_id: str,
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher),
):
    """Import resources into an existing course from a ZIP archive.

    Expects ``resources/`` entries for files, ``assets/`` for supplementary
    files, ``quiz_*.json`` for quizzes, and an optional ``course.json``
    metadata manifest.  Processes everything in a background thread.

    Returns:
        Counts of resources created, quizzes found, and assets extracted.
    """
    await _ensure_course_exists(course_id)

    tmp_dir = os.path.join(COURSES_DIR, f"tmp_{uuid.uuid4().hex}")
    os.makedirs(tmp_dir, exist_ok=True)
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zip')
    archive_path = os.path.join(tmp_dir, safe_filename)

    def _flush(buf):
        """Append a buffer of uploaded bytes to the temp archive file."""
        with open(archive_path, "ab") as f:
            f.write(buf)

    chunk_size = 64 * 1024
    total_size = 0
    buf = []
    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        buf.append(chunk)
        total_size += len(chunk)
        if total_size > 500 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="ZIP exceeds 500 MB limit.")  # i18n: user-facing error message
        if len(buf) >= 64:
            await asyncio.to_thread(_flush, b"".join(buf))
            buf = []
    if buf:
        await asyncio.to_thread(_flush, b"".join(buf))
    await file.close()

    def _process():
        """Extract the ZIP in a worker thread, validating paths and writing rows."""
        conn_sql = None
        try:
            with zipfile.ZipFile(archive_path, "r") as zf:
                names = zf.namelist()
                for name in names:
                    if '..' in name or name.startswith('/'):
                        raise _ZipError(400, f"ZIP contains invalid path: {name}")  # i18n: user-facing error message

                resources_created = 0
                quizzes_found = 0
                assets_extracted = 0
                res_dir = _resources_dir(course_id)
                ast_dir = _assets_dir(course_id)

                conn_sql = sqlite3.connect(DB_PATH, timeout=5.0)
                conn_sql.row_factory = sqlite3.Row
                last_row = conn_sql.execute(
                    "SELECT COALESCE(MAX(position), -1) AS mp FROM course_resources WHERE course_id = ?",
                    (course_id,)
                ).fetchone()
                next_pos = (last_row["mp"] if last_row and last_row["mp"] is not None else -1) + 1

                if "course.json" in names:
                    md = json.loads(zf.read("course.json"))
                    cur_row = conn_sql.execute(
                        "SELECT title, description, subject, grade, language FROM courses WHERE id=?", (course_id,)
                    ).fetchone()
                    fallback = dict(cur_row) if cur_row else {}
                    conn_sql.execute(
                        """UPDATE courses SET title=?, description=?, subject=?, grade=?, language=?, updated_at=datetime('now')
                           WHERE id=?""",
                        (md.get("title", fallback.get("title", "")),
                         md.get("description", fallback.get("description", "")),
                         md.get("subject", fallback.get("subject", "")),
                         md.get("grade", fallback.get("grade", 0)),
                         md.get("language", fallback.get("language", "en")), course_id)
                    )

                for name in names:
                    if zf.getinfo(name).is_dir() or name == "course.json":
                        continue
                    if name.startswith("quiz_") and name.endswith(".json"):
                        with open(os.path.join(COURSES_DIR, course_id, name), "wb") as f:
                            f.write(zf.read(name))
                        quizzes_found += 1
                        continue
                    if name.startswith("assets/"):
                        arcname = os.path.relpath(name, "assets")
                        dest = os.path.join(ast_dir, arcname)
                        os.makedirs(os.path.dirname(dest), exist_ok=True)
                        with open(dest, "wb") as f:
                            f.write(zf.read(name))
                        assets_extracted += 1
                        continue
                    if name.startswith("resources/"):
                        orig = os.path.basename(name)
                        rid = str(uuid.uuid4())
                        _, ext = os.path.splitext(orig)
                        saved_name = f"{rid}{ext}"
                        dest = os.path.join(res_dir, saved_name)
                        with open(dest, "wb") as f:
                            f.write(zf.read(name))
                        fsize = os.path.getsize(dest)
                        rtype = "video" if ext.lower() in (".mp4", ".webm", ".avi", ".mkv") else "textbook"
                        conn_sql.execute(
                            """INSERT INTO course_resources
                               (id, course_id, resource_type, title, original_name, filename, file_size, position)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                            (rid, course_id, rtype, orig, orig, saved_name, fsize, next_pos)
                        )
                        next_pos += 1
                        resources_created += 1

                conn_sql.commit()
                return {"status": "ok", "resources_created": resources_created,
                        "quizzes_found": quizzes_found, "assets_extracted": assets_extracted}
        except zipfile.BadZipFile:
            raise _ZipError(400, "Invalid ZIP archive.")  # i18n: user-facing error message
        except _ZipError:
            raise
        except Exception as e:
            raise _ZipError(400, f"Failed to extract archive: {e}")  # i18n: user-facing error message, {e} is the exception detail
        finally:
            if os.path.exists(tmp_dir):
                shutil.rmtree(tmp_dir, ignore_errors=True)
            try:
                if conn_sql:
                    conn_sql.close()
            except Exception:
                pass

    try:
        result = await asyncio.to_thread(_process)
    except _ZipError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)
    await audit(action=Action.IMPORT_ZIP, username=teacher_user, resource_type="course",
                resource_id=course_id,
                context={"resources_created": result['resources_created'],
                         "quizzes_found": result['quizzes_found'],
                         "assets_extracted": result['assets_extracted']})
    return result


@router.post("/api/teacher/courses/import",
             summary="Create a course by importing a ZIP archive", tags=["Teacher Courses"],
             description="Creates a new course from a ZIP archive containing a course.json manifest plus resources, assets, and quizzes.",
             response_model=dict,
             responses={201: {"description": "Course created from import"}, 400: {"description": "Invalid ZIP"}})
async def import_course_zip(
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher),
):
    """Create a new course by importing a ZIP archive.

    The ZIP must contain a ``course.json`` manifest with title, description,
    subject, grade, language, and optionally topics/resources metadata.
    Creates the course row, extracts resources/assets/quizzes, and maps
    topic assignments from the manifest.

    Returns:
        201 with the new course_id and extraction counts.
    """
    from app.database import gen_uid
    tmp_dir = os.path.join(COURSES_DIR, f"tmp_{uuid.uuid4().hex}")
    os.makedirs(tmp_dir, exist_ok=True)
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zip')
    archive_path = os.path.join(tmp_dir, safe_filename)

    def _flush(buf):
        """Append a buffer of uploaded bytes to the temp archive file."""
        with open(archive_path, "ab") as f:
            f.write(buf)

    chunk_size = 64 * 1024
    total_size = 0
    buf = []
    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        buf.append(chunk)
        total_size += len(chunk)
        if total_size > 500 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="ZIP exceeds 500 MB limit.")  # i18n: user-facing error message
        if len(buf) >= 64:
            await asyncio.to_thread(_flush, b"".join(buf))
            buf = []
    if buf:
        await asyncio.to_thread(_flush, b"".join(buf))
    await file.close()

    def _process():
        """Create the course and extract the ZIP in a worker thread."""
        conn_sql = None
        try:
            with zipfile.ZipFile(archive_path, "r") as zf:
                names = zf.namelist()
                for name in names:
                    if '..' in name or name.startswith('/'):
                        raise _ZipError(400, f"ZIP contains invalid path: {name}")  # i18n: user-facing error message
                if "course.json" not in names:
                    raise _ZipError(400, "ZIP must contain course.json.")  # i18n: user-facing error message
                md = json.loads(zf.read("course.json"))
                title = md.get("title", "Imported Course")
                description = md.get("description", "")
                subject = md.get("subject", "gen")
                grade = md.get("grade", 0)
                language = md.get("language", "en")
                now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

                conn_sql = sqlite3.connect(DB_PATH, timeout=5.0)
                conn_sql.row_factory = sqlite3.Row
                subj_row = conn_sql.execute("SELECT id FROM subjects WHERE name = ?", (subject,)).fetchone()
                subject_id = subj_row["id"] if subj_row else ""
                course_id = gen_composite_uid(conn_sql, grade, subject, 'CRS')
                conn_sql.execute(
                    """INSERT INTO courses (id, title, description, subject, subject_id, grade, language, teacher_username, created_at, updated_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (course_id, title, description, subject, subject_id, grade, language, teacher_user, now, now)
                )

                resources_created = quizzes_found = assets_extracted = 0
                res_dir = _resources_dir(course_id)
                ast_dir = _assets_dir(course_id)
                next_pos = 0

                old_to_new_topic = {}
                for t in md.get("topics", []):
                    new_tid = gen_uid("TPC")
                    conn_sql.execute(
                        "INSERT INTO topics (id, course_id, title, description, position, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                        (new_tid, course_id, t.get("title", ""), t.get("description", ""), t.get("position", next_pos), now)
                    )
                    old_to_new_topic[t["id"]] = new_tid

                res_topic_map = {}
                for r in md.get("resources", []):
                    if r.get("topic_id") and r.get("original_name"):
                        res_topic_map[r["original_name"]] = r["topic_id"]

                for name in names:
                    if zf.getinfo(name).is_dir() or name == "course.json":
                        continue
                    if name.startswith("quiz_") and name.endswith(".json"):
                        with open(os.path.join(COURSES_DIR, course_id, name), "wb") as f:
                            f.write(zf.read(name))
                        quizzes_found += 1
                        continue
                    if name.startswith("assets/"):
                        arcname = os.path.relpath(name, "assets")
                        dest = os.path.join(ast_dir, arcname)
                        os.makedirs(os.path.dirname(dest), exist_ok=True)
                        with open(dest, "wb") as f:
                            f.write(zf.read(name))
                        assets_extracted += 1
                        continue
                    if name.startswith("resources/"):
                        orig = os.path.basename(name)
                        rid = str(uuid.uuid4())
                        _, ext = os.path.splitext(orig)
                        saved_name = f"{rid}{ext}"
                        dest = os.path.join(res_dir, saved_name)
                        with open(dest, "wb") as f:
                            f.write(zf.read(name))
                        fsize = os.path.getsize(dest)
                        rtype = "video" if ext.lower() in (".mp4", ".webm", ".avi", ".mkv") else "textbook"
                        topic_fk = old_to_new_topic.get(res_topic_map.get(orig, ""), "")
                        conn_sql.execute(
                            """INSERT INTO course_resources
                               (id, course_id, resource_type, title, original_name, filename, file_size, position, topic_id)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                            (rid, course_id, rtype, orig, orig, saved_name, fsize, next_pos, topic_fk)
                        )
                        next_pos += 1
                        resources_created += 1

                conn_sql.commit()
            return {"status": "ok", "course_id": course_id, "resources_created": resources_created,
                    "quizzes_found": quizzes_found, "assets_extracted": assets_extracted}
        except zipfile.BadZipFile:
            raise _ZipError(400, "Invalid ZIP archive.")  # i18n: user-facing error message
        except _ZipError:
            raise
        except Exception as e:
            raise _ZipError(400, f"Failed to extract archive: {e}")  # i18n: user-facing error message, {e} is the exception detail
        finally:
            if os.path.exists(tmp_dir):
                shutil.rmtree(tmp_dir, ignore_errors=True)
            try:
                if conn_sql:
                    conn_sql.close()
            except Exception:
                pass

    try:
        result = await asyncio.to_thread(_process)
    except _ZipError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)
    await audit(action=Action.IMPORT_ZIP, username=teacher_user, resource_type="course",
                resource_id=result['course_id'],
                context={"resources_created": result['resources_created'],
                         "quizzes_found": result['quizzes_found'],
                         "assets_extracted": result['assets_extracted']})
    return result


@router.get("/api/teacher/courses/{course_id}/export",
            summary="Export course as ZIP", tags=["Teacher Courses"],
            description="Streams the course as a ZIP archive with course.json manifest, resources, assets, and quizzes.",
            responses={200: {"description": "ZIP file download"}, 404: {"description": "Course not found"}})
async def export_course(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Export a course as a ZIP archive.

    Bundles ``course.json`` (full metadata + resources + topics manifest),
    all resource files under ``resources/``, assets under ``assets/``, and
    any ``quiz_*.json`` files.  Returns a streaming ZIP response.

    Raises:
        HTTPException: 404 if the course does not exist.
    """
    row = await _ensure_course_exists(course_id)
    resources = await db_fetch(
        "SELECT * FROM course_resources WHERE course_id = ? ORDER BY position ASC", (course_id,))
    topics = await db_fetch(
        "SELECT * FROM topics WHERE course_id = ? ORDER BY position ASC", (course_id,))
    course_dir = os.path.join(COURSES_DIR, course_id)
    assets_path = os.path.join(course_dir, "assets")

    def _build_zip():
        """Build the ZIP archive bytes in a worker thread."""
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            manifest = _course_to_response(row)
            manifest["resources"] = [dict(r) for r in resources]
            manifest["topics"] = [dict(t) for t in topics]
            zf.writestr("course.json", json.dumps(manifest, indent=2, default=str))
            if os.path.isdir(course_dir):
                for r in resources:
                    fpath = os.path.join(course_dir, "resources", r["filename"])
                    if os.path.isfile(fpath):
                        zf.write(fpath, f"resources/{r['filename']}")
                if os.path.isdir(assets_path):
                    for root, _, files in os.walk(assets_path):
                        for fname in files:
                            fpath = os.path.join(root, fname)
                            zf.write(fpath, os.path.relpath(fpath, course_dir))
                for fname in os.listdir(course_dir):
                    if fname.startswith("quiz_") and fname.endswith(".json"):
                        zf.write(os.path.join(course_dir, fname), fname)
        buf.seek(0)
        return buf

    zip_buf = await asyncio.to_thread(_build_zip)
    safe_title = re.sub(r'[^A-Za-z0-9_-]', '_', row["title"])
    return StreamingResponse(
        iter([zip_buf.getvalue()]),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename=\"{safe_title}.zip\""}
    )
