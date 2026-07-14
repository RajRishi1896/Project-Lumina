"""Subject, grade, and resource topic management routes."""
import os
import sqlite3
import logging
import asyncio
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from app.async_db import db_conn, db_exec, db_fetch
from app.database import UPLOAD_DIR, gen_uid
from app.dependencies import verify_teacher
from app.models import SubjectCreate, SubjectResponse, SubjectCreateResponse, StatusResponse, GradeInfo

router = APIRouter()


@router.get("/subjects", response_model=list[SubjectResponse],
            summary="List all subjects",
            description="Returns all subjects with id, name, symbol, and class_name.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def get_subjects(teacher_user: str = Depends(verify_teacher)):
    """List all subjects ordered by class and name.

    Returns:
        List of dicts with id, name, symbol, and class_name.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT id, name, symbol, class_name FROM subjects ORDER BY class_name ASC, name ASC")
            rows = c.fetchall()
            return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": r[3] or "All Classes"} for r in rows]
        except sqlite3.OperationalError:
            c.execute("SELECT id, name, symbol FROM subjects ORDER BY name ASC")
            rows = c.fetchall()
            return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": "All Classes"} for r in rows]


@router.post("/teacher/subjects", response_model=SubjectCreateResponse,
             summary="Create a subject",
             description="Creates a new subject with name, symbol, and optional class_name.",
             tags=["Subjects"],
             responses={400: {"description": "Failed to create subject"}, 401: {"description": "Unauthorized"}})
async def create_subject(subject: SubjectCreate, teacher_user: str = Depends(verify_teacher)):
    """Create a new subject.

    Args:
        subject: Subject creation payload.

    Returns:
        Dict with status, id, name, symbol, and class_name.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            class_val = subject.class_name or "All Classes"
            subj_id = gen_uid("SUBJ")
            c.execute("INSERT INTO subjects (id, name, symbol, class_name) VALUES (?, ?, ?, ?)",
                      (subj_id, subject.name, subject.symbol, class_val))
            conn.commit()
            return {"status": "success", "id": subj_id, "name": subject.name, "symbol": subject.symbol, "class_name": class_val}
        except Exception as e:
            logging.error(f"create_subject: {e}")
            raise HTTPException(status_code=400, detail="Failed to create subject")


@router.put("/teacher/subjects/{subject_id}",
            summary="Edit a subject", tags=["Subjects"])
async def update_subject(subject_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    allowed = {"name", "symbol", "class_name"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT id, name FROM subjects WHERE id = ?", (subject_id,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Subject not found.")
        old_name = row[1]
        if "name" in fields:
            c.execute("SELECT id FROM subjects WHERE name = ? AND id != ?", (fields["name"], subject_id))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="A subject with that name already exists.")
        set_parts = []
        params = []
        if "name" in fields:
            set_parts.append("name = ?")
            params.append(fields["name"])
        if "symbol" in fields:
            set_parts.append("symbol = ?")
            params.append(fields["symbol"])
        if "class_name" in fields:
            set_parts.append("class_name = ?")
            params.append(fields["class_name"])
        if set_parts:
            params.append(subject_id)
            c.execute(f"UPDATE subjects SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
        if "name" in fields and fields["name"] != old_name:
            c.execute("UPDATE resources SET subject = ? WHERE subject = ?", (fields["name"], old_name))
            c.execute("UPDATE resource_topics SET subject = ? WHERE subject = ?", (fields["name"], old_name))
        conn.commit()
    return {"status": "ok"}


@router.delete("/teacher/subjects/{subject_id}", response_model=StatusResponse,
               summary="Delete a subject",
               description="Deletes a subject by id, optionally transferring resources to another subject.",
               tags=["Subjects"],
               responses={400: {"description": "Invalid request or target subject missing"}, 401: {"description": "Unauthorized"}, 404: {"description": "Subject not found"}})
async def delete_subject(subject_id: str, transfer_to: str = Query(None), teacher_user: str = Depends(verify_teacher)):
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT name FROM subjects WHERE id = ?", (subject_id,))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Subject not found.")
            subject_name = row[0]

            if transfer_to:
                c.execute("SELECT COUNT(*) FROM subjects WHERE name = ?", (transfer_to,))
                if c.fetchone()[0] == 0:
                    raise HTTPException(status_code=400, detail="Target subject does not exist.")
                c.execute("UPDATE resources SET subject = ? WHERE subject = ?", (transfer_to, subject_name))
            else:
                c.execute("SELECT filename FROM resources WHERE subject = ?", (subject_name,))
                files = [r[0] for r in c.fetchall()]
                for fname in files:
                    fp = os.path.join(UPLOAD_DIR, fname) if fname else None
                    if fp and await asyncio.to_thread(os.path.exists, fp):
                        try:
                            await asyncio.to_thread(os.remove, fp)
                        except Exception as e:
                            logging.warning(f"Could not remove physical file {fp}: {e}")
                c.execute("DELETE FROM resources WHERE subject = ?", (subject_name,))

            c.execute("DELETE FROM subjects WHERE id = ?", (subject_id,))
            conn.commit()
            return {"status": "success"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"delete_subject: {e}", exc_info=True)
            raise HTTPException(status_code=400, detail=f"Failed to delete subject: {e}")


@router.get("/grades", response_model=list[GradeInfo],
            summary="List all grades",
            description="Returns all grade levels ordered by name.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def get_grades(teacher_user: str = Depends(verify_teacher)):
    """List all grade levels.

    Returns:
        List of dicts with name for each grade.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT id, name FROM grades ORDER BY name ASC")
        rows = c.fetchall()
    return [{"id": r[0], "name": r[1]} for r in rows]


@router.post("/grades",
             summary="Create a grade",
             description="Creates a new grade level with a unique name (max 50 characters).",
             tags=["Subjects"],
             responses={400: {"description": "Missing name, too long, or duplicate"}, 401: {"description": "Unauthorized"}})
async def create_grade(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Create a new grade level.

    Args:
        data: Dict with a name field.

    Returns:
        Dict with status and the created name.
    Raises:
        HTTPException 400: If name is missing, too long, or already exists.
    """
    name = data.get("name", "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Grade name is required.")
    if len(name) > 50:
        raise HTTPException(status_code=400, detail="Grade name too long (max 50 characters).")
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("INSERT INTO grades (id, name) VALUES (?, ?)", (gen_uid("GRD"), name))
            conn.commit()
            return {"status": "success", "name": name}
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="Grade already exists.")


@router.put("/grades/{grade_name}",
            summary="Rename a grade", tags=["Subjects"])
async def update_grade(grade_name: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    new_name = (data.get("new_name") or "").strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="new_name is required.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM grades WHERE name = ?", (grade_name,))
        if not c.fetchone():
            raise HTTPException(status_code=404, detail="Grade not found.")
        c.execute("SELECT id FROM grades WHERE name = ? AND name != ?", (new_name, grade_name))
        if c.fetchone():
            raise HTTPException(status_code=400, detail="A grade with that name already exists.")
        c.execute("UPDATE grades SET name = ? WHERE name = ?", (new_name, grade_name))
        c.execute("UPDATE resources SET grade = ? WHERE grade = ?", (new_name, grade_name))
        conn.commit()
    return {"status": "ok"}


@router.delete("/grades/{name}", response_model=StatusResponse,
               summary="Delete a grade",
               description="Deletes a grade level, optionally transferring resources to another grade first.",
               tags=["Subjects"],
               responses={400: {"description": "Target grade not found"}, 401: {"description": "Unauthorized"}})
async def delete_grade(name: str, transfer_to: str = None, teacher_user: str = Depends(verify_teacher)):
    """Delete a grade level.

    Args:
        name: The grade name to delete.
        transfer_to: Optional grade to transfer resources to before deletion.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If target grade does not exist.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        if transfer_to:
            c.execute("SELECT COUNT(*) FROM grades WHERE name = ?", (transfer_to,))
            if c.fetchone()[0] == 0:
                raise HTTPException(status_code=400, detail="Target grade does not exist.")
            c.execute("UPDATE resources SET grade = ? WHERE grade = ?", (transfer_to, name))
        else:
            c.execute("SELECT filename FROM resources WHERE grade = ?", (name,))
            files = c.fetchall()
            for (fname,) in files:
                fp = os.path.join(UPLOAD_DIR, fname) if fname else None
                if fp and await asyncio.to_thread(os.path.exists, fp):
                    await asyncio.to_thread(os.remove, fp)
            c.execute("DELETE FROM resources WHERE grade = ?", (name,))
        c.execute("DELETE FROM grades WHERE name = ?", (name,))
        conn.commit()
    return {"status": "success"}


# ─── Resource Topics (chapters within subjects) ────────────────────────────

@router.get("/teacher/resource-topics",
            summary="List resource topics",
            description="Returns resource topics. Omit subject to list all.",
            tags=["Subjects"])
async def list_resource_topics(subject: str = Query(None, description="Subject name (omit for all)"),
                               teacher_user: str = Depends(verify_teacher)):
    if subject:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics WHERE subject = ? ORDER BY position ASC",
            (subject,))
    else:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics ORDER BY subject ASC, position ASC")
    return [dict(r) for r in rows]


@router.post("/teacher/resource-topics",
             summary="Create a resource topic (chapter)",
             tags=["Subjects"],
             responses={201: {"description": "Topic created"}, 400: {"description": "Topic already exists"}})
async def create_resource_topic(data: dict, teacher_user: str = Depends(verify_teacher)):
    subject = (data.get("subject") or "").strip()
    name = (data.get("name") or "").strip()
    if not subject or not name:
        raise HTTPException(status_code=400, detail="Subject and name are required.")
    last = await db_fetch(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM resource_topics WHERE subject = ?",
        (subject,))
    mp = last[0]["mp"] if last and last[0]["mp"] is not None else -1
    topic_id = gen_uid("RTOP")
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    try:
        await db_exec(
            "INSERT INTO resource_topics (id, subject, name, position) VALUES (?, ?, ?, ?)",
            (topic_id, subject, name, mp + 1))
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail=f"Topic '{name}' already exists for subject '{subject}'.")
    return {"status": "ok", "id": topic_id, "subject": subject, "name": name}


@router.put("/teacher/resource-topics/{topic_id}",
            summary="Edit a resource topic", tags=["Subjects"])
async def update_resource_topic(topic_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    allowed = {"name", "subject"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")
    row = await db_fetch("SELECT id, subject, name FROM resource_topics WHERE id = ?", (topic_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")
    old = row[0]
    new_subject = fields.get("subject", old["subject"])
    new_name = fields.get("name", old["name"])
    if "name" in fields or "subject" in fields:
        dup = await db_fetch(
            "SELECT id FROM resource_topics WHERE subject = ? AND name = ? AND id != ?",
            (new_subject, new_name, topic_id))
        if dup:
            raise HTTPException(status_code=400, detail=f"Topic '{new_name}' already exists for subject '{new_subject}'.")
    set_parts = []
    params = []
    if "name" in fields:
        set_parts.append("name = ?")
        params.append(fields["name"])
    if "subject" in fields:
        set_parts.append("subject = ?")
        params.append(fields["subject"])
    params.append(topic_id)
    await db_exec(f"UPDATE resource_topics SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
    return {"status": "ok"}


@router.delete("/teacher/resource-topics/{topic_id}",
               summary="Delete a resource topic",
               tags=["Subjects"],
               responses={200: {"description": "Deleted"}, 404: {"description": "Not found"}})
async def delete_resource_topic(topic_id: str,
                                delete_resources: bool = Query(False, description="Also hard-delete all resources in this topic"),
                                teacher_user: str = Depends(verify_teacher)):
    row = await db_fetch("SELECT id FROM resource_topics WHERE id = ?", (topic_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")
    if delete_resources:
        resources = await db_fetch("SELECT id, filename FROM resources WHERE topic_id = ?", (topic_id,))
        for r in resources:
            if r["filename"]:
                fpath = os.path.join(UPLOAD_DIR, r["filename"])
                try:
                    if await asyncio.to_thread(os.path.exists, fpath):
                        await asyncio.to_thread(os.remove, fpath)
                except Exception as e:
                    logging.warning(f"Could not remove file {fpath}: {e}")
            await db_exec("DELETE FROM scholar_downloads WHERE resource_id = ?", (r["id"],))
            await db_exec("DELETE FROM resources WHERE id = ?", (r["id"],))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        return {"status": "ok", "message": f"Topic and {len(resources)} resource(s) deleted."}
    else:
        await db_exec("UPDATE resources SET topic_id = '' WHERE topic_id = ?", (topic_id,))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        return {"status": "ok", "message": "Topic deleted. Resources moved to General."}
