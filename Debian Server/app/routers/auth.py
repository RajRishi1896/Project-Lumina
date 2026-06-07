"""Authentication routes — register, login, token management, logout."""
import uuid
import sqlite3
import asyncio
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Request, Response, Form, status
from fastapi.responses import JSONResponse, RedirectResponse
from app.database import DB_PATH, log_admin_action
from app.async_db import db_conn, db_fetchone, db_fetchall, db_execute
from app.models import ScholarReg, StudentLoginRequest, TokenRefreshRequest, TokenRenewRequest
from app.dependencies import hash_password, verify_password, validate_password_strength, verify_teacher
from app.encryption import _generate_session_token, _make_encryption_key

router = APIRouter()


@router.post("/register", summary="Register a new student scholar", description="Creates or updates a scholar account with username and optional password. Returns session, refresh, and persistent tokens on success.", tags=["Auth"], responses={400: {"description": "Registration failed or validation error"}})
async def register_scholar(scholar: ScholarReg, request: Request):
    """Register a new student scholar account.

    Args:
        scholar: Registration details including username and optional password.
        request: The incoming HTTP request used to determine the secure scheme.

    Returns:
        JSON with the scholar ID, session token, refresh token, persistent key, and encryption key.

    Raises:
        HTTPException 400: If the password fails strength validation or registration otherwise fails.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        display_name = scholar.name or scholar.username
        c.execute("SELECT id FROM scholars WHERE username = ?", (scholar.username,))
        existing = c.fetchone()
        if existing:
            full_id = existing[0]
        else:
            unique_suffix = uuid.uuid4().hex
            full_id = f"LUMINA_01-{unique_suffix}"

        pwd = scholar.password or "lumina2026"
        if scholar.password:
            valid, msg = validate_password_strength(pwd)
            if not valid:
                raise HTTPException(status_code=400, detail=msg)
        hashed = hash_password(pwd)

        if existing:
            c.execute("UPDATE scholars SET hashed_password = ?, name = ?, reset_required = 0 WHERE id = ?", (hashed, display_name, full_id))
        else:
            c.execute("INSERT INTO scholars (id, username, name, hashed_password, reset_required) VALUES (?, ?, ?, ?, 0)", (full_id, scholar.username, display_name, hashed))
        conn.commit()

        tokens = await _generate_session_token(full_id, "student", _make_encryption_key())
        resp_data = {"id": full_id, "token": tokens["session_token"]}
        resp_data["refresh_token"] = tokens["refresh_token"]
        resp_data["persistent_key"] = tokens["persistent_key"]
        resp_data["encryption_key"] = tokens["encryption_key"]
        response = JSONResponse(resp_data)
        response.set_cookie(key="lumina_session", value=tokens["session_token"], httponly=True, samesite="strict", secure=request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https", max_age=86400)
        return response


@router.post("/student/token", summary="Authenticate a student", description="Validates student credentials against the scholars table and returns session, refresh, and persistent tokens. Also returns the student's name, grade, and reset-required flag.", tags=["Auth"], responses={401: {"description": "Invalid credentials or account not found"}, 500: {"description": "Login failed due to server error"}})
async def student_login(data: StudentLoginRequest, request: Request):
    """Authenticate a student and issue session tokens.

    Args:
        data: Student login credentials (username and password).
        request: The incoming HTTP request used to determine the secure scheme.

    Returns:
        JSON with status, scholar ID, session token, refresh token, persistent key, encryption key, name, grade, and reset-required flag.

    Raises:
        HTTPException 401: If the account is not found or credentials are invalid.
        HTTPException 500: If the login process fails unexpectedly.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT id, hashed_password, reset_required FROM scholars WHERE username = ?", (data.username,))
        row = c.fetchone()

        if not row:
            raise HTTPException(status_code=401, detail="Student account not found.")

        scholar_id, hashed_pwd, reset_req = row

        pwd_to_check = hashed_pwd
        if not pwd_to_check:
            raise HTTPException(status_code=401, detail="Password not set. Contact teacher to set your password.")

        if not verify_password(data.password, pwd_to_check):
            raise HTTPException(status_code=401, detail="Invalid student credentials.")

        tokens = await _generate_session_token(scholar_id, "student", _make_encryption_key())

        c.execute("SELECT name, grade FROM scholars WHERE id = ?", (scholar_id,))
        srow = c.fetchone()
        srow_name = srow[0] if srow else data.username
        srow_grade = srow[1] if srow else ""

        response = JSONResponse({
            "status": "ok", "scholar_id": scholar_id,
            "token": tokens["session_token"],
            "refresh_token": tokens["refresh_token"],
            "persistent_key": tokens["persistent_key"],
            "encryption_key": tokens["encryption_key"],
            "name": srow_name, "grade": srow_grade,
            "reset_required": bool(reset_req)
        })
        response.set_cookie(key="lumina_session", value=tokens["session_token"], httponly=True, samesite="strict", max_age=86400, secure=request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https")
        return response


@router.post("/token", summary="Authenticate a teacher or admin", description="Form-based login for teacher and admin users. Returns a bearer access token with user metadata including role, name, department, and scholar ID. Supports schema migration for the scholar_id column.", tags=["Auth"], responses={401: {"description": "Invalid credentials or account disabled"}})
async def login(response: Response, request: Request, username: str = Form(...), password: str = Form(...)):
    """Authenticate a teacher or admin via form-based login.

    Args:
        response: The outgoing response for setting the session cookie.
        request: The incoming HTTP request used to determine the secure scheme.
        username: The teacher or admin username.
        password: The account password.

    Returns:
        Dict with access token, token type, username, name, department, scholar ID, role, reset-required flag, and encryption key.

    Raises:
        HTTPException 401: If credentials are invalid or the account is disabled.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT hashed_password, name, department, scholar_id, reset_required, role FROM users WHERE username = ?", (username,))
            row = c.fetchone()
            reset_req = row[4] if row else 0
            if username == "admin":
                reset_req = 0
        except sqlite3.OperationalError:
            c.execute("SELECT hashed_password, username as name, 'General' as department, scholar_id FROM users WHERE username = ?", (username,))
            row = c.fetchone()
            if row and not row[3]:
                fallback_id = f"LUMINA_01-T{uuid.uuid4().hex}"
                conn.execute("UPDATE users SET scholar_id = ? WHERE username = ?", (fallback_id, username))
                conn.commit()
                row = (row[0], row[1], row[2], fallback_id)
            reset_req = 0

        if not row:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")
        if row[0] == 'DISABLED':
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="This account has been disabled by an administrator.")
        if not verify_password(password, row[0]):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")

        user_role = row[5] if (row and len(row) > 5) else ("admin" if username == "admin" else "teacher")
        tokens = await _generate_session_token(username, user_role, _make_encryption_key())
        scholar_id = row[3] if (row and row[3]) else None
        if not scholar_id:
            scholar_id = f"LUMINA_01-T{uuid.uuid4().hex}"
            conn.execute("UPDATE users SET scholar_id = ? WHERE username = ?", (scholar_id, username))
            conn.commit()
        response.set_cookie(key="lumina_session", value=tokens["session_token"], httponly=True, max_age=86400, samesite="strict", secure=request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https")
        return {
            "access_token": tokens["session_token"],
            "token_type": "bearer",
            "username": username,
            "name": row[1] or username,
            "department": row[2] or "General",
            "scholar_id": scholar_id,
            "role": user_role,
            "reset_required": reset_req or 0,
            "encryption_key": tokens["encryption_key"]
        }


@router.get("/logout", summary="Log out current user", description="Deletes the session, refresh token, and persistent key from the database and clears the lumina_session cookie. Redirects to the welcome page.", tags=["Auth"])
@router.post("/logout", summary="Log out current user", description="Deletes the session, refresh token, and persistent key from the database and clears the lumina_session cookie. Redirects to the welcome page.", tags=["Auth"])
async def logout(request: Request, response: Response):
    """Log out the current user and clear session data.

    Args:
        request: The incoming HTTP request containing the session cookie.
        response: The outgoing response used to delete the cookie.

    Returns:
        RedirectResponse to the welcome page.
    """
    token = request.cookies.get("lumina_session")
    if token:
        async with db_conn() as conn:
            c = conn.cursor()
            c.execute("DELETE FROM sessions WHERE token = ?", (token,))
            c.execute("DELETE FROM refresh_tokens WHERE token = ?", (token,))
            c.execute("DELETE FROM persistent_keys WHERE token = ?", (token,))
            conn.commit()
    response.delete_cookie(key="lumina_session", path="/")
    return RedirectResponse(url="/welcome")


@router.post("/student/refresh-token", summary="Refresh an expired session", description="Exchanges a valid one-time-use refresh token for a new set of session, refresh, and persistent tokens. The old refresh token is marked as used to prevent replay.", tags=["Auth"], responses={401: {"description": "Invalid, used, or expired refresh token"}, 500: {"description": "Token refresh failed due to server error"}})
async def refresh_session(data: TokenRefreshRequest, request: Request):
    """Refresh an expired session using a one-time refresh token.

    Args:
        data: The refresh token to exchange.
        request: The incoming HTTP request (unused but required for FastAPI dependency injection).

    Returns:
        Dict with new session token, refresh token, persistent key, and encryption key.

    Raises:
        HTTPException 401: If the refresh token is invalid, already used, or expired.
        HTTPException 500: If the refresh process fails unexpectedly.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT username, role, used, expires_at FROM refresh_tokens WHERE token = ?", (data.refresh_token,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=401, detail="Invalid refresh token")
        if row[2]:
            raise HTTPException(status_code=401, detail="Refresh token already used")
        if row[3] and datetime.fromisoformat(row[3]) < datetime.now():
            raise HTTPException(status_code=401, detail="Refresh token expired")
        username, role = row[0], row[1]
        c.execute("UPDATE refresh_tokens SET used = 1 WHERE token = ?", (data.refresh_token,))
        conn.commit()
        tokens = await _generate_session_token(username, role, _make_encryption_key())
        return {
            "token": tokens["session_token"],
            "refresh_token": tokens["refresh_token"],
            "persistent_key": tokens["persistent_key"],
            "encryption_key": tokens["encryption_key"]
        }


@router.post("/student/renew-session", summary="Renew session with persistent key", description="Exchanges a valid one-time-use persistent key for a new set of session tokens without requiring re-authentication. The old persistent key is marked as used.", tags=["Auth"], responses={401: {"description": "Invalid, used, or expired persistent key"}, 500: {"description": "Session renewal failed due to server error"}})
async def renew_session(data: TokenRenewRequest, request: Request):
    """Renew a session using a one-time persistent key without re-authentication.

    Args:
        data: The persistent key to exchange.
        request: The incoming HTTP request (unused but required for FastAPI dependency injection).

    Returns:
        Dict with new session token, refresh token, persistent key, and encryption key.

    Raises:
        HTTPException 401: If the persistent key is invalid, already used, or expired.
        HTTPException 500: If the renewal process fails unexpectedly.
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT username, role, used, expires_at FROM persistent_keys WHERE token = ?", (data.persistent_key,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=401, detail="Invalid persistent key")
        if row[2]:
            raise HTTPException(status_code=401, detail="Persistent key already used")
        if row[3] and datetime.fromisoformat(row[3]) < datetime.now():
            raise HTTPException(status_code=401, detail="Persistent key expired")
        username, role = row[0], row[1]
        c.execute("UPDATE persistent_keys SET used = 1 WHERE token = ?", (data.persistent_key,))
        conn.commit()
        tokens = await _generate_session_token(username, role, _make_encryption_key())
        return {
            "token": tokens["session_token"],
            "refresh_token": tokens["refresh_token"],
            "persistent_key": tokens["persistent_key"],
            "encryption_key": tokens["encryption_key"]
        }
