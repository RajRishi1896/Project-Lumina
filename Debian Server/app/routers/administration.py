"""Admin management: default admin toggling and admin/teacher/student CRUD."""
import sqlite3
import uuid
import asyncio
import secrets
from fastapi import APIRouter, Depends, HTTPException
from app.audit import audit, Action
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.models import TeacherCreate, AdminStudentCreate, StatusResponse, AdminSummary, AdminCreateResponse
from app.dependencies import hash_password, validate_password_strength, verify_admin

router = APIRouter()


@router.post("/teacher/disable-default-admin", response_model=StatusResponse,
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
    def _disable_admin(conn):
        """Disable the default admin only if another admin account exists."""
        count = conn.execute("SELECT count(*) FROM users WHERE username != 'admin' AND role = 'admin'").fetchone()[0]
        if count == 0:
            raise HTTPException(status_code=400, detail="Cannot disable default admin: No other admin accounts exist. Create another admin first.")  # i18n: user-facing error message
        conn.execute("UPDATE users SET hashed_password = 'DISABLED' WHERE username = 'admin'")
        conn.commit()
    await db_run(_disable_admin)
    await audit(action=Action.CHANGE_SETTINGS, username=admin_user, resource_type="account",
                resource_id="admin", resource_name="default admin", context={"enabled": False})
    return {"status": "success"}


@router.post("/teacher/enable-default-admin", response_model=StatusResponse,
             summary="Enable default admin",
             description="Re-enables the default admin account by resetting its password to the default.",
             tags=["Admin"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def enable_default_admin(admin_user: str = Depends(verify_admin)):
    """Re-enable the default admin account.

    Returns:
        Status dict indicating success.
    """
    generated_pwd = secrets.token_urlsafe(12)
    hashed = await asyncio.to_thread(hash_password, generated_pwd)
    await db_exec("UPDATE users SET hashed_password = ? WHERE username = 'admin'", (hashed,))
    await audit(action=Action.CHANGE_SETTINGS, username=admin_user, resource_type="account",
                resource_id="admin", resource_name="default admin", context={"enabled": True})
    return {"status": "success", "temporary_password": generated_pwd}


@router.get("/teacher/default-admin-status", response_model=dict,
            summary="Check default admin status",
            description="Returns whether the default admin account is currently enabled or disabled.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def default_admin_status(admin_user: str = Depends(verify_admin)):
    """Check if the default admin account is enabled.

    Returns:
        Dict with enabled boolean.
    """
    row = await db_fetch_one("SELECT hashed_password FROM users WHERE username = 'admin'")
    if row and row[0] == 'DISABLED':
        return {"enabled": False}
    return {"enabled": True}


@router.get("/api/admin/admins", response_model=list[AdminSummary],
            summary="List admin accounts",
            description="Returns all admin user profiles. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def list_admins(admin_user: str = Depends(verify_admin)):
    """List all admin users.

    Returns:
        List of dicts with username, name, department, and reset_required.
    """
    rows = await db_fetch("SELECT username, name, department, scholar_id, reset_required FROM users WHERE role = 'admin' ORDER BY name ASC")
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "System", "scholar_id": r[3] or "", "reset_required": r[4] or 0} for r in rows]


async def _create_user(data: TeacherCreate, admin_user: str, role: str, default_dept: str):
    """Shared helper for creating admin, teacher, or student accounts.

    Validates username uniqueness, hashes the password, inserts the user
    row, and logs the action to the audit log.

    Args:
        data: Account creation payload.
        admin_user: Username of the admin performing the action.
        role: Target role (``admin``, ``teacher``, or ``student``).
        default_dept: Default department if none specified in data.

    Returns:
        Dict with status, username, name, and scholar_id.

    Raises:
        HTTPException: 400 if username exists.
    """
    display_name = data.name or data.username
    dept = data.department or default_dept
    user_id = f"LUMINA_01-T{uuid.uuid4().hex}"
    valid, msg = validate_password_strength(data.password)
    if not valid:
        raise HTTPException(status_code=400, detail=msg)
    hashed_pwd = await asyncio.to_thread(hash_password, data.password)
    # Race-safe: users.username is the PRIMARY KEY, so a concurrent
    # create with the same username loses the INSERT and gets a 400.
    try:
        await db_exec(
            "INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, ?)",
            (data.username, hashed_pwd, display_name, dept, user_id, role),
        )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Username already exists.")  # i18n: user-facing error message
    await audit(action=Action.CREATE_ACCOUNT, username=admin_user, resource_type="account",
                resource_id=data.username, resource_name=display_name,
                target_user=data.username, context={"role": role})
    return {"status": "success", "username": data.username, "name": display_name, "scholar_id": user_id}


@router.post("/api/admin/create", response_model=AdminCreateResponse,
             summary="Create admin account",
             description="Creates a new admin user. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_admin(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a new admin account.

    Admin-only endpoint. Delegates to ``_create_user`` with role ``admin``
    and default department ``System``.
    """
    return await _create_user(data, admin_user, "admin", "System")


@router.post("/api/admin/create-teacher", response_model=AdminCreateResponse,
             summary="Create teacher account (admin)",
             description="Creates a new teacher user with the teacher role. Admin-only. Logs the action to the audit log.",
             tags=["Admin"],
             responses={400: {"description": "Username already exists or creation failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def create_teacher(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    """Create a new teacher account.

    Admin-only endpoint. Delegates to ``_create_user`` with role ``teacher``
    and default department ``General``.
    """
    return await _create_user(data, admin_user, "teacher", "General")


@router.post("/api/admin/create-student", response_model=AdminCreateResponse,
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
        HTTPException 400: If the username is already taken.
    """
    display_name = data.name or data.username
    scholar_id = f"LUMINA_01-{uuid.uuid4().hex}"
    pwd = data.password or secrets.token_urlsafe(12)
    if data.password:
        valid, msg = validate_password_strength(data.password)
        if not valid:
            raise HTTPException(status_code=400, detail=msg)
    hashed_pwd = await asyncio.to_thread(hash_password, pwd)
    # Race-safe: scholars.username has a UNIQUE index, so a concurrent
    # create with the same username loses the INSERT and gets a 400.
    try:
        await db_exec(
            "INSERT INTO scholars (id, username, name, hashed_password, reset_required, grade) VALUES (?, ?, ?, ?, 0, ?)",
            (scholar_id, data.username, display_name, hashed_pwd, data.grade or ""),
        )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Username already exists.")  # i18n: user-facing error message
    await audit(action=Action.CREATE_ACCOUNT, username=admin_user, resource_type="account",
                resource_id=data.username, resource_name=display_name,
                target_user=data.username, context={"role": "student"})
    resp = {"status": "success", "username": data.username, "name": display_name, "scholar_id": scholar_id}
    if not data.password:
        resp["temporary_password"] = pwd
    return resp
