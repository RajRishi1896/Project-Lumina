"""Authentication dependencies and password helpers for Lumina EduMesh Hub."""
import re
import sqlite3
import asyncio
import bcrypt as bcrypt_lib
from datetime import datetime, timedelta
from fastapi import HTTPException, Request
from app.database import DB_PATH


def hash_password(password: str) -> str:
    """Hash a plain-text password using bcrypt.

    Args:
        password: Plain-text password to hash.

    Returns:
        Bcrypt-hashed password as a string.
    """
    return bcrypt_lib.hashpw(password.encode(), bcrypt_lib.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    """Verify a plain-text password against a bcrypt hash.

    Args:
        password: Plain-text password to verify.
        hashed: Bcrypt hash to compare against.

    Returns:
        True if the password matches the hash, False otherwise.
    """
    return bcrypt_lib.checkpw(password.encode(), hashed.encode())


def validate_password_strength(password: str) -> tuple[bool, str]:
    """Check a password against minimum strength requirements.

    Requires at least 8 characters, one uppercase letter, one lowercase
    letter, and one digit.

    Args:
        password: Plain-text password to validate.

    Returns:
        Tuple of (is_valid, error_message). Error message is empty when valid.
    """
    if len(password) < 8:
        return False, "Password must be at least 8 characters"
    if not any(c.isupper() for c in password):
        return False, "Password must contain an uppercase letter"
    if not any(c.islower() for c in password):
        return False, "Password must contain a lowercase letter"
    if not any(c.isdigit() for c in password):
        return False, "Password must contain a digit"
    return True, ""


def _is_stale_minutes(dt_str: str, minutes: int) -> bool:
    """Check if a datetime string is more than N minutes old.
    
    Args:
        dt_str: ISO datetime string from SQLite (e.g., '2026-06-11 12:00:00').
        minutes: Threshold in minutes.
    
    Returns:
        True if the datetime is older than the threshold or unparsable.
    """
    try:
        dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
        return datetime.now() - dt > timedelta(minutes=minutes)
    except (ValueError, TypeError):
        return True


async def _extract_user(request: Request) -> dict:
    """Resolve the authenticated user from a request's session cookie or bearer token.

    Checks the sessions table for teacher/admin tokens and the scholars
    table for student tokens. Updates the last_accessed timestamp on hit.

    Args:
        request: The incoming HTTP request.

    Returns:
        Dictionary with keys 'username' and 'role'.
    """
    auth = request.headers.get("Authorization")
    cookie = request.cookies.get("lumina_session")
    if not cookie and not (auth and auth.startswith("Bearer ")):
        raise HTTPException(status_code=401, detail="Unauthorized: Session required.")
    token = cookie or (auth.removeprefix("Bearer ") if auth else "")

    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute("SELECT s.username, s.role, s.last_accessed FROM sessions s JOIN users u ON s.username = u.username WHERE s.token = ?", (token,))
            row = cur.fetchone()
            if row:
                try:
                    # Only update last_accessed if >5min old — reduces DB writes
                    if row[2] is None or _is_stale_minutes(row[2], 5):
                        cur.execute("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
                        conn.commit()
                except Exception:
                    pass
                return {"username": row[0], "role": row[1]}
            cur.execute("SELECT s.username, s.last_accessed FROM sessions s JOIN scholars sc ON s.username = sc.id WHERE s.token = ?", (token,))
            row = cur.fetchone()
            if row:
                try:
                    if row[1] is None or _is_stale_minutes(row[1], 5):
                        cur.execute("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
                        conn.commit()
                except Exception:
                    pass
                return {"username": row[0], "role": "student"}
            raise HTTPException(status_code=401, detail="Unauthorized: Invalid session.")
        finally:
            conn.close()

    return await asyncio.to_thread(_run)


async def verify_teacher(request: Request) -> str:
    """Require teacher or admin role for the current session.

    Args:
        request: The incoming HTTP request.

    Returns:
        Username of the authenticated teacher or admin.

    Raises:
        HTTPException: 401 if not authenticated, 403 if role is insufficient.
    """
    user = await _extract_user(request)
    if user["role"] not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teacher privilege required.")
    return user["username"]


async def verify_admin(request: Request) -> str:
    """Require admin role for the current session.

    Args:
        request: The incoming HTTP request.

    Returns:
        Username of the authenticated admin.

    Raises:
        HTTPException: 401 if not authenticated, 403 if not an admin.
    """
    user = await _extract_user(request)
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admin privilege required.")
    return user["username"]


async def verify_student(request: Request):
    """Require a valid student session for the current request.

    Checks the sessions table for a student-role token and verifies the
    associated scholar account still exists.

    Args:
        request: The incoming HTTP request.

    Returns:
        Scholar username (id) from the session.

    Raises:
        HTTPException: 401 if the session is missing, expired, or the
            scholar account no longer exists.
    """
    token = request.cookies.get("lumina_session") or request.headers.get("Authorization", "").removeprefix("Bearer ")
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute("SELECT username FROM sessions WHERE token = ? AND role = 'student'", (token,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=401, detail="Invalid or expired student session")
            try:
                cur.execute("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
                conn.commit()
            except Exception:
                pass
            cur.execute("SELECT id FROM scholars WHERE id = ?", (row[0],))
            if not cur.fetchone():
                raise HTTPException(status_code=401, detail="Account no longer exists.")
            return row[0]
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=401, detail="Not authenticated")
        finally:
            conn.close()

    return await asyncio.to_thread(_run)
