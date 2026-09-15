"""Resource topic (chapter) management routes."""
import os
import sqlite3
import logging
import asyncio
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from app.async_db import db_exec, db_fetch
from app.database import UPLOAD_DIR, gen_uid
from app.dependencies import verify_teacher
from app.models import StatusResponse
from app.audit import audit, Action
from datetime import datetime, timezone

router = APIRouter()


@router.get("/teacher/resource-topics", response_model=list[dict],
            summary="List resource topics",
            description="Returns resource topics (id, subject, name, position). Omit subject to list all.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def list_resource_topics(subject: str = Query(None, description="Subject name (omit for all)"),
                               teacher_user: str = Depends(verify_teacher)):
    """List resource topics, optionally filtered by subject.

    Returns topics ordered by position within each subject.
    """
    if subject:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics WHERE subject = ? ORDER BY position ASC",
            (subject,))
    else:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics ORDER BY subject ASC, position ASC")
    return [dict(r) for r in rows]


@router.post("/teacher/resource-topics", response_model=dict,
             summary="Create a resource topic (chapter)",
             description="Creates a new resource topic within a subject, assigning the next position automatically.",
             tags=["Subjects"],
             responses={201: {"description": "Topic created"}, 400: {"description": "Missing fields or topic already exists"}})
async def create_resource_topic(data: dict, teacher_user: str = Depends(verify_teacher),
                                request: Request = None):
    """Create a new resource topic (chapter) within a subject.

    Assigns the next position index automatically. Enforces unique
    (subject, name) constraint.

    Raises:
        HTTPException: 400 if missing fields or duplicate.
    """
    subject = (data.get("subject") or "").strip()
    name = (data.get("name") or "").strip()
    if not subject or not name:
        raise HTTPException(status_code=400, detail="Subject and name are required.")  # i18n: user-facing error message
    last = await db_fetch(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM resource_topics WHERE subject = ?",
        (subject,))
    mp = last[0]["mp"] if last and last[0]["mp"] is not None else -1
    topic_id = gen_uid("RTOP")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    try:
        await db_exec(
            "INSERT INTO resource_topics (id, subject, name, position) VALUES (?, ?, ?, ?)",
            (topic_id, subject, name, mp + 1))
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail=f"Topic '{name}' already exists for subject '{subject}'.")  # i18n: user-facing error message
    await audit(action=Action.CREATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_id=topic_id, resource_name=name, context={"subject": subject})
    return {"status": "ok", "id": topic_id, "subject": subject, "name": name}


@router.put("/teacher/resource-topics/{topic_id}", response_model=StatusResponse,
            summary="Edit a resource topic", tags=["Subjects"],
            description="Updates a resource topic's name or subject, enforcing a unique (subject, name) pair.",
            responses={400: {"description": "No fields given or duplicate name"}, 401: {"description": "Unauthorized"}, 404: {"description": "Topic not found"}})
async def update_resource_topic(topic_id: str, data: dict, teacher_user: str = Depends(verify_teacher),
                                request: Request = None):
    """Update a resource topic's name or subject.

    Checks for duplicate (subject, name) combinations before applying.

    Raises:
        HTTPException: 400 on duplicate, 404 if topic not found.
    """
    allowed = {"name", "subject"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")  # i18n: user-facing error message
    row = await db_fetch("SELECT id, subject, name FROM resource_topics WHERE id = ?", (topic_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    old = row[0]
    new_subject = fields.get("subject", old["subject"])
    new_name = fields.get("name", old["name"])
    if "name" in fields or "subject" in fields:
        dup = await db_fetch(
            "SELECT id FROM resource_topics WHERE subject = ? AND name = ? AND id != ?",
            (new_subject, new_name, topic_id))
        if dup:
            raise HTTPException(status_code=400, detail=f"Topic '{new_name}' already exists for subject '{new_subject}'.")  # i18n: user-facing error message
    set_parts, params = [], []
    if "name" in fields:
        set_parts.append("name = ?")
        params.append(fields["name"])
    if "subject" in fields:
        set_parts.append("subject = ?")
        params.append(fields["subject"])
    if set_parts:
        params.append(topic_id)
        await db_exec(f"UPDATE resource_topics SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
    await audit(action=Action.UPDATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_id=topic_id, resource_name=new_name, changes=fields)
    return {"status": "ok"}


@router.delete("/teacher/resource-topics/{topic_id}", response_model=dict,
               summary="Delete a resource topic",
               description="Deletes a resource topic, optionally transferring or hard-deleting its resources.",
               tags=["Subjects"],
               responses={200: {"description": "Deleted"}, 401: {"description": "Unauthorized"}, 404: {"description": "Topic or transfer target not found"}})
async def delete_resource_topic(topic_id: str,
                                delete_resources: bool = Query(False, description="Also hard-delete all resources in this topic"),
                                transfer_to: Optional[str] = Query(None, description="Transfer resources to this topic before deleting"),
                                teacher_user: str = Depends(verify_teacher),
                                request: Request = None):
    """Delete a resource topic.

    If ``transfer_to`` is set, resources are moved to that topic.
    If ``delete_resources`` is true, all resources are hard-deleted.
    Otherwise resources are moved to the General/unassigned bucket.

    Raises:
        HTTPException: 404 if topic or transfer target not found.
    """
    row = await db_fetch("SELECT id FROM resource_topics WHERE id = ?", (topic_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    if transfer_to:
        target = await db_fetch("SELECT id, name FROM resource_topics WHERE id = ?", (transfer_to,))
        if not target:
            raise HTTPException(status_code=404, detail="Transfer target topic not found.")  # i18n: user-facing error message
        await db_exec("UPDATE resources SET topic_id = ? WHERE topic_id = ?", (transfer_to, topic_id))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"transferred_to": target[0]["name"]})
        return {"status": "ok", "message": f"Topic deleted. Resources transferred to '{target[0]['name']}'.",
                "transferred_to": target[0]["name"]}  # i18n: user-facing success message
    if delete_resources:
        resources = await db_fetch("SELECT id, filename FROM resources WHERE topic_id = ?", (topic_id,))
        if resources:
            filepaths = [os.path.join(UPLOAD_DIR, r["filename"]) for r in resources if r["filename"]]
            if filepaths:
                def _remove_files(paths):
                    """Delete a batch of resource files from disk, tolerating missing files."""
                    for fp in paths:
                        try:
                            if os.path.exists(fp):
                                os.remove(fp)
                        except Exception as e:
                            logging.warning(f"Could not remove file {fp}: {e}")
                await asyncio.to_thread(_remove_files, filepaths)

            # Batch DB deletions instead of N+1
            resource_ids = [r["id"] for r in resources]
            placeholders = ",".join("?" for _ in resource_ids)
            await db_exec(f"DELETE FROM student_bookmarks WHERE resource_id IN ({placeholders})", tuple(resource_ids))
            await db_exec(f"DELETE FROM scholar_downloads WHERE resource_id IN ({placeholders})", tuple(resource_ids))
            await db_exec(f"DELETE FROM resources WHERE id IN ({placeholders})", tuple(resource_ids))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"deleted_resources": len(resources)})
        return {"status": "ok", "message": f"Topic and {len(resources)} resource(s) deleted."}  # i18n: user-facing success message
    else:
        await db_exec("UPDATE resources SET topic_id = '' WHERE topic_id = ?", (topic_id,))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id)
        return {"status": "ok", "message": "Topic deleted. Resources moved to General."}  # i18n: user-facing success message
