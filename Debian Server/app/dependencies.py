"""Authentication dependencies and password helpers for Lumina EduMesh Hub."""
import time
import uuid
import bcrypt as bcrypt_lib
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Request
from app.async_db import db_fetch_one, db_exec, db_run

# ponytail: per-token session cache. Avoids DB hit on every authenticated request.
# TTL 60s, max 2000 entries. Upgrade to Redis-backed if multi-node.
_session_cache: dict[str, tuple[dict, float]] = {}
_SESSION_CACHE_TTL = 60  # seconds
_SESSION_CACHE_MAX = 2000


def _cache_get(token: str) -> dict | None:
    """Return a cached session dict for ``token``, or None if absent/expired."""
    entry = _session_cache.get(token)
    if entry and (time.time() - entry[1]) < _SESSION_CACHE_TTL:
        return entry[0]
    _session_cache.pop(token, None)
    return None


def _cache_put(token: str, user: dict):
    """Store a session in the cache, evicting stale entries when over the cap."""
    if len(_session_cache) > _SESSION_CACHE_MAX:
        # ponytail: evict oldest quarter
        cutoff = time.time() - _SESSION_CACHE_TTL
        stale = [k for k, v in _session_cache.items() if v[1] < cutoff]
        for k in stale[:len(stale) // 2 + 1]:
            _session_cache.pop(k, None)
    _session_cache[token] = (user, time.time())


def _cache_invalidate_user(username: str):
    """Drop every cached session belonging to ``username``."""
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
        return False, "Password must be at least 8 characters"  # i18n: user-facing validation message
    if not any(c.isupper() for c in password):
        return False, "Password must contain an uppercase letter"  # i18n: user-facing validation message
    if not any(c.islower() for c in password):
        return False, "Password must contain a lowercase letter"  # i18n: user-facing validation message
    if not any(c.isdigit() for c in password):
        return False, "Password must contain a digit"  # i18n: user-facing validation message
    return True, ""


def _is_session_stale(dt_str: str | None, minutes: int = 5) -> bool:
    """Check if a datetime string is older than the given threshold."""
    if dt_str is None:
        return True
    try:
        dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        return datetime.now(timezone.utc) - dt > timedelta(minutes=minutes)
    except (ValueError, TypeError):
        return True


async def _extract_user(request: Request) -> dict:
    """Extract and validate the session token from the incoming request.

    Checks the ``lumina_session`` cookie first, then the ``Authorization``
    header.  Returns a dict with ``username`` and ``role`` on success.
    Results are cached in-memory for 60 seconds to avoid repeated DB hits.

    Raises:
        HTTPException: 401 if no valid session token is found.
    """
    if hasattr(request.state, "_user"):
        return request.state._user

    auth = request.headers.get("Authorization")
    cookie = request.cookies.get("lumina_session")
    if not cookie and (not auth or not auth.startswith("Bearer ")):
        _log_auth_failure("no_token", request)
        raise HTTPException(status_code=401, detail="Unauthorized: Session required.")  # i18n: user-facing auth error
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
            try:
                await db_exec("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
            except Exception:
                import logging as _log
                _log.warning("Failed to update last_accessed for token")
        result = {"username": row["username"], "role": row["role"]}
        _cache_put(token, result)
        request.state._user = result
        return result

    _log_auth_failure("invalid_token", request)
    raise HTTPException(status_code=401, detail="Unauthorized: Invalid session.")  # i18n: user-facing auth error


def _log_auth_failure(reason: str, request: Request):
    """Log authentication failure without blocking the request."""
    import logging as _log
    ip = ""
    if hasattr(request, "client") and request.client:
        ip = request.client.host
    _log.warning(f"AUTH_FAIL reason={reason} ip={ip} path={request.url.path}")


async def verify_teacher(request: Request) -> str:
    """Require teacher or admin role for the current session."""
    user = await _extract_user(request)
    if user["role"] not in ("teacher", "admin"):
        import logging as _log
        ip = ""
        if hasattr(request, "client") and request.client:
            ip = request.client.host
        _log.warning(f"PERM_DENIED user={user['username']} role={user['role']} need=teacher ip={ip} path={request.url.path}")
        raise HTTPException(status_code=403, detail="Teacher privilege required.")  # i18n: user-facing auth error
    return user["username"]


async def verify_admin(request: Request) -> str:
    """Require admin role for the current session."""
    user = await _extract_user(request)
    if user["role"] != "admin":
        import logging as _log
        ip = ""
        if hasattr(request, "client") and request.client:
            ip = request.client.host
        _log.warning(f"PERM_DENIED user={user['username']} role={user['role']} need=admin ip={ip} path={request.url.path}")
        raise HTTPException(status_code=403, detail="Admin privilege required.")  # i18n: user-facing auth error
    return user["username"]


async def verify_user(request: Request) -> str:
    """Require any authenticated role (admin, teacher, or student).

    Args:
        request: The incoming HTTP request.

    Returns:
        Username of the authenticated user.
    """
    user = await _extract_user(request)
    return user["username"]


async def can_manage_resource(actor_username: str, owner_username: str | None) -> bool:
    """Return True if the actor owns the resource or has admin role.

    Used by teacher-owned content routes (resources, quizzes) to enforce
    per-teacher ownership with an admin override.

    Args:
        actor_username: The authenticated user's username.
        owner_username: The ``uploaded_by`` value stored on the resource.

    Returns:
        True when the actor owns the resource or is an admin.
    """
    if owner_username and owner_username == actor_username:
        return True
    user = await db_fetch_one("SELECT role FROM users WHERE username = ?", (actor_username,))
    return bool(user and user["role"] == "admin")


async def generate_session_token(username: str, role: str) -> dict:
    """Create a session token, refresh token, and persistent key for a user.

    Invalidates any existing cached sessions for this user, then inserts
    new rows into ``sessions``, ``refresh_tokens``, and ``persistent_keys``.
    Old sessions beyond the most recent 5 are pruned.

    Args:
        username: The authenticated user's username.
        role: The user's role (``admin``, ``teacher``, or ``student``).

    Returns:
        Dict with ``session_token``, ``refresh_token``, and ``persistent_key``.
    """
    _cache_invalidate_user(username)
    stoken = f"LUMINA_HUB-{uuid.uuid4().hex}"
    rtoken = f"LUMINA_REF-{uuid.uuid4().hex}"
    ptoken = f"LUMINA_PER-{uuid.uuid4().hex}"

    def _create_tokens(conn):
        """Prune old sessions and insert the new session/refresh/persistent rows."""
        conn.execute("DELETE FROM sessions WHERE username = ? AND rowid NOT IN (SELECT rowid FROM sessions WHERE username = ? ORDER BY rowid DESC LIMIT 5)", (username, username))
        conn.execute("INSERT INTO sessions (token, username, role, used, expiry) VALUES (?, ?, ?, 0, datetime('now', '+1 day'))", (stoken, username, role))
        conn.execute("INSERT INTO refresh_tokens (token, username, role, expires_at) VALUES (?, ?, ?, datetime('now', '+7 days'))", (rtoken, username, role))
        conn.execute("INSERT INTO persistent_keys (token, username, role, expires_at) VALUES (?, ?, ?, datetime('now', '+365 days'))", (ptoken, username, role))
        conn.commit()
    await db_run(_create_tokens)
    return {"session_token": stoken, "refresh_token": rtoken, "persistent_key": ptoken}


async def invalidate_tokens_for_user(username: str):
    """Clear all session, refresh, and persistent tokens for a user.

    Removes cached entries from the in-memory session cache and deletes
    all token rows from the database, effectively logging the user out.

    Args:
        username: The user whose tokens should be invalidated.
    """
    _cache_invalidate_user(username)
    def _delete_tokens(conn):
        """Delete all session/refresh/persistent rows for the user in one transaction."""
        conn.execute("DELETE FROM sessions WHERE username = ?", (username,))
        conn.execute("DELETE FROM refresh_tokens WHERE username = ?", (username,))
        conn.execute("DELETE FROM persistent_keys WHERE username = ?", (username,))
        conn.commit()
    await db_run(_delete_tokens)


async def verify_student(request: Request) -> str:
    """FastAPI dependency that validates the session and enforces student role.

    Composes ``_extract_user`` (shared token extraction + cache) with a
    student role check and a scholar-exists lookup, so students resolve
    through the same session path as teachers/admins.

    Returns:
        The student's username (scholar ID).

    Raises:
        HTTPException: 401 if not authenticated, not a student, or the
            scholar account has been deleted.
    """
    user = await _extract_user(request)
    if user["role"] != "student":
        raise HTTPException(status_code=401, detail="Not authenticated")  # i18n: user-facing auth error

    if not hasattr(request.state, "_scholar_exists"):
        exists = await db_fetch_one("SELECT id FROM scholars WHERE id = ?", (user["username"],))
        if not exists:
            raise HTTPException(status_code=401, detail="Account no longer exists.")  # i18n: user-facing auth error
        request.state._scholar_exists = True
    return user["username"]
