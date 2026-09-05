"""Teacher topic (chapter) management for courses."""
from datetime import datetime, timezone
from typing import Optional
import asyncio
import os
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from app.database import gen_uid
from app.async_db import db_exec, db_exec_many, db_fetch, db_fetch_one
from app.dependencies import verify_teacher
from app.routers.teacher_courses import _ensure_course_exists
from app.audit import audit, Action

router = APIRouter()


@router.post("/api/teacher/courses/{course_id}/topics",
             summary="Create a topic (chapter)", tags=["Teacher Courses"],
             description="Creates a new topic within a course and assigns the next position index.",
             response_model=dict,
             responses={201: {"description": "Topic created"}, 400: {"description": "Title required"}, 404: {"description": "Course not found"}})
async def create_topic(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Create a new topic (chapter) within a course.

    Assigns the next position index. Title is required.

    Raises:
        HTTPException: 400 if title is empty.
    """
    await _ensure_course_exists(course_id)
    title = (data.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Topic title is required.")  # i18n: user-facing error message
    last = await db_fetch_one(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM topics WHERE course_id = ?", (course_id,))
    next_pos = (last["mp"] if last and last["mp"] is not None else -1) + 1
    topic_id = gen_uid("TPC")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    await db_exec(
        "INSERT INTO topics (id, course_id, title, description, position, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (topic_id, course_id, title, data.get("description", ""), next_pos, now))
    await audit(action=Action.CREATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_id=topic_id, resource_name=title, context={"course_id": course_id})
    row = await db_fetch_one("SELECT * FROM topics WHERE id = ?", (topic_id,))
    return dict(row)


@router.get("/api/teacher/courses/{course_id}/topics",
            summary="List topics in a course", tags=["Teacher Courses"],
            description="Lists all topics for a course ordered by position.",
            response_model=list,
            responses={200: {"description": "List of topics"}, 404: {"description": "Course not found"}})
async def list_topics(course_id: str, teacher_user: str = Depends(verify_teacher)):
    """List all topics for a course, ordered by position."""
    await _ensure_course_exists(course_id)
    rows = await db_fetch(
        "SELECT * FROM topics WHERE course_id = ? ORDER BY position ASC", (course_id,))
    return [dict(r) for r in rows]


@router.put("/api/teacher/courses/{course_id}/topics/{topic_id}",
            summary="Update a topic", tags=["Teacher Courses"],
            description="Updates a topic's title and description.",
            response_model=dict,
            responses={200: {"description": "Topic updated"}, 400: {"description": "Title required"}, 404: {"description": "Topic or course not found"}})
async def update_topic(course_id: str, topic_id: str, data: dict, teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Update a topic's title and description.

    Raises:
        HTTPException: 400 if title empty, 404 if topic not found.
    """
    await _ensure_course_exists(course_id)
    row = await db_fetch_one("SELECT id FROM topics WHERE id = ? AND course_id = ?", (topic_id, course_id))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    title = (data.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Topic title is required.")  # i18n: user-facing error message
    await db_exec("UPDATE topics SET title = ?, description = ? WHERE id = ?",
                  (title, data.get("description", ""), topic_id))
    await audit(action=Action.UPDATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_id=topic_id, resource_name=title, context={"course_id": course_id})
    updated = await db_fetch_one("SELECT * FROM topics WHERE id = ?", (topic_id,))
    return dict(updated)


@router.delete("/api/teacher/courses/{course_id}/topics/{topic_id}",
               summary="Delete a topic", tags=["Teacher Courses"],
               description="Deletes a topic, optionally transferring or hard-deleting its resources.",
               response_model=dict,
               responses={200: {"description": "Topic deleted"}, 404: {"description": "Topic or transfer target not found"}})
async def delete_topic(course_id: str, topic_id: str,  # noqa: PLR0913
                       transfer_to: Optional[str] = Query(None, description="Transfer resources to this topic before deleting"),
                       delete_resources: bool = Query(False, description="Delete all resources in this topic"),
                       teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Delete a topic and optionally transfer or delete its resources.

    If ``transfer_to`` is set, resources are moved to that topic.
    If ``delete_resources`` is true, resources are hard-deleted.
    Otherwise resources are ungrouped (topic_id cleared).

    Raises:
        HTTPException: 404 if topic or transfer target not found.
    """
    await _ensure_course_exists(course_id)
    row = await db_fetch_one("SELECT id FROM topics WHERE id = ? AND course_id = ?", (topic_id, course_id))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    if transfer_to:
        target = await db_fetch_one("SELECT id, title FROM topics WHERE id = ? AND course_id = ?", (transfer_to, course_id))
        if not target:
            raise HTTPException(status_code=404, detail="Transfer target topic not found.")  # i18n: user-facing error message
        await db_exec("UPDATE course_resources SET topic_id = ? WHERE topic_id = ?", (transfer_to, topic_id))
        await db_exec("DELETE FROM topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"course_id": course_id, "transferred_to": target["title"]})
        return {"status": "ok", "message": f"Topic deleted. Resources transferred to '{target['title']}'.",
                "transferred_to": target["title"]}  # i18n: user-facing success message
    elif delete_resources:
        resources = await db_fetch("SELECT id, filename FROM course_resources WHERE topic_id = ?", (topic_id,))
        upload_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")

        def _remove_files():
            for r in resources:
                fpath = os.path.join(upload_dir, r["filename"])
                if r.get("filename") and os.path.exists(fpath):
                    try:
                        os.remove(fpath)
                    except OSError:
                        pass

        await asyncio.to_thread(_remove_files)
        count = len(resources)
        await db_exec("DELETE FROM course_resources WHERE topic_id = ?", (topic_id,))
        await db_exec("DELETE FROM topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"course_id": course_id, "deleted_resources": count})
        return {"status": "ok", "message": f"Topic and {count} resources deleted."}  # i18n: user-facing success message
    else:
        await db_exec("UPDATE course_resources SET topic_id = '' WHERE topic_id = ?", (topic_id,))
        await db_exec("DELETE FROM topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"course_id": course_id})
        return {"status": "ok", "message": "Topic deleted. Resources moved to ungrouped."}  # i18n: user-facing success message


@router.post("/api/teacher/courses/{course_id}/topics/reorder",
             summary="Reorder topics", tags=["Teacher Courses"],
             description="Reorders topics within a course. Body expects a `topic_ids` list in the desired order.",
             response_model=dict,
             responses={200: {"description": "Topics reordered"}, 400: {"description": "topic_ids list required"}, 404: {"description": "Course not found"}})
async def reorder_topics(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Reorder topics within a course.

    Expects ``topic_ids`` as a list of topic IDs in the desired order.
    Sets each topic's position to its index in the list.
    """
    await _ensure_course_exists(course_id)
    topic_ids = data.get("topic_ids", [])
    if not topic_ids:
        raise HTTPException(status_code=400, detail="topic_ids list is required.")  # i18n: user-facing error message
    await db_exec_many(
        "UPDATE topics SET position = ? WHERE id = ? AND course_id = ?",
        [(i, tid, course_id) for i, tid in enumerate(topic_ids)])
    await audit(action=Action.UPDATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_name="reorder", context={"course_id": course_id, "count": len(topic_ids)})
    return {"status": "ok", "message": f"Reordered {len(topic_ids)} topics."}  # i18n: user-facing success message


@router.put("/api/teacher/courses/{course_id}/resources/{resource_id}/topic",
            summary="Assign a resource to a topic", tags=["Teacher Courses"],
            description="Assigns a course resource to a topic, or unassigns it with an empty `topic_id`.",
            response_model=dict,
            responses={200: {"description": "Resource assigned"}, 404: {"description": "Resource or topic not found"}})
async def assign_resource_topic(course_id: str, resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Assign a course resource to a topic (or unassign with empty topic_id).

    Validates both the resource and topic belong to the course.

    Raises:
        HTTPException: 404 if resource or topic not found in this course.
    """
    await _ensure_course_exists(course_id)
    res = await db_fetch_one(
        "SELECT id FROM course_resources WHERE id = ? AND course_id = ?", (resource_id, course_id))
    if not res:
        raise HTTPException(status_code=404, detail="Resource not found.")  # i18n: user-facing error message
    topic_id = data.get("topic_id", "")
    if topic_id:
        tpc = await db_fetch_one("SELECT id FROM topics WHERE id = ? AND course_id = ?", (topic_id, course_id))
        if not tpc:
            raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    await db_exec("UPDATE course_resources SET topic_id = ? WHERE id = ?", (topic_id, resource_id))
    return {"status": "ok", "message": "Resource assigned to topic."}  # i18n: user-facing success message


@router.post("/api/teacher/courses/{course_id}/topics/reorder-resources",
             summary="Reorder resources within a topic", tags=["Teacher Courses"],
             description="Reorders resources within a course. Body expects a `resource_ids` list in the desired order.",
             response_model=dict,
             responses={200: {"description": "Resources reordered"}, 400: {"description": "resource_ids list required"}, 404: {"description": "Course not found"}})
async def reorder_topic_resources(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher), request: Request = None):
    """Reorder resources within a course (across all topics).

    Expects ``resource_ids`` as a list in the desired order. Sets each
    resource's position to its index in the list.
    """
    await _ensure_course_exists(course_id)
    resource_ids = data.get("resource_ids", [])
    if not resource_ids:
        raise HTTPException(status_code=400, detail="resource_ids list is required.")  # i18n: user-facing error message
    await db_exec_many(
        "UPDATE course_resources SET position = ? WHERE id = ? AND course_id = ?",
        [(i, rid, course_id) for i, rid in enumerate(resource_ids)])
    await audit(action=Action.UPDATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_name="reorder-resources", context={"course_id": course_id, "count": len(resource_ids)})
    return {"status": "ok", "message": f"Reordered {len(resource_ids)} resources."}  # i18n: user-facing success message
