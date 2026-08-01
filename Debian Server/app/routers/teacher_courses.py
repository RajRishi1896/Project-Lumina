"""Teacher course management -- CRUD, publishing, and shared helpers."""
import os
import asyncio
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from app.database import UPLOAD_DIR, gen_composite_uid
from app.audit import audit, Action
from app.async_db import db_conn, db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.models import CourseCreate

router = APIRouter()
COURSES_DIR = os.path.join(UPLOAD_DIR, "courses")
os.makedirs(COURSES_DIR, exist_ok=True)


def _course_to_response(row) -> dict:
    """Convert a database row to a CourseResponse dict."""
    return {
        "id": row["id"], "title": row["title"], "description": row["description"],
        "subject": row["subject"], "grade": row["grade"], "language": row["language"],
        "cover_image": row["cover_image"], "published": row["published"],
        "teacher_username": row["teacher_username"], "enrollment_count": row["enrollment_count"],
        "resource_count": row["resource_count"] if "resource_count" in row.keys() else 0,
        "created_at": row["created_at"], "updated_at": row["updated_at"],
    }


def _resources_dir(course_id: str) -> str:
    """Return (and create if needed) the resources directory for a course."""
    d = os.path.join(COURSES_DIR, course_id, "resources")
    os.makedirs(d, exist_ok=True)
    return d


def _assets_dir(course_id: str) -> str:
    """Return (and create if needed) the assets directory for a course."""
    d = os.path.join(COURSES_DIR, course_id, "assets")
    os.makedirs(d, exist_ok=True)
    return d


async def _ensure_course_owner(course_id: str, teacher_user: str):
    """Verify the current user owns the course or is an admin.

    Returns the course row if authorised.

    Raises:
        HTTPException: 404 if course not found or user is not owner/admin.
    """
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")  # i18n: user-facing error message
    if row["teacher_username"] != teacher_user:
        user = await db_fetch_one("SELECT role FROM users WHERE username = ?", (teacher_user,))
        if not user or user["role"] != "admin":
            raise HTTPException(status_code=404, detail="Course not found.")  # i18n: user-facing error message (deliberately same text to avoid leaking info)
    return row


async def _write_chunked(dest_path: str, file: UploadFile, max_size: int,
                         request=None, support_resume: bool = False) -> int:
    """Write an uploaded file to disk in 64KB chunks with a size limit.

    Buffers up to 4MB in memory before flushing to disk to reduce I/O
    cycles on low-end hardware. When ``support_resume`` is True, writes to
    a ``.part`` file first and renames on completion. Supports
    ``Content-Range`` header for resume.

    Args:
        dest_path: Destination file path on disk.
        file: The FastAPI UploadFile object.
        max_size: Maximum allowed file size in bytes.
        request: Optional FastAPI Request to read Content-Range header.
        support_resume: Enable .part file + resume logic.

    Returns:
        Total bytes written.

    Raises:
        HTTPException: 400 if the file exceeds max_size.
    """
    chunk_size = 64 * 1024
    total_size = 0
    chunk_buffer = b""
    first_write = True
    part_path = f"{dest_path}.part" if support_resume else dest_path
    existing_bytes = 0

    if support_resume and await asyncio.to_thread(os.path.exists, part_path):
        existing_bytes = await asyncio.to_thread(os.path.getsize, part_path)

    content_range = None
    if request is not None:
        content_range = request.headers.get("content-range")

    if support_resume and content_range:
        # Content-Range: bytes START-END/TOTAL
        try:
            range_spec = content_range.split(" ", 1)[1]
            byte_range, total = range_spec.split("/")
            start_str, end_str = byte_range.split("-")
            start = int(start_str)
            existing_bytes = start
        except Exception:
            existing_bytes = 0

    total_size = existing_bytes

    def _flush(data):
        nonlocal first_write
        mode = "wb" if first_write and not existing_bytes else "ab"
        first_write = False
        with open(part_path, mode) as f:
            if first_write and not existing_bytes:
                pass  # already wb mode
            f.write(data)

    # For resume, we need to seek to the right position on first write
    if support_resume and existing_bytes and not content_range:
        def _init_append():
            # Just open in append mode — file already has existing bytes
            with open(part_path, "ab") as f:
                pass  # create if missing
        await asyncio.to_thread(_init_append)

    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        chunk_buffer += chunk
        total_size += len(chunk)
        if total_size > max_size:
            raise HTTPException(status_code=400, detail=f"File exceeds {max_size // (1024 * 1024)} MB limit.")  # i18n: user-facing error message
        if len(chunk_buffer) >= 4 * 1024 * 1024:
            await asyncio.to_thread(_flush, chunk_buffer)
            chunk_buffer = b""
    if chunk_buffer:
        await asyncio.to_thread(_flush, chunk_buffer)
    await file.close()

    if support_resume and part_path != dest_path:
        await asyncio.to_thread(os.rename, part_path, dest_path)

    return total_size


# ─── Static-path routes ──────────────────────────────────────────────────

@router.get("/api/teacher/courses/suggest-similar",
            summary="Search published courses across all teachers",
            tags=["Teacher Courses"])
async def suggest_similar_courses(q: str = Query("", description="Search query for course title")):
    """Search published courses across all teachers by title substring.

    Returns up to 20 matching courses for the similar-courses picker.
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
             summary="Create a new course", tags=["Teacher Courses"],
             responses={201: {"description": "Created course"}})
async def create_course(data: CourseCreate, teacher_user: str = Depends(verify_teacher)):
    """Create a new course with the given metadata.

    Generates a composite UID incorporating grade and subject, persists the
    course row, and logs the action to the audit log.

    Returns:
        201 with the created course metadata.
    """
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    subj_row = await db_fetch_one("SELECT id FROM subjects WHERE name = ?", (data.subject,))
    subject_id = subj_row["id"] if subj_row else ""
    async with db_conn() as conn:
        course_id = gen_composite_uid(conn, data.grade, data.subject, 'CRS')
        conn.execute(
            """INSERT INTO courses (id, title, description, subject, subject_id, grade, language, teacher_username, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (course_id, data.title, data.description, data.subject, subject_id, data.grade, data.language, teacher_user, now, now)
        )
        conn.commit()
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await audit(action=Action.CREATE_COURSE, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=data.title)
    return _course_to_response(row)


@router.get("/api/teacher/courses",
            summary="List own courses", tags=["Teacher Courses"])
async def list_courses(teacher_user: str = Depends(verify_teacher)):
    """List all non-archived courses ordered by last update.

    Includes a resource_count subquery for each course.
    """
    # Non-admin teachers only see their own courses
    user_role = await db_fetch_one("SELECT role FROM users WHERE username = ?", (teacher_user,))
    is_admin = user_role and user_role["role"] == "admin"
    if is_admin:
        rows = await db_fetch(
            "SELECT c.*, (SELECT COUNT(*) FROM course_resources WHERE course_id = c.id) AS resource_count FROM courses c WHERE c.published != -1 ORDER BY c.updated_at DESC"
        )
    else:
        rows = await db_fetch(
            "SELECT c.*, (SELECT COUNT(*) FROM course_resources WHERE course_id = c.id) AS resource_count FROM courses c WHERE c.published != -1 AND c.teacher_username = ? ORDER BY c.updated_at DESC",
            (teacher_user,)
        )
    return [_course_to_response(r) for r in rows]


@router.get("/api/teacher/courses/{course_id}",
            summary="Get course detail", tags=["Teacher Courses"],
            responses={200: {"description": "Course detail"}, 404: {"description": "Course not found"}})
async def get_course_detail(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Return full course detail including resources, topics, and similar courses.

    Raises:
        HTTPException: 404 if the course does not exist.
    """
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")  # i18n: user-facing error message
    resources = await db_fetch(
        "SELECT * FROM course_resources WHERE course_id = ? ORDER BY position ASC", (course_id,))
    topics = await db_fetch(
        "SELECT * FROM topics WHERE course_id = ? ORDER BY position ASC", (course_id,))
    similar = await db_fetch(
        "SELECT * FROM similar_courses WHERE course_id = ?", (course_id,))
    result = _course_to_response(row)
    result["resources"] = [dict(r) for r in resources]
    result["topics"] = [dict(t) for t in topics]
    result["similar_courses"] = [dict(s) for s in similar]
    return result


@router.put("/api/teacher/courses/{course_id}",
            summary="Update course metadata", tags=["Teacher Courses"])
async def update_course(course_id: str, data: CourseCreate, teacher_user: str = Depends(verify_teacher)):
    """Update course metadata (title, description, subject, grade, language).

    Verifies ownership before updating. Logs the change to the audit log.
    """
    await _ensure_course_owner(course_id, teacher_user)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        """UPDATE courses SET title = ?, description = ?, subject = ?, grade = ?, language = ?, updated_at = ?
           WHERE id = ?""",
        (data.title, data.description, data.subject, data.grade, data.language, now, course_id)
    )
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await audit(action=Action.UPDATE_COURSE, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=data.title)
    return _course_to_response(row)


@router.delete("/api/teacher/courses/{course_id}",
               summary="Soft-delete a course", tags=["Teacher Courses"])
async def delete_course(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Soft-delete a course by setting published = -1.

    The course is archived, not removed from the database. Resources remain
    on disk. Logs the action to the audit log.
    """
    row = await _ensure_course_owner(course_id, teacher_user)
    await db_exec("UPDATE courses SET published = -1, updated_at = datetime('now') WHERE id = ?", (course_id,))
    await audit(action=Action.DELETE_COURSE, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=row['title'])
    return {"status": "ok", "message": f"Course '{row['title']}' archived."}  # i18n: user-facing success message


# ─── Publishing ───────────────────────────────────────────────────────────

@router.post("/api/teacher/courses/{course_id}/publish",
             summary="Toggle course published status", tags=["Teacher Courses"])
async def toggle_publish(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Toggle a course between published (1) and unpublished (0).

    Verifies ownership, flips the published flag, and logs the action.
    """
    row = await _ensure_course_owner(course_id, teacher_user)
    new_val = 0 if row["published"] == 1 else 1
    await db_exec("UPDATE courses SET published = ?, updated_at = datetime('now') WHERE id = ?", (new_val, course_id))
    action = Action.PUBLISH_COURSE if new_val == 1 else Action.UNPUBLISH_COURSE
    await audit(action=action, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=row['title'], context={"published": new_val})
    updated = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    return _course_to_response(updated)
