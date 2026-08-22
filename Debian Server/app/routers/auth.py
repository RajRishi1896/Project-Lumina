"""Authentication routes: register, login, token management, logout."""
import uuid
import time
import sqlite3

import asyncio
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, Response, Form, status
from fastapi.responses import JSONResponse, RedirectResponse
from app.async_db import db_exec, db_fetch_one, db_run
from app.audit import audit, Action
from app.models import ScholarReg, StudentLoginRequest, ScholarRegisterResponse, StudentLoginResponse, LoginTokenResponse, TokenResponse
from app.dependencies import hash_password, verify_password, validate_password_strength, generate_session_token, invalidate_tokens_for_user

router = APIRouter()

# ponytail: per-IP rate limiter, in-memory dict.
# Zero external deps, survives ~250 concurrent.
# Upgrade to Redis-backed if multi-node in future.
_login_attempts: dict[str, list[float]] = {}
_MAX_LOGIN_ATTEMPTS = 10
_LOGIN_WINDOW = 60  # seconds
_MAX_IPS = 500  # ponytail: cap dict size to prevent memory leak


def _check_rate_limit(request: Request):
    """Raise 429 if this IP exceeds max login attempts in the window."""
    ip = request.client.host if request.client else "unknown"
    now = time.time()
    window_start = now - _LOGIN_WINDOW
    attempts = _login_attempts.get(ip, [])
    attempts = [t for t in attempts if t > window_start]
    if len(attempts) >= _MAX_LOGIN_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later.")  # i18n: user-facing error message
    _login_attempts[ip] = attempts


def _record_failed_login(request: Request):
    """Record a failed login attempt for rate limiting."""
    ip = request.client.host if request.client else "unknown"
    now = time.time()
    # ponytail: cap dict size; drop oldest IPs if over limit
    if len(_login_attempts) > _MAX_IPS:
        cutoff = now - _LOGIN_WINDOW
        stale = [k for k, v in _login_attempts.items() if not v or v[-1] < cutoff]
        for k in stale[:len(stale) // 2 + 1]:
            _login_attempts.pop(k, None)
    attempts = _login_attempts.get(ip, [])
    attempts.append(now)
    _login_attempts[ip] = attempts


def _secure_cookie(request) -> bool:
    """Return True when the request arrived over HTTPS (direct or proxied)."""
    return request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https"


async def _consume_one_time(table: str, field: str, value):
    """Atomically validate and mark used a one-time token row.

    Args:
        table: Token table name (``refresh_tokens`` or ``persistent_keys``).
        field: Column holding the token value.
        value: The presented token.

    Returns:
        Tuple of (username, role).

    Raises:
        HTTPException 401: If the token is invalid, already used, or expired.
    """
    label = table[:-1].replace("_", " ")

    def _consume(conn):
        """Validate and one-time-use the token; returns (username, role)."""
        row = conn.execute(
            f"SELECT username, role, used, expires_at FROM {table} WHERE {field} = ?",
            (value,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=401, detail=f"Invalid {label}")  # i18n: user-facing error message
        if row[2]:
            raise HTTPException(status_code=401, detail=f"{label.capitalize()} already used")  # i18n: user-facing error message
        if row[3] and datetime.fromisoformat(row[3]).replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
            raise HTTPException(status_code=401, detail=f"{label.capitalize()} expired")  # i18n: user-facing error message
        conn.execute(f"UPDATE {table} SET used = 1 WHERE {field} = ?", (value,))
        conn.commit()
        return row[0], row[1]

    return await db_run(_consume)


@router.post("/register", response_model=ScholarRegisterResponse, summary="Register a new student scholar", description="Creates or updates a scholar account with username and optional password. Returns session, refresh, and persistent tokens on success.", tags=["Auth"], responses={400: {"description": "Registration failed or validation error"}})
async def register_scholar(scholar: ScholarReg, request: Request):
    """Register a new student scholar account.

    Args:
        scholar: Registration details including username and optional password.
        request: The incoming HTTP request used to determine the secure scheme.

    Returns:
        JSON with the scholar ID, session token, refresh token, and persistent key.

    Raises:
        HTTPException 400: If the password fails strength validation or registration otherwise fails.
    """
    _check_rate_limit(request)
    display_name = scholar.name or scholar.username
    grade_val = scholar.grade or "General"

    if not scholar.password:
        raise HTTPException(status_code=400, detail="Password is required")  # i18n: user-facing validation message
    pwd = scholar.password
    valid, msg = validate_password_strength(pwd)
    if not valid:
        raise HTTPException(status_code=400, detail=msg)  # i18n: msg is from validate_password_strength(); user-facing
    hashed = await asyncio.to_thread(hash_password, pwd)

    unique_suffix = uuid.uuid4().hex
    full_id = f"LUMINA_01-{unique_suffix}"

    # Race-safe duplicate detection: the UNIQUE index on scholars(username)
    # guarantees exactly one concurrent register wins; the loser gets a 409.
    try:
        await db_exec(
            "INSERT INTO scholars (id, username, name, hashed_password, reset_required, grade) "
            "VALUES (?, ?, ?, ?, 0, ?)",
            (full_id, scholar.username, display_name, hashed, grade_val),
        )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Username already taken")  # i18n: user-facing registration error
    await audit(action=Action.CREATE_ACCOUNT, username=scholar.username, resource_type="account",
                resource_id=full_id, role="student", request=request,
                context={"is_update": False})

    tokens = await generate_session_token(full_id, "student")
    resp_data = {"id": full_id, "token": tokens["session_token"]}
    resp_data["refresh_token"] = tokens["refresh_token"]
    resp_data["persistent_key"] = tokens["persistent_key"]
    response = JSONResponse(resp_data)
    response.set_cookie(key="lumina_session", value=tokens["session_token"], httponly=True, samesite="lax", secure=_secure_cookie(request), max_age=86400)
    return response


@router.post("/student/token", response_model=StudentLoginResponse, summary="Authenticate a student", description="Validates student credentials against the scholars table and returns session, refresh, and persistent tokens. Also returns the student's name, grade, and reset-required flag.", tags=["Auth"], responses={401: {"description": "Invalid credentials or account not found"}, 500: {"description": "Login failed due to server error"}})
async def student_login(data: StudentLoginRequest, request: Request):
    """Authenticate a student and issue session tokens.

    Args:
        data: Student login credentials (username and password).
        request: The incoming HTTP request used to determine the secure scheme.

    Returns:
        JSON with status, scholar ID, session token, refresh token, persistent key, name, grade, and reset-required flag.

    Raises:
        HTTPException 401: If the account is not found or credentials are invalid.
        HTTPException 429: If rate limited.
        HTTPException 500: If the login process fails unexpectedly.
    """
    _check_rate_limit(request)
    row = await db_fetch_one("SELECT id, hashed_password, reset_required, name, grade FROM scholars WHERE username = ?", (data.username,))

    if not row:
        _record_failed_login(request)
        await audit(action=Action.LOGIN_FAILED, username=data.username, request=request,
                    success=False, error="student account not found", role="student")
        raise HTTPException(status_code=401, detail="Student account not found.")  # i18n: user-facing error message

    scholar_id, hashed_pwd, reset_req, srow_name, srow_grade = row

    if not hashed_pwd:
        _record_failed_login(request)
        await audit(action=Action.LOGIN_FAILED, username=data.username, request=request,
                    success=False, error="password not set", role="student")
        raise HTTPException(status_code=401, detail="Password not set. Contact teacher to set your password.")  # i18n: user-facing error message

    password_ok = await asyncio.to_thread(verify_password, data.password, hashed_pwd)
    if not password_ok:
        _record_failed_login(request)
        await audit(action=Action.LOGIN_FAILED, username=data.username, request=request,
                    success=False, error="invalid password", role="student")
        raise HTTPException(status_code=401, detail="Invalid student credentials.")  # i18n: user-facing error message

    tokens = await generate_session_token(scholar_id, "student")

    srow_name = srow_name or data.username
    srow_grade = srow_grade or "General"

    await audit(action=Action.LOGIN, username=data.username, request=request, role="student")
    response = JSONResponse({
        "status": "ok", "scholar_id": scholar_id,
        "token": tokens["session_token"],
        "refresh_token": tokens["refresh_token"],
        "persistent_key": tokens["persistent_key"],
        "name": srow_name, "grade": srow_grade,
        "reset_required": bool(reset_req)
    })
    response.set_cookie(key="lumina_session", value=tokens["session_token"], httponly=True, samesite="lax", max_age=86400, secure=_secure_cookie(request))
    return response


@router.post("/token", response_model=LoginTokenResponse, summary="Authenticate a teacher or admin", description="Form-based login for teacher and admin users. Returns a bearer access token with user metadata including role, name, department, and scholar ID. Supports schema migration for the scholar_id column.", tags=["Auth"], responses={401: {"description": "Invalid credentials or account disabled"}})
async def login(response: Response, request: Request, username: str = Form(...), password: str = Form(...)):
    """Authenticate a teacher or admin via form-based login.

    Args:
        response: The outgoing response for setting the session cookie.
        request: The incoming HTTP request used to determine the secure scheme.
        username: The teacher or admin username.
        password: The account password.

    Returns:
        Dict with access token, token type, username, name, department, scholar ID, role, and reset-required flag.
    """
    _check_rate_limit(request)
    row = await db_fetch_one("SELECT hashed_password, name, department, scholar_id, reset_required, role FROM users WHERE username = ?", (username,))
    reset_req = row[4] if row else 0
    if username == "admin":
        reset_req = 0

    if not row:
        _record_failed_login(request)
        await audit(action=Action.LOGIN_FAILED, username=username, request=request,
                    success=False, error="account not found")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")  # i18n: user-facing login error
    if row[0] == 'DISABLED':
        _record_failed_login(request)
        await audit(action=Action.LOGIN_FAILED, username=username, request=request,
                    success=False, error="account disabled", severity="warning")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="This account has been disabled by an administrator.")  # i18n: user-facing login error
    password_ok = await asyncio.to_thread(verify_password, password, row[0])
    if not password_ok:
        _record_failed_login(request)
        await audit(action=Action.LOGIN_FAILED, username=username, request=request,
                    success=False, error="invalid password")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")  # i18n: user-facing login error

    user_role = row[5]
    # Same token path as students: prunes to newest 5 sessions and
    # invalidates cached sessions for the user.
    tokens = await generate_session_token(username, user_role)
    scholar_id = row[3]
    await audit(action=Action.LOGIN, username=username, request=request, role=user_role)
    response.set_cookie(key="lumina_session", value=tokens["session_token"], httponly=True, max_age=86400, samesite="lax", secure=_secure_cookie(request))
    return {
        "access_token": tokens["session_token"],
        "token_type": "bearer",
        "username": username,
        "name": row[1] or username,
        "department": row[2] or "General",
        "scholar_id": scholar_id,
        "role": user_role,
        "reset_required": reset_req or 0
    }


@router.api_route("/logout", methods=["GET", "POST"], summary="Log out current user", description="Deletes the session, refresh token, and persistent key from the database and clears the lumina_session cookie. Redirects to the welcome page.", tags=["Auth"])
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
        # Extract username from the session to properly invalidate all tokens
        row = await db_fetch_one("SELECT username FROM sessions WHERE token = ?", (token,))
        if row:
            await invalidate_tokens_for_user(row["username"])
    response.delete_cookie(key="lumina_session", path="/")
    return RedirectResponse(url="/welcome")


@router.post("/student/refresh-token", response_model=TokenResponse, summary="Refresh an expired session", description="Exchanges a valid one-time-use refresh token for a new set of session, refresh, and persistent tokens. The old refresh token is marked as used to prevent replay.", tags=["Auth"], responses={401: {"description": "Invalid, used, or expired refresh token"}, 500: {"description": "Token refresh failed due to server error"}})
async def refresh_session(data: dict, request: Request):
    """Refresh an expired session using a one-time refresh token.

    Args:
        data: The refresh token to exchange.
        request: The incoming HTTP request (unused but required for FastAPI dependency injection).

    Returns:
        Dict with new session token, refresh token, and persistent key.

    Raises:
        HTTPException 401: If the refresh token is invalid, already used, or expired.
        HTTPException 500: If the refresh process fails unexpectedly.
    """
    username, role = await _consume_one_time("refresh_tokens", "token", data.get('refresh_token'))
    tokens = await generate_session_token(username, role)
    return {
        "token": tokens["session_token"],
        "refresh_token": tokens["refresh_token"],
        "persistent_key": tokens["persistent_key"]
    }


@router.post("/student/renew-session", response_model=TokenResponse, summary="Renew session with persistent key", description="Exchanges a valid one-time-use persistent key for a new set of session tokens without requiring re-authentication. The old persistent key is marked as used.", tags=["Auth"], responses={401: {"description": "Invalid, used, or expired persistent key"}, 500: {"description": "Session renewal failed due to server error"}})
async def renew_session(data: dict, request: Request):
    """Renew a session using a one-time persistent key without re-authentication.

    Args:
        data: The persistent key to exchange.
        request: The incoming HTTP request (unused but required for FastAPI dependency injection).

    Returns:
        Dict with new session token, refresh token, and persistent key.

    Raises:
        HTTPException 401: If the persistent key is invalid, already used, or expired.
        HTTPException 500: If the renewal process fails unexpectedly.
    """
    username, role = await _consume_one_time("persistent_keys", "token", data.get('persistent_key'))
    tokens = await generate_session_token(username, role)
    return {
        "token": tokens["session_token"],
        "refresh_token": tokens["refresh_token"],
        "persistent_key": tokens["persistent_key"]
    }
