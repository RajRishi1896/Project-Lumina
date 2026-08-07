"""Teacher similar-course linking."""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from app.audit import audit, Action
from app.async_db import db_fetch, db_fetch_one, db_exec
from app.dependencies import verify_teacher
from app.models import SimilarLinkCreate
from app.routers.teacher_courses import _ensure_course_exists

router = APIRouter()


@router.get("/api/teacher/courses/{course_id}/similar",
            summary="List similar course links", tags=["Teacher Courses"])
async def list_similar_courses(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """List all similar-course links involving this course.

    Returns links where this course is either the source or target.
    """
    await _ensure_course_exists(course_id)
    rows = await db_fetch(
        "SELECT * FROM similar_courses WHERE course_id = ? OR similar_course_id = ?",
        (course_id, course_id))
    return [dict(r) for r in rows]


@router.post("/api/teacher/courses/{course_id}/similar",
             summary="Add a similar course link", tags=["Teacher Courses"])
async def add_similar_course(course_id: str, data: SimilarLinkCreate, teacher_user: str = Depends(verify_teacher)):
    """Create a bidirectional similar-course link.

    Validates both courses exist, prevents self-linking and duplicates.
    Creates the link in both directions.

    Raises:
        HTTPException: 400 on self-link or duplicate, 404 if either course missing.
    """
    c1 = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (course_id,))
    c2 = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (data.similar_course_id,))
    if not c1 or not c2:
        raise HTTPException(status_code=404, detail="One or both courses not found.")  # i18n: user-facing error message
    await _ensure_course_exists(course_id)
    await _ensure_course_exists(data.similar_course_id)
    if course_id == data.similar_course_id:
        raise HTTPException(status_code=400, detail="A course cannot link to itself.")  # i18n: user-facing error message
    dup = await db_fetch_one(
        "SELECT 1 FROM similar_courses WHERE course_id = ? AND similar_course_id = ?",
        (course_id, data.similar_course_id))
    if dup:
        raise HTTPException(status_code=400, detail="Similar link already exists.")  # i18n: user-facing error message
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        "INSERT INTO similar_courses (course_id, similar_course_id, created_by, created_at) VALUES (?, ?, ?, ?)",
        (course_id, data.similar_course_id, teacher_user, now))
    await db_exec(
        "INSERT OR IGNORE INTO similar_courses (course_id, similar_course_id, created_by, created_at) VALUES (?, ?, ?, ?)",
        (data.similar_course_id, course_id, teacher_user, now))
    await audit(action=Action.LINK_SIMILAR, username=teacher_user, resource_type="course",
                resource_id=course_id,
                context={"similar_course_id": data.similar_course_id})
    return {"status": "ok", "message": "Similar link created."}  # i18n: user-facing success message


@router.delete("/api/teacher/courses/{course_id}/similar/{similar_id}",
               summary="Remove a similar course link", tags=["Teacher Courses"])
async def remove_similar_course(course_id: str, similar_id: str, teacher_user: str = Depends(verify_teacher)):
    """Remove a bidirectional similar-course link.

    Deletes both directions of the link between the two courses.

    Raises:
        HTTPException: 404 if the link does not exist.
    """
    await _ensure_course_exists(course_id)
    existing = await db_fetch_one(
        "SELECT 1 FROM similar_courses WHERE (course_id = ? AND similar_course_id = ?) OR (course_id = ? AND similar_course_id = ?)",
        (course_id, similar_id, similar_id, course_id))
    if not existing:
        raise HTTPException(status_code=404, detail="Similar link not found.")  # i18n: user-facing error message
    await db_exec(
        "DELETE FROM similar_courses WHERE (course_id = ? AND similar_course_id = ?) OR (course_id = ? AND similar_course_id = ?)",
        (course_id, similar_id, similar_id, course_id))
    await audit(action=Action.UNLINK_SIMILAR, username=teacher_user, resource_type="course",
                resource_id=course_id,
                context={"similar_course_id": similar_id})
    return {"status": "ok", "message": "Similar link removed."}  # i18n: user-facing success message
