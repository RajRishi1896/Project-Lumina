"""Authentication dependencies and password helpers for Lumina EduMesh Hub."""
import time
import uuid
import bcrypt as bcrypt_lib
from datetime import datetime, timedelta
from fastapi import HTTPException, Request
from app.async_db import db_fetch_one, db_exec, db_run

# ponytail: per-token session cache. Avoids DB hit on every authenticated request.
# TTL 60s, max 2000 entries. Upgrade to Redis-backed if multi-node.
_session_cache: dict[str, tuple[dict, float]] = {}
_SESSION_CACHE_TTL = 60  # seconds
_SESSION_CACHE_MAX = 2000


def _cache_get(token: str) -> dict | None:
    entry = _session_cache.get(token)
    if entry and (time.time() - entry[1]) < _SESSION_CACHE_TTL:
        return entry[0]
    _session_cache.pop(token, None)
    return None


def _cache_put(token: str, user: dict):
    if len(_session_cache) > _SESSION_CACHE_MAX:
        # ponytail: evict oldest quarter
        cutoff = time.time() - _SESSION_CACHE_TTL
        stale = [k for k, v in _session_cache.items() if v[1] < cutoff]
        for k in stale[:len(stale) // 2 + 1]:
            _session_cache.pop(k, None)
    _session_cache[token] = (user, time.time())


def _cache_invalidate(token: str):
    _session_cache.pop(token, None)


def _cache_invalidate_user(username: str):
    to_del = [k for k, v in _session_cache.items() if v[0].get("username") == username]
    for k in to_del:
        _session_cache.pop(k, None)


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


def _is_session_stale(dt_str: str | None, minutes: int = 5) -> bool:
    """Check if a datetime string is older than the given threshold."""
    if dt_str is None:
        return True
    try:
        dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
        return datetime.now() - dt > timedelta(minutes=minutes)
    except (ValueError, TypeError):
        return True


async def _extract_user(request: Request) -> dict:
    if hasattr(request.state, "_user"):
        return request.state._user

    auth = request.headers.get("Authorization")
    cookie = request.cookies.get("lumina_session")
    if not cookie and (not auth or not auth.startswith("Bearer ")):
        raise HTTPException(status_code=401, detail="Unauthorized: Session required.")
    token = cookie or (auth.removeprefix("Bearer ") if auth else "")

    cached = _cache_get(token)
    if cached:
        request.state._user = cached
        return cached

    row = await db_fetch_one(
        "SELECT username, role, last_accessed FROM sessions WHERE token = ? AND role IN ('admin', 'teacher', 'student') AND used = 0 AND expiry > datetime('now')",
        (token,)
    )
    if row:
        if _is_session_stale(row["last_accessed"]):
            await db_exec("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
        result = {"username": row["username"], "role": row["role"]}
        _cache_put(token, result)
        request.state._user = result
        return result

    raise HTTPException(status_code=401, detail="Unauthorized: Invalid session.")


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


async def generate_session_token(username: str, role: str) -> dict:
    _cache_invalidate_user(username)
    stoken = f"LUMINA_HUB-{uuid.uuid4().hex}"
    rtoken = f"LUMINA_REF-{uuid.uuid4().hex}"
    ptoken = f"LUMINA_PER-{uuid.uuid4().hex}"

    def _create_tokens(conn):
        conn.execute("DELETE FROM sessions WHERE username = ? AND rowid NOT IN (SELECT rowid FROM sessions WHERE username = ? ORDER BY rowid DESC LIMIT 5)", (username, username))
        conn.execute("INSERT INTO sessions (token, username, role, encryption_key, used, expiry) VALUES (?, ?, ?, '', 0, datetime('now', '+1 day'))", (stoken, username, role))
        conn.execute("INSERT INTO refresh_tokens (token, username, role, expires_at) VALUES (?, ?, ?, datetime('now', '+7 days'))", (rtoken, username, role))
        conn.execute("INSERT INTO persistent_keys (token, username, role, expires_at) VALUES (?, ?, ?, datetime('now', '+365 days'))", (ptoken, username, role))
        conn.commit()
    await db_run(_create_tokens)
    return {"session_token": stoken, "refresh_token": rtoken, "persistent_key": ptoken, "encryption_key": ""}


async def invalidate_tokens_for_user(username: str):
    _cache_invalidate_user(username)
    def _delete_tokens(conn):
        conn.execute("DELETE FROM sessions WHERE username = ?", (username,))
        conn.execute("DELETE FROM refresh_tokens WHERE username = ?", (username,))
        conn.execute("DELETE FROM persistent_keys WHERE username = ?", (username,))
        conn.commit()
    await db_run(_delete_tokens)


async def verify_student(request: Request):
    if hasattr(request.state, "_student_id"):
        return request.state._student_id

    token = request.cookies.get("lumina_session") or request.headers.get("Authorization", "").removeprefix("Bearer ")
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # ponytail: check cache first (same token format, student role)
    cache_key = f"student:{token}"
    cached = _cache_get(token)
    if cached and cached.get("role") == "student":
        request.state._student_id = cached["username"]
        return cached["username"]

    row = await db_fetch_one(
        "SELECT username, last_accessed FROM sessions WHERE token = ? AND role = 'student' AND used = 0 AND expiry > datetime('now')",
        (token,)
    )
    if not row:
        raise HTTPException(status_code=401, detail="Invalid or expired student session")

    if _is_session_stale(row["last_accessed"]):
        await db_exec("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))

    exists = await db_fetch_one("SELECT id FROM scholars WHERE id = ?", (row["username"],))
    if not exists:
        raise HTTPException(status_code=401, detail="Account no longer exists.")

    result = {"username": row["username"], "role": "student"}
    _cache_put(token, result)
    request.state._student_id = row["username"]
    return row["username"]
