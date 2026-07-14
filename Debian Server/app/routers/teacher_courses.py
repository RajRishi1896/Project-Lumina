"""Teacher course management — CRUD, publishing, and shared helpers."""
import os
import asyncio
import uuid
import logging
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from app.database import UPLOAD_DIR, log_admin_action, gen_composite_uid
from app.async_db import db_conn, db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.models import CourseCreate

router = APIRouter()
COURSES_DIR = os.path.abspath(os.path.join(UPLOAD_DIR, "..", "courses"))
os.makedirs(COURSES_DIR, exist_ok=True)


def _course_to_response(row) -> dict:
    return {
        "id": row["id"], "title": row["title"], "description": row["description"],
        "subject": row["subject"], "grade": row["grade"], "language": row["language"],
        "cover_image": row["cover_image"], "published": row["published"],
        "teacher_username": row["teacher_username"], "enrollment_count": row["enrollment_count"],
        "resource_count": row["resource_count"] if "resource_count" in row.keys() else 0,
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
        user = await db_fetch_one("SELECT role FROM users WHERE username = ?", (teacher_user,))
        if not user or user["role"] != "admin":
            raise HTTPException(status_code=404, detail="Course not found.")
    return row


async def _write_chunked(dest_path: str, file: UploadFile, max_size: int) -> int:
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


# ─── Static-path routes ──────────────────────────────────────────────────

@router.get("/api/teacher/courses/suggest-similar",
            summary="Search published courses across all teachers",
            tags=["Teacher Courses"])
async def suggest_similar_courses(q: str = Query("", description="Search query for course title")):
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
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    async with db_conn() as conn:
        course_id = gen_composite_uid(conn, data.grade, data.subject, 'CRS')
        conn.execute(
            """INSERT INTO courses (id, title, description, subject, grade, language, teacher_username, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (course_id, data.title, data.description, data.subject, data.grade, data.language, teacher_user, now, now)
        )
        conn.commit()
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    await log_admin_action(teacher_user, f"Created course '{data.title}' (id={course_id})")
    return _course_to_response(row)


@router.get("/api/teacher/courses",
            summary="List own courses", tags=["Teacher Courses"])
async def list_courses(teacher_user: str = Depends(verify_teacher)):
    rows = await db_fetch(
        "SELECT c.*, (SELECT COUNT(*) FROM course_resources WHERE course_id = c.id) AS resource_count FROM courses c WHERE c.published != -1 ORDER BY c.updated_at DESC"
    )
    return [_course_to_response(r) for r in rows]


@router.get("/api/teacher/courses/{course_id}",
            summary="Get course detail", tags=["Teacher Courses"],
            responses={200: {"description": "Course detail"}, 404: {"description": "Course not found"}})
async def get_course_detail(course_id: str, teacher_user: str = Depends(verify_teacher)):
    row = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")
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
               summary="Soft-delete a course", tags=["Teacher Courses"])
async def delete_course(course_id: str, teacher_user: str = Depends(verify_teacher)):
    row = await _ensure_course_owner(course_id, teacher_user)
    await db_exec("UPDATE courses SET published = -1, updated_at = datetime('now') WHERE id = ?", (course_id,))
    await log_admin_action(teacher_user, f"Archived course '{row['title']}' (id={course_id})")
    return {"status": "ok", "message": f"Course '{row['title']}' archived."}


# ─── Publishing ───────────────────────────────────────────────────────────

@router.post("/api/teacher/courses/{course_id}/publish",
             summary="Toggle course published status", tags=["Teacher Courses"])
async def toggle_publish(course_id: str, teacher_user: str = Depends(verify_teacher)):
    row = await _ensure_course_owner(course_id, teacher_user)
    new_val = 0 if row["published"] == 1 else 1
    await db_exec("UPDATE courses SET published = ?, updated_at = datetime('now') WHERE id = ?", (new_val, course_id))
    action = "Published" if new_val == 1 else "Unpublished"
    await log_admin_action(teacher_user, f"{action} course '{row['title']}' (id={course_id})")
    updated = await db_fetch_one("SELECT * FROM courses WHERE id = ?", (course_id,))
    return _course_to_response(updated)
