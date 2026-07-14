"""Teacher similar-course linking."""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from app.database import log_admin_action
from app.async_db import db_fetch, db_fetch_one, db_exec
from app.dependencies import verify_teacher
from app.models import SimilarLinkCreate

router = APIRouter()


@router.get("/api/teacher/courses/{course_id}/similar",
            summary="List similar course links", tags=["Teacher Courses"])
async def list_similar_courses(course_id: str, teacher_user: str = Depends(verify_teacher)):
    rows = await db_fetch(
        "SELECT * FROM similar_courses WHERE course_id = ? OR similar_course_id = ?",
        (course_id, course_id))
    return [dict(r) for r in rows]


@router.post("/api/teacher/courses/{course_id}/similar",
             summary="Add a similar course link", tags=["Teacher Courses"])
async def add_similar_course(course_id: str, data: SimilarLinkCreate, teacher_user: str = Depends(verify_teacher)):
    c1 = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (course_id,))
    c2 = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (data.similar_course_id,))
    if not c1 or not c2:
        raise HTTPException(status_code=404, detail="One or both courses not found.")
    if course_id == data.similar_course_id:
        raise HTTPException(status_code=400, detail="A course cannot link to itself.")
    dup = await db_fetch_one(
        "SELECT 1 FROM similar_courses WHERE course_id = ? AND similar_course_id = ?",
        (course_id, data.similar_course_id))
    if dup:
        raise HTTPException(status_code=400, detail="Similar link already exists.")
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        "INSERT INTO similar_courses (course_id, similar_course_id, created_by, created_at) VALUES (?, ?, ?, ?)",
        (course_id, data.similar_course_id, teacher_user, now))
    await db_exec(
        "INSERT OR IGNORE INTO similar_courses (course_id, similar_course_id, created_by, created_at) VALUES (?, ?, ?, ?)",
        (data.similar_course_id, course_id, teacher_user, now))
    await log_admin_action(teacher_user, f"Linked similar courses {course_id} <-> {data.similar_course_id}")
    return {"status": "ok", "message": "Similar link created."}


@router.delete("/api/teacher/courses/{course_id}/similar/{similar_id}",
               summary="Remove a similar course link", tags=["Teacher Courses"])
async def remove_similar_course(course_id: str, similar_id: str, teacher_user: str = Depends(verify_teacher)):
    existing = await db_fetch_one(
        "SELECT 1 FROM similar_courses WHERE (course_id = ? AND similar_course_id = ?) OR (course_id = ? AND similar_course_id = ?)",
        (course_id, similar_id, similar_id, course_id))
    if not existing:
        raise HTTPException(status_code=404, detail="Similar link not found.")
    await db_exec(
        "DELETE FROM similar_courses WHERE (course_id = ? AND similar_course_id = ?) OR (course_id = ? AND similar_course_id = ?)",
        (course_id, similar_id, similar_id, course_id))
    await log_admin_action(teacher_user, f"Removed similar link between {course_id} and {similar_id}")
    return {"status": "ok", "message": "Similar link removed."}
