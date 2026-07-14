"""Password management routes — change, force-change, and admin reset."""
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from app.async_db import db_conn
from app.models import StatusResponse
from app.dependencies import hash_password, verify_password, validate_password_strength, verify_teacher, verify_admin, invalidate_tokens_for_user
from app.database import log_admin_action

router = APIRouter()


@router.post("/teacher/change-password", response_model=StatusResponse,
             summary="Change password",
             description="Changes the authenticated teacher's password after verifying the current password.",
             tags=["Teacher"],
             responses={400: {"description": "Incorrect password, weak password, or update failed"}, 401: {"description": "Unauthorized"}})
async def change_password(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Change the authenticated user's password.

    Args:
        data: Change password request with old and new passwords.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If current password is incorrect or new password is weak,
            or if the user is the default admin.
    """
    if teacher_user == "admin":
        raise HTTPException(status_code=400, detail="Cannot change the default admin password.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT hashed_password FROM users WHERE username = ?", (teacher_user,))
        row = c.fetchone()
        if not row or not verify_password(data.get('old_password'), row[0]):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Incorrect current password.")
        valid, msg = validate_password_strength(data.get('new_password'))
        if not valid:
            raise HTTPException(status_code=400, detail=msg)
        new_hash = hash_password(data.get('new_password'))
        c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
        conn.commit()
    await invalidate_tokens_for_user(teacher_user)
    return {"status": "success"}


@router.post("/teacher/force-change-password", response_model=StatusResponse,
             summary="Force change password",
             description="Changes password when reset_required is set (used for first-login forced password reset).",
             tags=["Teacher"],
             responses={400: {"description": "Reset not required, weak password, or update failed"}, 401: {"description": "Unauthorized"}})
async def force_change_password(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Force a password change when reset is required.

    Args:
        data: Force change request with new password.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If reset is not required or new password is weak.
    """
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("SELECT reset_required FROM users WHERE username = ?", (teacher_user,))
            row = c.fetchone()
            if not row or not row[0]:
                raise HTTPException(status_code=400, detail="Password reset not required.")
            valid, msg = validate_password_strength(data.get('new_password'))
            if not valid:
                raise HTTPException(status_code=400, detail=msg)
            new_hash = hash_password(data.get('new_password'))
            c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
            conn.commit()
            await invalidate_tokens_for_user(teacher_user)
            return {"status": "success"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"force_change_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to change password")


@router.post("/teacher/reset-password/{username}", response_model=StatusResponse,
             summary="Admin reset teacher password",
             description="Resets a teacher's password to the default and marks reset_required. Admin-only.",
             tags=["Admin"],
             responses={400: {"description": "Cannot reset default admin or reset failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def force_reset_teacher_password(username: str, admin_user: str = Depends(verify_admin)):
    """Admin-only: reset a teacher's password to the default.

    Args:
        username: The teacher's username.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If username is 'admin' or the reset fails.
    """
    if username == "admin":
        raise HTTPException(status_code=400, detail="Cannot reset the default admin password. Use the Settings page to re-enable the default admin account.")
    hashed = hash_password("lumina2026")
    async with db_conn() as conn:
        try:
            c = conn.cursor()
            c.execute("UPDATE users SET hashed_password = ?, reset_required = 1 WHERE username = ?", (hashed, username))
            conn.commit()
            await invalidate_tokens_for_user(username)
            await log_admin_action(admin_user, f"reset password for teacher {username}")
            return {"status": "success"}
        except Exception as e:
            logging.error(f"force_reset_teacher_password: {e}")
            raise HTTPException(status_code=400, detail="Failed to reset password")
