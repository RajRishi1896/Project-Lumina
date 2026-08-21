"""Password management routes: change, force-change, and admin reset."""
import asyncio
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from app.async_db import db_exec, db_fetch_one
from app.models import StatusResponse
from app.dependencies import hash_password, verify_password, validate_password_strength, verify_teacher, verify_admin, invalidate_tokens_for_user
from app.audit import audit, Action

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
        raise HTTPException(status_code=400, detail="Cannot change the default admin password.")  # i18n: user-facing error message
    row = await db_fetch_one("SELECT hashed_password FROM users WHERE username = ?", (teacher_user,))
    if not row or not await asyncio.to_thread(verify_password, data.get('old_password'), row[0]):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Incorrect current password.")  # i18n: user-facing error message
    valid, msg = validate_password_strength(data.get('new_password'))
    if not valid:
        raise HTTPException(status_code=400, detail=msg)  # i18n: msg is from validate_password_strength(); user-facing
    new_hash = await asyncio.to_thread(hash_password, data.get('new_password'))
    await db_exec("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
    await invalidate_tokens_for_user(teacher_user)
    await audit(action=Action.CHANGE_PASSWORD, username=teacher_user, resource_type="account",
                severity="notice")
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
    try:
        row = await db_fetch_one("SELECT reset_required FROM users WHERE username = ?", (teacher_user,))
        if not row or not row[0]:
            raise HTTPException(status_code=400, detail="Password reset not required.")  # i18n: user-facing error message
        valid, msg = validate_password_strength(data.get('new_password'))
        if not valid:
            raise HTTPException(status_code=400, detail=msg)  # i18n: msg is from validate_password_strength(); user-facing
        new_hash = await asyncio.to_thread(hash_password, data.get('new_password'))
        await db_exec("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
        await invalidate_tokens_for_user(teacher_user)
        await audit(action=Action.FORCE_PASSWORD_CHANGE, username=teacher_user, resource_type="account",
                    severity="notice")
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"force_change_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to change password")  # i18n: user-facing error message


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
        raise HTTPException(status_code=400, detail="Cannot reset the default admin password. Use the Settings page to re-enable the default admin account.")  # i18n: user-facing error message
    hashed = await asyncio.to_thread(hash_password, "lumina2026")
    try:
        await db_exec("UPDATE users SET hashed_password = ?, reset_required = 1 WHERE username = ?", (hashed, username))
        await invalidate_tokens_for_user(username)
        await audit(action=Action.RESET_PASSWORD, username=admin_user, resource_type="account",
                    resource_id=username, target_user=username)
        return {"status": "success"}
    except Exception as e:
        logging.error(f"force_reset_teacher_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to reset password")  # i18n: user-facing error message
