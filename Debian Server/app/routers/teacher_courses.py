"""Teacher course management: CRUD, publishing, and shared helpers."""
import os
import asyncio
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, UploadFile, Query
from app.database import UPLOAD_DIR, gen_composite_uid
from app.audit import audit, Action
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.course_cover import save_course_cover
from app.course_meta import bump_course_version
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
        "version": row["version"] if "version" in row.keys() and row["version"] is not None else 1,
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


async def _ensure_course_exists(course_id: str):
    """Verify the course exists.

    Any authenticated teacher may edit any course; ownership is not
    enforced (all courses are shared hub content).

    Returns the course row if it exists.

    Raises:
        HTTPException: 404 if course not found.
    """
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")  # i18n: user-facing error message
    return row


async def _require_course_resources(course_id: str):
    """Raise 400 when the course has zero rows in course_resources."""
    row = await db_fetch_one("SELECT COUNT(*) AS n FROM course_resources WHERE course_id = ?", (course_id,))
    if not row or not row["n"]:
        raise HTTPException(status_code=400, detail="Cannot publish a course with no resources. Add at least one resource first.")  # i18n: user-facing error message


async def _write_chunked(dest_path: str, file: UploadFile, max_size: int) -> int:
    """Write an uploaded file to disk in 64KB chunks with a size limit.

    Buffers up to 4MB in memory before flushing to disk to reduce I/O
    cycles on low-end hardware. Cleans up the partial file on size rejection.

    Args:
        dest_path: Destination file path on disk.
        file: The FastAPI UploadFile object.
        max_size: Maximum allowed file size in bytes.

    Returns:
        Total bytes written.

    Raises:
        HTTPException: 400 if the file exceeds max_size.
    """
    chunk_size = 64 * 1024
    total_size = 0
    chunk_buffer = b""

    def _flush(data):
        """Append a buffered batch of bytes to the destination file in one open/write/close cycle."""
        with open(dest_path, "ab") as f:
            f.write(data)

    try:
        while True:
            chunk = await file.read(chunk_size)
            if not chunk:
                break
            chunk_buffer += chunk
            total_size += len(chunk)
            if total_size > max_size:
                # Clean up partial file before raising
                try:
                    os.remove(dest_path)
                except OSError:
                    pass
                raise HTTPException(status_code=400, detail=f"File exceeds {max_size // (1024 * 1024)} MB limit.")  # i18n: user-facing error message
            if len(chunk_buffer) >= 4 * 1024 * 1024:
                await asyncio.to_thread(_flush, chunk_buffer)
                chunk_buffer = b""
        if chunk_buffer:
            await asyncio.to_thread(_flush, chunk_buffer)
    except HTTPException:
        raise
    except Exception:
        # Clean up on any unexpected error
        try:
            os.remove(dest_path)
        except OSError:
            pass
        raise
    await file.close()

    return total_size


# ─── Static-path routes ──────────────────────────────────────────────────

@router.get("/api/teacher/courses/suggest-similar",
            summary="Search published courses across all teachers",
            tags=["Teacher Courses"],
            description="Searches published courses by title substring for the similar-courses picker.",
            response_model=list,
            responses={200: {"description": "Up to 20 matching courses"}})
async def suggest_similar_courses(q: str = Query("", description="Search query for course title"),
                                   teacher_user: str = Depends(verify_teacher)):
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
             description="Creates a new course with the given metadata. The course ID is a composite of grade and subject. Accepts an optional cover_image data-URL.",
             response_model=dict,
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

    def _insert_course(conn):
        """Generate the composite course ID and insert the course row within the caller's transaction."""
        course_id = gen_composite_uid(conn, data.grade, data.subject, 'CRS')
        conn.execute(
            """INSERT INTO courses (id, title, description, subject, subject_id, grade, language, teacher_username, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (course_id, data.title, data.description, data.subject, subject_id, data.grade, data.language, teacher_user, now, now)
        )
        conn.commit()
        return course_id

    course_id = await db_run(_insert_course)
    cover_rel = await save_course_cover(COURSES_DIR, course_id, data.cover_image)
    if cover_rel is not None:
        await db_exec("UPDATE courses SET cover_image = ? WHERE id = ?", (cover_rel, course_id))
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await audit(action=Action.CREATE_COURSE, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=data.title)
    return _course_to_response(row)


@router.get("/api/teacher/courses",
            summary="List own courses", tags=["Teacher Courses"],
            description="Lists all non-archived courses, ordered by last update. Admins see all courses; teachers see their own.",
            response_model=list,
            responses={200: {"description": "List of courses"}})
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
            description="Returns full course detail including resources, topics, and similar courses.",
            response_model=dict,
            responses={200: {"description": "Course detail"}, 404: {"description": "Course not found"}})
async def get_course_detail(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Return full course detail including resources, topics, and similar courses.

    Raises:
        HTTPException: 404 if the course does not exist.
    """
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")  # i18n: user-facing error message
    await _ensure_course_exists(course_id)
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
            summary="Update course metadata",
            tags=["Teacher Courses"],
            description="Updates course metadata (title, description, subject, grade, language, cover_image). An optional `status` of 'draft' or 'published' also moves the course out of / into the published state; publishing an empty course is rejected with 400.",
            response_model=dict,
            responses={200: {"description": "Updated course"}, 404: {"description": "Course not found"}})
async def update_course(course_id: str, data: CourseCreate, teacher_user: str = Depends(verify_teacher)):
    """Update course metadata (title, description, subject, grade, language).

    An explicit `status` of 'draft' or 'published' also moves the course
    between draft (0) and published (1); any other value leaves the current
    publish state untouched.

    Verifies ownership before updating. Logs the change to the audit log.
    """
    await _ensure_course_exists(course_id)
    if data.status == "published":
        await _require_course_resources(course_id)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        """UPDATE courses SET title = ?, description = ?, subject = ?, grade = ?, language = ?, updated_at = ?
           WHERE id = ?""",
        (data.title, data.description, data.subject, data.grade, data.language, now, course_id)
    )
    cover_rel = await save_course_cover(COURSES_DIR, course_id, data.cover_image)
    if cover_rel is not None:
        await db_exec("UPDATE courses SET cover_image = ? WHERE id = ?", (cover_rel, course_id))
        await bump_course_version(course_id)
    if data.status in ("draft", "published"):
        new_val = 0 if data.status == "draft" else 1
        await db_exec(
            "UPDATE courses SET published = ?, updated_at = datetime('now') WHERE id = ?",
            (new_val, course_id)
        )
        action = Action.UNPUBLISH_COURSE if new_val == 0 else Action.PUBLISH_COURSE
        await audit(action=action, username=teacher_user, resource_type="course",
                    resource_id=course_id, resource_name=data.title,
                    context={"published": new_val})
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await audit(action=Action.UPDATE_COURSE, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=data.title)
    return _course_to_response(row)


@router.delete("/api/teacher/courses/{course_id}",
               summary="Soft-delete a course", tags=["Teacher Courses"],
               description="Archives a course by setting published = -1. Resources remain on disk.",
               response_model=dict,
               responses={200: {"description": "Course archived"}, 404: {"description": "Course not found"}})
async def delete_course(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Soft-delete a course by setting published = -1.

    The course is archived, not removed from the database. Resources remain
    on disk. Logs the action to the audit log.
    """
    row = await _ensure_course_exists(course_id)
    await db_exec("UPDATE courses SET published = -1, updated_at = datetime('now') WHERE id = ?", (course_id,))
    await audit(action=Action.DELETE_COURSE, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=row['title'])
    return {"status": "ok", "message": f"Course '{row['title']}' archived."}  # i18n: user-facing success message


# ─── Publishing ───────────────────────────────────────────────────────────

@router.post("/api/teacher/courses/{course_id}/publish",
             summary="Toggle course published status", tags=["Teacher Courses"],
             description="Toggles a course between published (1) and unpublished (0).",
             response_model=dict,
             responses={200: {"description": "Updated course"}, 404: {"description": "Course not found"}})
async def toggle_publish(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """Toggle a course between published (1) and unpublished (0).

    Verifies ownership, flips the published flag, and logs the action.
    """
    row = await _ensure_course_exists(course_id)
    new_val = 0 if row["published"] == 1 else 1
    if new_val == 1:
        await _require_course_resources(course_id)
    await db_exec("UPDATE courses SET published = ?, updated_at = datetime('now') WHERE id = ?", (new_val, course_id))
    action = Action.PUBLISH_COURSE if new_val == 1 else Action.UNPUBLISH_COURSE
    await audit(action=action, username=teacher_user, resource_type="course",
                resource_id=course_id, resource_name=row['title'], context={"published": new_val})
    updated = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    return _course_to_response(updated)
