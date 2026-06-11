"""Admin management — default admin toggling and admin/teacher/student CRUD."""
import uuid
import sqlite3
import logging
from fastapi import APIRouter, Depends, HTTPException
from app.database import log_admin_action
from app.async_db import db_conn
from app.models import TeacherCreate, AdminStudentCreate
from app.dependencies import hash_password, verify_admin

router = APIRouter()


@router.post("/teacher/disable-default-admin",
             summary="Disable default admin",
             description="Disables the default admin account by setting its password to DISABLED. Requires at least one other teacher profile.",
             tags=["Admin"],
             responses={400: {"description": "No teacher profiles exist"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def disable_default_admin(admin_user: str = Depends(verify_admin)):
    """Disable the default admin account.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If no other teacher profiles exist.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT count(*) FROM users WHERE username != 'admin'")
        count = c.fetchone()[0]
        if count == 0:
            raise HTTPException(status_code=400, detail="Cannot disable default admin: No teacher profiles exist.")
        c.execute("UPDATE users SET hashed_password = 'DISABLED' WHERE username = 'admin'")
        conn.commit()
    await log_admin_action(admin_user, "disabled the default admin account")
    return {"status": "success"}


@router.post("/teacher/enable-default-admin",
             summary="Enable default admin",
             description="Re-enables the default admin account by resetting its password to the default.",
             tags=["Admin"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def enable_default_admin(admin_user: str = Depends(verify_admin)):
    """Re-enable the default admin account.

    Returns:
        Status dict indicating success.
    """
    hashed = hash_password("lumina2026")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET hashed_password = ? WHERE username = 'admin'", (hashed,))
        conn.commit()
    await log_admin_action(admin_user, "enabled the default admin account")
    return {"status": "success"}


@router.get("/teacher/default-admin-status",
             summary="Check default admin status",
             description="Returns whether the default admin account is currently enabled or disabled.",
             tags=["Admin"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def default_admin_status(admin_user: str = Depends(verify_admin)):
    """Check if the default admin account is enabled.

    Returns:
        Dict with enabled boolean.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT hashed_password FROM users WHERE username = 'admin'")
        row = c.fetchone()
    if row and row[0] == 'DISABLED':
        return {"enabled": False}
    return {"enabled": True}


@router.get("/api/admin/admins",
            summary="List admin accounts",
            description="Returns all admin user profiles. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def list_admins(admin_user: str = Depends(verify_admin)):
    """List all admin users.

    Returns:
        List of dicts with username, name, department, and reset_required.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT username, name, department, reset_required FROM users WHERE role = 'admin' ORDER BY name ASC")
            rows = c.fetchall()
        except sqlite3.OperationalError:
            c.execute("SELECT username, name, department, '' as reset_required FROM users WHERE username != 'admin' ORDER BY name ASC")
            rows = c.fetchall()
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "System", "reset_required": r[3] or 0} for r in rows]


@router.post("/api/admin/create",
             summary="Create admin account",
             description="Creates a new admin user. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_admin(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a new admin account.

    Args:
        data: TeacherCreate payload with username, password, name, and department.

    Returns:
        Dict with status, username, name, and scholar_id.
    Raises:
        HTTPException 400: If the username is already taken.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT username FROM users WHERE username = ?", (data.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")
            display_name = data.name or data.username
            dept = data.department or "System"
            admin_id = f"LUMINA_01-T{uuid.uuid4().hex}"
            hashed_pwd = hash_password(data.password)
            c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'admin')",
                      (data.username, hashed_pwd, display_name, dept, admin_id))
            conn.commit()
            await log_admin_action(admin_user, f"created admin account '{data.username}'")
            return {"status": "success", "username": data.username, "name": display_name, "scholar_id": admin_id}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"create_admin: {e}")
            raise HTTPException(status_code=400, detail="Failed to create admin account")


@router.post("/api/admin/create-teacher",
             summary="Create teacher account (admin)",
             description="Creates a new teacher user with the teacher role. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_teacher(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a new teacher account (admin action).

    Args:
        data: TeacherCreate payload with username, password, name, and department.

    Returns:
        Dict with status, username, name, and scholar_id.
    Raises:
        HTTPException 400: If the username is already taken.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT username FROM users WHERE username = ?", (data.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")
            display_name = data.name or data.username
            dept = data.department or "General"
            teacher_id = f"LUMINA_01-T{uuid.uuid4().hex}"
            hashed_pwd = hash_password(data.password)
            c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'teacher')",
                      (data.username, hashed_pwd, display_name, dept, teacher_id))
            conn.commit()
            await log_admin_action(admin_user, f"created teacher account '{data.username}'")
            return {"status": "success", "username": data.username, "name": display_name, "scholar_id": teacher_id}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"create_teacher: {e}")
            raise HTTPException(status_code=400, detail="Failed to create teacher account")


@router.post("/api/admin/create-student",
             summary="Create student account (admin)",
             description="Creates a new student scholar account. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_student(data: AdminStudentCreate, admin_user: str = Depends(verify_admin)):
    """Create a new student account (admin action).

    Args:
        data: AdminStudentCreate payload with username, optional password, name, and grade.

    Returns:
        Dict with status, username, name, and scholar_id.
    Raises:
        HTTPException 400: If the username is already taken or creation fails.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT id FROM scholars WHERE username = ?", (data.username,))
            if c.fetchone():
                raise HTTPException(status_code=400, detail="Username already exists.")
            display_name = data.name or data.username
            scholar_id = f"LUMINA_01-{uuid.uuid4().hex}"
            pwd = data.password or "lumina2026"
            hashed_pwd = hash_password(pwd)
            if data.grade:
                c.execute("INSERT INTO scholars (id, username, name, hashed_password, reset_required, grade) VALUES (?, ?, ?, ?, 0, ?)",
                          (scholar_id, data.username, display_name, hashed_pwd, data.grade))
            else:
                c.execute("INSERT INTO scholars (id, username, name, hashed_password, reset_required) VALUES (?, ?, ?, ?, 0)",
                          (scholar_id, data.username, display_name, hashed_pwd))
            conn.commit()
            await log_admin_action(admin_user, f"created student account '{data.username}'")
            return {"status": "success", "username": data.username, "name": display_name, "scholar_id": scholar_id}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"create_student: {e}")
            raise HTTPException(status_code=400, detail="Failed to create student account")
