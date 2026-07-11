"""Teacher course management — CRUD, publishing, ZIP export/import, similar links."""
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
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query
from fastapi.responses import StreamingResponse
from app.database import UPLOAD_DIR, DB_PATH, log_admin_action
from app.async_db import db_conn, db_exec, db_fetch, db_fetch_one, db_run
from app.dependencies import verify_teacher
from app.models import CourseCreate, StatusResponse, SimilarLinkCreate, SimilarLinkResponse

router = APIRouter()
COURSES_DIR = os.path.abspath(os.path.join(UPLOAD_DIR, "..", "courses"))
os.makedirs(COURSES_DIR, exist_ok=True)


def _course_to_response(row) -> dict:
    return {
        "id": row["id"], "title": row["title"], "description": row["description"],
        "subject": row["subject"], "grade": row["grade"], "language": row["language"],
        "cover_image": row["cover_image"], "published": row["published"],
        "teacher_username": row["teacher_username"], "enrollment_count": row["enrollment_count"],
        "created_at": row["created_at"], "updated_at": row["updated_at"],
    }


def _resources_dir(course_id: str) -> str:
    d = os.path.join(COURSES_DIR, course_id, "resources")
    os.makedirs(d, exist_ok=True)
    return d


def _assets_dir(course_id: str) -> str:
    d = os.path.join(COURSES_DIR, course_id, "assets")
    os.makedirs(d, exist_ok=True)
    return d


async def _ensure_course_owner(course_id: str, teacher_user: str):
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")
    if row["teacher_username"] != teacher_user:
        raise HTTPException(status_code=404, detail="Course not found.")
    return row


# ─── Write chunk helper ───────────────────────────────────────────────────

async def _write_chunked(dest_path: str, file: UploadFile, max_size: int) -> int:
    """Read file in chunks, flush to disk in ~4 MB batches. Returns total bytes written."""
    chunk_size = 64 * 1024
    total_size = 0
    chunk_buffer = b""
    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        chunk_buffer += chunk
        total_size += len(chunk)
        if total_size > max_size:
            raise HTTPException(status_code=400, detail=f"File exceeds {max_size // (1024 * 1024)} MB limit.")
        if len(chunk_buffer) >= 4 * 1024 * 1024:
            buf = chunk_buffer
            await asyncio.to_thread(lambda: open(dest_path, "ab" if os.path.exists(dest_path) else "wb").write(buf))
            chunk_buffer = b""
    if chunk_buffer:
        await asyncio.to_thread(lambda: open(dest_path, "ab" if os.path.exists(dest_path) else "wb").write(chunk_buffer))
    await file.close()
    return total_size


# ─── Static-path routes (before {id} to avoid capture) ────────────────────

@router.get("/api/teacher/courses/suggest-similar",
            summary="Search published courses across all teachers",
            description="Returns up to 20 published courses matching the search query from ALL teachers. Used for cross-teacher similar-course linking.",
            tags=["Teacher Courses"],
            responses={200: {"description": "List of matching courses"}})
async def suggest_similar_courses(q: str = Query("", description="Search query for course title")):
    """Search published courses by title across all teachers.

    Args:
        q: Substring to match against course title.

    Returns:
        List of up to 20 matching courses with id, title, subject, grade, teacher_username.
    """
    if not q:
        return []
    rows = await db_fetch(
        "SELECT id, title, subject, grade, teacher_username FROM courses WHERE published = 1 AND title LIKE ? LIMIT 20",
        (f"%{q}%",)
    )
    return [dict(r) for r in rows]


# ─── CRUD ─────────────────────────────────────────────────────────────────

@router.post("/api/teacher/courses",
             summary="Create a new course",
             description="Creates a course with the given metadata. The teacher_username is set from the authenticated session.",
             tags=["Teacher Courses"],
             responses={201: {"description": "Created course"}})
async def create_course(data: CourseCreate, teacher_user: str = Depends(verify_teacher)):
    """Create a new course.

    Args:
        data: Course metadata (title, description, subject, grade, language).

    Returns:
        The created course dict.
    """
    course_id = str(uuid.uuid4())
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        """INSERT INTO courses (id, title, description, subject, grade, language, teacher_username, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (course_id, data.title, data.description, data.subject, data.grade, data.language, teacher_user, now, now)
    )
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await log_admin_action(teacher_user, f"Created course '{data.title}' (id={course_id})")
    return _course_to_response(row)


@router.get("/api/teacher/courses",
            summary="List own courses",
            description="Returns all courses owned by the authenticated teacher, ordered by most recently updated.",
            tags=["Teacher Courses"],
            responses={200: {"description": "List of courses"}})
async def list_courses(teacher_user: str = Depends(verify_teacher)):
    """List all courses for the authenticated teacher.

    Returns:
        List of course dicts ordered by updated_at DESC.
    """
    rows = await db_fetch(
        "SELECT * FROM courses WHERE teacher_username = ? ORDER BY updated_at DESC",
        (teacher_user,)
    )
    return [_course_to_response(r) for r in rows]


@router.get("/api/teacher/courses/{course_id}",
            summary="Get course detail",
            description="Returns full course metadata, its resources (ordered by position), and similar course links.",
            tags=["Teacher Courses"],
            responses={200: {"description": "Course detail with resources and similar links"}, 404: {"description": "Course not found"}})
async def get_course_detail(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Get full course detail including resources and similar course links.

    Args:
        course_id: UUID of the course.

    Returns:
        Dict with course metadata, resources list, and similar_courses list.
    """
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")
    resources = await db_fetch(
        "SELECT * FROM course_resources WHERE course_id = ? ORDER BY position ASC",
        (course_id,)
    )
    similar = await db_fetch(
        "SELECT * FROM similar_courses WHERE course_id = ?",
        (course_id,)
    )
    result = _course_to_response(row)
    result["resources"] = [dict(r) for r in resources]
    result["similar_courses"] = [dict(s) for s in similar]
    return result


@router.put("/api/teacher/courses/{course_id}",
            summary="Update course metadata",
            description="Updates the title, description, subject, grade, and language of a course. Only the owning teacher may update.",
            tags=["Teacher Courses"],
            responses={200: {"description": "Updated course"}, 404: {"description": "Course not found"}})
async def update_course(course_id: str, data: CourseCreate, teacher_user: str = Depends(verify_teacher)):
    """Update course metadata.

    Args:
        course_id: UUID of the course to update.
        data: Updated course metadata.

    Returns:
        The updated course dict.
    """
    await _ensure_course_owner(course_id, teacher_user)
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        """UPDATE courses SET title = ?, description = ?, subject = ?, grade = ?, language = ?, updated_at = ?
           WHERE id = ?""",
        (data.title, data.description, data.subject, data.grade, data.language, now, course_id)
    )
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await log_admin_action(teacher_user, f"Updated course '{data.title}' (id={course_id})")
    return _course_to_response(row)


@router.delete("/api/teacher/courses/{course_id}",
               summary="Soft-delete a course",
               description="Sets published = -1 to archive the course. Hard deletion is not available — courses are soft-deleted only.",
               tags=["Teacher Courses"],
               responses={200: {"description": "Course archived"}, 404: {"description": "Course not found"}})
async def delete_course(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Soft-delete a course by setting published = -1 (archived).

    Args:
        course_id: UUID of the course to archive.
    """
    row = await _ensure_course_owner(course_id, teacher_user)
    await db_exec("UPDATE courses SET published = -1, updated_at = datetime('now') WHERE id = ?", (course_id,))
    await log_admin_action(teacher_user, f"Archived course '{row['title']}' (id={course_id})")
    return {"status": "ok", "message": f"Course '{row['title']}' archived."}


# ─── Publishing ───────────────────────────────────────────────────────────

@router.post("/api/teacher/courses/{course_id}/publish",
             summary="Toggle course published status",
             description="Toggles the published flag between 0 (draft) and 1 (published). Only the owning teacher may publish.",
             tags=["Teacher Courses"],
             responses={200: {"description": "Toggled publish status"}, 404: {"description": "Course not found"}})
async def toggle_publish(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Toggle course published status between 0 (draft) and 1 (published).

    Args:
        course_id: UUID of the course.
    """
    row = await _ensure_course_owner(course_id, teacher_user)
    new_val = 0 if row["published"] == 1 else 1
    await db_exec("UPDATE courses SET published = ?, updated_at = datetime('now') WHERE id = ?", (new_val, course_id))
    action = "Published" if new_val == 1 else "Unpublished"
    await log_admin_action(teacher_user, f"{action} course '{row['title']}' (id={course_id})")
    updated = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    return _course_to_response(updated)


# ─── Resource upload ──────────────────────────────────────────────────────

@router.post("/api/teacher/courses/{course_id}/upload-resource",
             summary="Upload a resource file to a course",
             description="Uploads a single file as a course resource. Validates file size < 500 MB. The file is saved with a UUID prefix to avoid collisions.",
             tags=["Teacher Courses"],
             responses={200: {"description": "Resource created"}, 400: {"description": "File too large or invalid"}, 404: {"description": "Course not found"}})
async def upload_course_resource(
    course_id: str,
    resource_type: str = Query(..., description="Resource type (textbook, video, notes, etc.)"),
    title: str = Query("", description="Display title for the resource"),
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher),
):
    """Upload a single file as a course resource.

    Args:
        course_id: UUID of the target course.
        resource_type: Type of resource (textbook, video, notes, pyq, etc.).
        title: Optional display title (defaults to original filename).
        file: The file to upload (max 500 MB).

    Returns:
        The created course_resource row as a dict.
    """
    await _ensure_course_owner(course_id, teacher_user)

    original_name = file.filename or "unnamed_file"
    resource_id = str(uuid.uuid4())
    ext = os.path.splitext(original_name)[1]
    saved_name = f"{resource_id}{ext}"
    dest_dir = _resources_dir(course_id)
    dest_path = os.path.join(dest_dir, saved_name)

    total_size = await _write_chunked(dest_path, file, 500 * 1024 * 1024)
    disp_title = title if title else original_name

    last_pos = await db_fetch_one(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM course_resources WHERE course_id = ?",
        (course_id,)
    )
    next_pos = (last_pos["mp"] if last_pos and last_pos["mp"] is not None else -1) + 1

    await db_exec(
        """INSERT INTO course_resources (id, course_id, resource_type, title, original_name, filename, file_size, position)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (resource_id, course_id, resource_type, disp_title, original_name, saved_name, total_size, next_pos)
    )
    await log_admin_action(teacher_user, f"Uploaded resource '{disp_title}' to course {course_id}")
    row = await db_fetch_one("SELECT * FROM course_resources WHERE id = ?", (resource_id,))
    return dict(row)


@router.post("/api/teacher/courses/{course_id}/upload-zip",
             summary="Import course content from a ZIP archive",
             description="Extracts a ZIP containing course.json (metadata), resources/ (files), assets/ (cover images etc.), and quiz_*.json files. Validates paths to prevent traversal attacks.",
             tags=["Teacher Courses"],
             responses={200: {"description": "Import summary"}, 400: {"description": "Invalid ZIP"}, 404: {"description": "Course not found"}})
async def upload_course_zip(
    course_id: str,
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher),
):
    """Import course content from a structured ZIP archive.

    Expected ZIP layout:
      course.json          — JSON with title, description, subject, grade, language
      resources/           — files become course_resources entries
      assets/              — cover images, extras → saved to assets dir
      quiz_*.json          — quiz definitions → saved alongside resources

    Args:
        course_id: UUID of the target course.
        file: The ZIP archive.

    Returns:
        Dict with status, resources_created, quizzes_found, assets_extracted.
    """
    await _ensure_course_owner(course_id, teacher_user)

    tmp_dir = os.path.join(COURSES_DIR, f"tmp_{uuid.uuid4().hex}")
    os.makedirs(tmp_dir, exist_ok=True)

    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zip')
    archive_path = os.path.join(tmp_dir, safe_filename)

    def _flush(buf):
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
            raise HTTPException(status_code=400, detail="ZIP exceeds 500 MB limit.")
        if len(buf) >= 64:
            await asyncio.to_thread(_flush, b"".join(buf))
            buf = []
    if buf:
        await asyncio.to_thread(_flush, b"".join(buf))
    await file.close()

    def _process():
        conn = None
        try:
            with zipfile.ZipFile(archive_path, "r") as zf:
                names = zf.namelist()
                for name in names:
                    if '..' in name or name.startswith('/'):
                        raise HTTPException(status_code=400, detail=f"ZIP contains invalid path: {name}")

                resources_created = 0
                quizzes_found = 0
                assets_extracted = 0

                res_dir = _resources_dir(course_id)
                ast_dir = _assets_dir(course_id)

                # Determine next position
                conn_sql = sqlite3.connect(DB_PATH, timeout=5.0)
                conn_sql.row_factory = sqlite3.Row
                last_row = conn_sql.execute(
                    "SELECT COALESCE(MAX(position), -1) AS mp FROM course_resources WHERE course_id = ?",
                    (course_id,)
                ).fetchone()
                next_pos = (last_row["mp"] if last_row and last_row["mp"] is not None else -1) + 1

                # Apply metadata from course.json if present
                if "course.json" in names:
                    md = json.loads(zf.read("course.json"))
                    cur_row = conn_sql.execute(
                        "SELECT title, description, subject, grade, language FROM courses WHERE id=?", (course_id,)
                    ).fetchone()
                    fallback = dict(cur_row) if cur_row else {}
                    title = md.get("title", fallback.get("title", ""))
                    description = md.get("description", fallback.get("description", ""))
                    subject = md.get("subject", fallback.get("subject", ""))
                    grade = md.get("grade", fallback.get("grade", 0))
                    language = md.get("language", fallback.get("language", "en"))
                    conn_sql.execute(
                        """UPDATE courses SET title=?, description=?, subject=?, grade=?, language=?, updated_at=datetime('now')
                           WHERE id=?""",
                        (title, description, subject, grade, language, course_id)
                    )

                for name in names:
                    if zf.getinfo(name).is_dir():
                        continue

                    if name == "course.json":
                        continue

                    # quiz_*.json — save alongside resources
                    if name.startswith("quiz_") and name.endswith(".json"):
                        data = zf.read(name)
                        qdest = os.path.join(COURSES_DIR, course_id, name)
                        with open(qdest, "wb") as f:
                            f.write(data)
                        quizzes_found += 1
                        continue

                    # assets/
                    if name.startswith("assets/"):
                        arcname = os.path.relpath(name, "assets")
                        dest = os.path.join(ast_dir, arcname)
                        os.makedirs(os.path.dirname(dest), exist_ok=True)
                        with open(dest, "wb") as f:
                            f.write(zf.read(name))
                        assets_extracted += 1
                        continue

                    # resources/
                    if name.startswith("resources/"):
                        orig = os.path.basename(name)
                        rid = str(uuid.uuid4())
                        _, ext = os.path.splitext(orig)
                        saved_name = f"{rid}{ext}"
                        dest = os.path.join(res_dir, saved_name)
                        with open(dest, "wb") as f:
                            f.write(zf.read(name))
                        fsize = os.path.getsize(dest)

                        rtype = "textbook"
                        if ext.lower() in (".mp4", ".webm", ".avi", ".mkv"):
                            rtype = "video"
                        elif ext.lower() in (".pdf", ".epub"):
                            rtype = "textbook"

                        conn_sql.execute(
                            """INSERT INTO course_resources
                               (id, course_id, resource_type, title, original_name, filename, file_size, position)
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                            (rid, course_id, rtype, orig, orig, saved_name, fsize, next_pos)
                        )
                        next_pos += 1
                        resources_created += 1

                conn_sql.commit()
                conn_sql.close()
                conn_sql = None

            return {
                "status": "ok",
                "resources_created": resources_created,
                "quizzes_found": quizzes_found,
                "assets_extracted": assets_extracted,
            }

        except zipfile.BadZipFile:
            raise HTTPException(status_code=400, detail="Invalid ZIP archive.")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to extract archive: {e}")
        finally:
            if os.path.exists(tmp_dir):
                shutil.rmtree(tmp_dir, ignore_errors=True)
            # Ensure cleanup if we opened SQLite
            try:
                if conn_sql:
                    conn_sql.close()
            except Exception:
                pass

    result = await asyncio.to_thread(_process)
    await log_admin_action(teacher_user,
        f"Imported ZIP into course {course_id}: {result['resources_created']} resources, "
        f"{result['quizzes_found']} quizzes, {result['assets_extracted']} assets"
    )
    return result


# ─── ZIP export ───────────────────────────────────────────────────────────

@router.get("/api/teacher/courses/{course_id}/export",
            summary="Export course as ZIP",
            description="Builds a ZIP archive containing course.json (metadata + resource list), all resource files, assets, and quiz definition files.",
            tags=["Teacher Courses"],
            responses={200: {"content": {"application/zip": {}}}, 404: {"description": "Course not found"}})
async def export_course(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Export a course as a downloadable ZIP archive.

    Args:
        course_id: UUID of the course to export.

    Returns:
        StreamingResponse with ZIP content.
    """
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")

    resources = await db_fetch(
        "SELECT * FROM course_resources WHERE course_id = ? ORDER BY position ASC",
        (course_id,)
    )

    course_dir = os.path.join(COURSES_DIR, course_id)
    assets_path = os.path.join(course_dir, "assets")

    def _build_zip():
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            manifest = _course_to_response(row)
            manifest["resources"] = [dict(r) for r in resources]
            zf.writestr("course.json", json.dumps(manifest, indent=2, default=str))

            for r in resources:
                fpath = os.path.join(course_dir, "resources", r["filename"])
                if os.path.isfile(fpath):
                    zf.write(fpath, f"resources/{r['filename']}")

            if os.path.isdir(assets_path):
                for root, _, files in os.walk(assets_path):
                    for fname in files:
                        fpath = os.path.join(root, fname)
                        arcname = os.path.relpath(fpath, course_dir)
                        zf.write(fpath, arcname)

            for fname in os.listdir(course_dir):
                if fname.startswith("quiz_") and fname.endswith(".json"):
                    fpath = os.path.join(course_dir, fname)
                    zf.write(fpath, fname)

        buf.seek(0)
        return buf

    zip_buf = await asyncio.to_thread(_build_zip)
    safe_title = re.sub(r'[^A-Za-z0-9_-]', '_', row["title"])
    return StreamingResponse(
        iter([zip_buf.getvalue()]),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename=\"{safe_title}.zip\""}
    )


# ─── Quiz management ──────────────────────────────────────────────────────

@router.put("/api/teacher/courses/{course_id}/quiz/{resource_id}",
            summary="Save quiz JSON for a course resource",
            description="Validates and saves quiz data for a course resource. Computes quiz_version by incrementing the previous version.",
            tags=["Teacher Courses"],
            responses={200: {"description": "Quiz saved"}, 400: {"description": "Invalid quiz data"}, 404: {"description": "Course or resource not found"}})
async def save_course_quiz(
    course_id: str,
    resource_id: str,
    data: dict,
    teacher_user: str = Depends(verify_teacher),
):
    """Save quiz JSON for a course resource.

    The body must contain a ``quiz`` key with a ``questions`` array.
    Each question must have ``id``, ``type``, and ``question`` fields.
    At least one question is required.

    Args:
        course_id: UUID of the course.
        resource_id: UUID of the course resource.
        data: Dict with ``quiz`` key.

    Returns:
        Dict with status and quiz_version.
    """
    await _ensure_course_owner(course_id, teacher_user)

    resource = await db_fetch_one(
        "SELECT id FROM course_resources WHERE id = ? AND course_id = ?",
        (resource_id, course_id)
    )
    if not resource:
        raise HTTPException(status_code=404, detail="Resource not found in this course.")

    quiz = data.get("quiz")
    if not isinstance(quiz, dict):
        raise HTTPException(status_code=400, detail="Body must contain a 'quiz' object.")
    questions = quiz.get("questions")
    if not isinstance(questions, list) or len(questions) == 0:
        raise HTTPException(status_code=400, detail="Quiz must have at least one question.")
    for i, q in enumerate(questions):
        if not all(k in q for k in ("id", "type", "question")):
            raise HTTPException(
                status_code=400,
                detail=f"Question at index {i} is missing one of: id, type, question."
            )

    quiz_dir = os.path.join(COURSES_DIR, course_id)
    os.makedirs(quiz_dir, exist_ok=True)
    quiz_path = os.path.join(quiz_dir, f"quiz_{resource_id}.json")

    def _save():
        quiz_version = 1
        if os.path.isfile(quiz_path):
            try:
                with open(quiz_path, "r") as f:
                    existing = json.load(f)
                if isinstance(existing, dict) and "quiz_version" in existing.get("quiz", {}):
                    quiz_version = existing["quiz"]["quiz_version"] + 1
            except (json.JSONDecodeError, OSError):
                quiz_version = 1
        quiz["quiz_version"] = quiz_version
        with open(quiz_path, "w") as f:
            json.dump({"quiz": quiz}, f, indent=2)
        return quiz_version

    version = await asyncio.to_thread(_save)
    await log_admin_action(teacher_user, f"Saved quiz v{version} for resource {resource_id} in course {course_id}")
    return {"status": "ok", "quiz_version": version}


# ─── Similar courses ──────────────────────────────────────────────────────

@router.get("/api/teacher/courses/{course_id}/similar",
            summary="List similar course links",
            description="Returns all bidirectional similar-course links for the given course.",
            tags=["Teacher Courses"],
            responses={200: {"description": "List of similar links"}})
async def list_similar_courses(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """List all similar-course links involving this course (bidirectional).

    Args:
        course_id: UUID of the course.

    Returns:
        List of similar_courses rows.
    """
    rows = await db_fetch(
        "SELECT * FROM similar_courses WHERE course_id = ? OR similar_course_id = ?",
        (course_id, course_id)
    )
    return [dict(r) for r in rows]


@router.post("/api/teacher/courses/{course_id}/similar",
             summary="Add a similar course link",
             description="Creates a bidirectional similar-course link. Both courses must exist. Prevents self-referencing and duplicate links.",
             tags=["Teacher Courses"],
             responses={200: {"description": "Link created"}, 400: {"description": "Invalid link"}, 404: {"description": "Course not found"}})
async def add_similar_course(
    course_id: str,
    data: SimilarLinkCreate,
    teacher_user: str = Depends(verify_teacher),
):
    """Add a bidirectional similar-course link.

    Creates both (course_id, similar_course_id) and (similar_course_id, course_id) rows.

    Args:
        course_id: UUID of the source course.
        data: Payload with similar_course_id.

    Returns:
        StatusResponse.
    """
    c1 = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (course_id,))
    c2 = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (data.similar_course_id,))
    if not c1 or not c2:
        raise HTTPException(status_code=404, detail="One or both courses not found.")

    if course_id == data.similar_course_id:
        raise HTTPException(status_code=400, detail="A course cannot link to itself.")

    dup = await db_fetch_one(
        "SELECT 1 FROM similar_courses WHERE course_id = ? AND similar_course_id = ?",
        (course_id, data.similar_course_id)
    )
    if dup:
        raise HTTPException(status_code=400, detail="Similar link already exists.")

    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        "INSERT INTO similar_courses (course_id, similar_course_id, created_by, created_at) VALUES (?, ?, ?, ?)",
        (course_id, data.similar_course_id, teacher_user, now)
    )
    await db_exec(
        "INSERT OR IGNORE INTO similar_courses (course_id, similar_course_id, created_by, created_at) VALUES (?, ?, ?, ?)",
        (data.similar_course_id, course_id, teacher_user, now)
    )
    await log_admin_action(teacher_user, f"Linked similar courses {course_id} <-> {data.similar_course_id}")
    return {"status": "ok", "message": "Similar link created."}


@router.delete("/api/teacher/courses/{course_id}/similar/{similar_id}",
               summary="Remove a similar course link",
               description="Removes the bidirectional similar-course link between two courses.",
               tags=["Teacher Courses"],
               responses={200: {"description": "Link removed"}, 404: {"description": "Link not found"}})
async def remove_similar_course(
    course_id: str,
    similar_id: str,
    teacher_user: str = Depends(verify_teacher),
):
    """Remove a bidirectional similar-course link.

    Deletes both (course_id, similar_id) and (similar_id, course_id) rows.

    Args:
        course_id: UUID of one course.
        similar_id: UUID of the other course.
    """
    existing = await db_fetch_one(
        "SELECT 1 FROM similar_courses WHERE (course_id = ? AND similar_course_id = ?) OR (course_id = ? AND similar_course_id = ?)",
        (course_id, similar_id, similar_id, course_id)
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Similar link not found.")

    await db_exec(
        "DELETE FROM similar_courses WHERE (course_id = ? AND similar_course_id = ?) OR (course_id = ? AND similar_course_id = ?)",
        (course_id, similar_id, similar_id, course_id)
    )
    await log_admin_action(teacher_user, f"Removed similar link between {course_id} and {similar_id}")
    return {"status": "ok", "message": "Similar link removed."}
