"""Teacher topic (chapter) management for courses."""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from app.database import log_admin_action, gen_uid
from app.async_db import db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.routers.teacher_courses import _ensure_course_owner

router = APIRouter()


@router.post("/api/teacher/courses/{course_id}/topics",
             summary="Create a topic (chapter)", tags=["Teacher Courses"],
             responses={201: {"description": "Topic created"}})
async def create_topic(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    title = (data.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Topic title is required.")
    last = await db_fetch_one(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM topics WHERE course_id = ?", (course_id,))
    next_pos = (last["mp"] if last and last["mp"] is not None else -1) + 1
    topic_id = gen_uid("TPC")
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        "INSERT INTO topics (id, course_id, title, description, position, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (topic_id, course_id, title, data.get("description", ""), next_pos, now))
    row = await db_fetch_one("SELECT * FROM topics WHERE id = ?", (topic_id,))
    return dict(row)


@router.get("/api/teacher/courses/{course_id}/topics",
            summary="List topics in a course", tags=["Teacher Courses"])
async def list_topics(course_id: str, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    rows = await db_fetch(
        "SELECT * FROM topics WHERE course_id = ? ORDER BY position ASC", (course_id,))
    return [dict(r) for r in rows]


@router.put("/api/teacher/courses/{course_id}/topics/{topic_id}",
            summary="Update a topic", tags=["Teacher Courses"])
async def update_topic(course_id: str, topic_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    row = await db_fetch_one("SELECT id FROM topics WHERE id = ? AND course_id = ?", (topic_id, course_id))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")
    title = (data.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Topic title is required.")
    await db_exec("UPDATE topics SET title = ?, description = ? WHERE id = ?",
                  (title, data.get("description", ""), topic_id))
    updated = await db_fetch_one("SELECT * FROM topics WHERE id = ?", (topic_id,))
    return dict(updated)


@router.delete("/api/teacher/courses/{course_id}/topics/{topic_id}",
               summary="Delete a topic", tags=["Teacher Courses"])
async def delete_topic(course_id: str, topic_id: str, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    row = await db_fetch_one("SELECT id FROM topics WHERE id = ? AND course_id = ?", (topic_id, course_id))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")
    await db_exec("UPDATE course_resources SET topic_id = '' WHERE topic_id = ?", (topic_id,))
    await db_exec("DELETE FROM topics WHERE id = ?", (topic_id,))
    return {"status": "ok", "message": "Topic deleted. Resources moved to ungrouped."}


@router.post("/api/teacher/courses/{course_id}/topics/reorder",
             summary="Reorder topics", tags=["Teacher Courses"])
async def reorder_topics(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    topic_ids = data.get("topic_ids", [])
    if not topic_ids:
        raise HTTPException(status_code=400, detail="topic_ids list is required.")
    for i, tid in enumerate(topic_ids):
        await db_exec("UPDATE topics SET position = ? WHERE id = ? AND course_id = ?", (i, tid, course_id))
    return {"status": "ok", "message": f"Reordered {len(topic_ids)} topics."}


@router.put("/api/teacher/courses/{course_id}/resources/{resource_id}/topic",
            summary="Assign a resource to a topic", tags=["Teacher Courses"])
async def assign_resource_topic(course_id: str, resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    res = await db_fetch_one(
        "SELECT id FROM course_resources WHERE id = ? AND course_id = ?", (resource_id, course_id))
    if not res:
        raise HTTPException(status_code=404, detail="Resource not found.")
    topic_id = data.get("topic_id", "")
    if topic_id:
        tpc = await db_fetch_one("SELECT id FROM topics WHERE id = ? AND course_id = ?", (topic_id, course_id))
        if not tpc:
            raise HTTPException(status_code=404, detail="Topic not found.")
    await db_exec("UPDATE course_resources SET topic_id = ? WHERE id = ?", (topic_id, resource_id))
    return {"status": "ok", "message": "Resource assigned to topic."}


@router.post("/api/teacher/courses/{course_id}/topics/reorder-resources",
             summary="Reorder resources within a topic", tags=["Teacher Courses"])
async def reorder_topic_resources(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    await _ensure_course_owner(course_id, teacher_user)
    resource_ids = data.get("resource_ids", [])
    if not resource_ids:
        raise HTTPException(status_code=400, detail="resource_ids list is required.")
    for i, rid in enumerate(resource_ids):
        await db_exec("UPDATE course_resources SET position = ? WHERE id = ? AND course_id = ?", (i, rid, course_id))
    return {"status": "ok", "message": f"Reordered {len(resource_ids)} resources."}
