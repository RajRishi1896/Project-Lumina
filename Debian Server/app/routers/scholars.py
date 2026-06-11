"""Scholar management routes — list, reset password, delete."""
import sqlite3
import logging
from fastapi import APIRouter, Depends, HTTPException
from app.async_db import db_conn
from app.dependencies import hash_password, verify_teacher

router = APIRouter()


@router.get("/teacher/scholars",
            summary="List all scholars",
            description="Returns a list of all scholars ordered by name, with reset_required flag.",
            tags=["Teacher"],
            responses={401: {"description": "Unauthorized"}})
async def get_scholars(teacher_user: str = Depends(verify_teacher)):
    """List all scholars.

    Returns:
        List of dicts with id, name, and reset_required fields.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT id, name, reset_required FROM scholars ORDER BY name ASC")
            rows = c.fetchall()
        except sqlite3.OperationalError:
            c.execute("SELECT id, name FROM scholars ORDER BY name ASC")
            rows = [(*r, 0) for r in c.fetchall()]
    return [{"id": r[0], "name": r[1], "reset_required": r[2] or 0} for r in rows]


@router.post("/teacher/scholars/reset-password/{scholar_id}",
             summary="Reset student password",
             description="Resets a scholar's password to the default and marks reset_required.",
             tags=["Teacher"],
             responses={400: {"description": "Failed to reset password"}, 401: {"description": "Unauthorized"}})
async def teacher_reset_student_password(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    """Reset a scholar's password to the default value.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Status dict indicating success.
    """
    hashed = hash_password("lumina2026")
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 1 WHERE id = ?", (hashed, scholar_id))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"teacher_reset_student_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to reset password")


@router.delete("/teacher/scholars/{scholar_id}",
               summary="Delete a scholar",
               description="Deletes a scholar and all associated activity logs and downloads.",
               tags=["Teacher"],
               responses={400: {"description": "Failed to delete student"}, 401: {"description": "Unauthorized"}})
async def teacher_delete_student(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    """Delete a scholar and related records.

    Args:
        scholar_id: The scholar's unique identifier.

    Returns:
        Status dict indicating success.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("DELETE FROM scholars WHERE id = ?", (scholar_id,))
            c.execute("DELETE FROM activity_logs WHERE scholar_id = ?", (scholar_id,))
            c.execute("DELETE FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
            conn.commit()
            return {"status": "success"}
        except Exception as e:
            logging.error(f"teacher_delete_student: {e}")
            raise HTTPException(status_code=400, detail="Failed to delete student")
