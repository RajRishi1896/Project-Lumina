"""Subject and grade management routes."""
import os
import sqlite3
import logging
import uuid
import asyncio
from fastapi import APIRouter, Depends, HTTPException
from app.async_db import db_conn
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
            subj_id = f"SUBJ-{uuid.uuid4().hex[:8]}"
            c.execute("INSERT INTO subjects (id, name, symbol, class_name) VALUES (?, ?, ?, ?)",
                      (subj_id, subject.name, subject.symbol, class_val))
            conn.commit()
            return {"status": "success", "id": subj_id, "name": subject.name, "symbol": subject.symbol, "class_name": class_val}
        except Exception as e:
            logging.error(f"create_subject: {e}")
            raise HTTPException(status_code=400, detail="Failed to create subject")


@router.post("/teacher/subjects/delete", response_model=StatusResponse,
             summary="Delete a subject",
             description="Deletes a subject by id or name, optionally transferring resources to another subject.",
             tags=["Subjects"],
             responses={400: {"description": "Invalid request or target subject missing"}, 401: {"description": "Unauthorized"}, 404: {"description": "Subject not found"}})
async def delete_subject(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Delete a subject and optionally transfer its resources.

    Args:
        data: Delete request with id/name and optional transfer_to.

    Returns:
        Status dict indicating success.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            if data.id:
                c.execute("SELECT name FROM subjects WHERE id = ?", (data.get('id'),))
            else:
                c.execute("SELECT name FROM subjects WHERE name = ?", (data.get('name'),))
            row = c.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Subject not found.")
            subject_name = row[0]

            if data.get('transfer_to'):
                c.execute("SELECT COUNT(*) FROM subjects WHERE name = ?", (data.get('transfer_to'),))
                if c.fetchone()[0] == 0:
                    raise HTTPException(status_code=400, detail="Target subject does not exist.")
                c.execute("UPDATE resources SET subject = ? WHERE subject = ?", (data.get('transfer_to'), subject_name))
            else:
                c.execute("SELECT file_path FROM resources WHERE subject = ?", (subject_name,))
                files = [r[0] for r in c.fetchall()]
                for fp in files:
                    if await asyncio.to_thread(os.path.exists, fp):
                        try:
                            await asyncio.to_thread(os.remove, fp)
                        except Exception as e:
                            logging.warning(f"Could not remove physical file {fp}: {e}")
                c.execute("DELETE FROM resources WHERE subject = ?", (subject_name,))

            if data.get('id'):
                c.execute("DELETE FROM subjects WHERE id = ?", (data.get('id'),))
            else:
                c.execute("DELETE FROM subjects WHERE name = ?", (data.get('name'),))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"delete_subject: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete subject")


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
        c.execute("SELECT name FROM grades ORDER BY name ASC")
        rows = c.fetchall()
    return [{"name": r[0]} for r in rows]


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
            c.execute("INSERT INTO grades (name) VALUES (?)", (name,))
            conn.commit()
            return {"status": "success", "name": name}
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="Grade already exists.")


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
            c.execute("SELECT file_path FROM resources WHERE grade = ?", (name,))
            files = c.fetchall()
            for (fp,) in files:
                if await asyncio.to_thread(os.path.exists, fp):
                    await asyncio.to_thread(os.remove, fp)
            c.execute("DELETE FROM resources WHERE grade = ?", (name,))
        c.execute("DELETE FROM grades WHERE name = ?", (name,))
        conn.commit()
    return {"status": "success"}
