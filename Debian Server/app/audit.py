"""Structured audit logging for Lumina EduMesh Hub.

Every admin/teacher/security event is written as a single JSON line to
``data/admin_actions.log``.

Design:
- JSON-lines format (one JSON object per line): parseable, filterable, exportable
- Async writes via ``asyncio.to_thread``: never blocks the request
- Bounded growth via existing retention pruning
- No secrets, passwords, tokens, or PII are ever written
"""
import os
import json
import uuid
import time
import asyncio
import logging
import sqlite3
from datetime import datetime, timezone
from typing import Optional

_DB_PATH = None  # lazy import to avoid circular import at module load
_RETENTION_CACHE: Optional[str] = None  # cached retention value, avoids DB open per event
_RETENTION_CACHE_TS: float = 0  # last cache refresh timestamp
_RETENTION_CACHE_TTL: float = 300  # refresh every 5 minutes
_RETENTION_DELTAS = {
    "24h": 86400,
    "7d": 604800,
    "30d": 2592000,
    "3m": 7776000,
    "6m": 15552000,
}


def _get_db_path():
    """Return the hub DB path, imported lazily to avoid a circular import."""
    global _DB_PATH
    if _DB_PATH is None:
        from app.database import DB_PATH
        _DB_PATH = DB_PATH
    return _DB_PATH


# === Action enums ===

class Action:
    """Canonical action identifiers: no free text."""
    # Auth
    LOGIN = "login"
    LOGOUT = "logout"
    LOGIN_FAILED = "login_failed"
    TOKEN_REFRESH = "token_refresh"
    FORCE_LOGOUT = "force_logout"

    # Account management
    CREATE_ACCOUNT = "create_account"
    DELETE_ACCOUNT = "delete_account"
    RESET_PASSWORD = "reset_password"
    CHANGE_PASSWORD = "change_password"
    FORCE_PASSWORD_CHANGE = "force_password_change"

    # Course management
    CREATE_COURSE = "create_course"
    UPDATE_COURSE = "update_course"
    DELETE_COURSE = "delete_course"
    PUBLISH_COURSE = "publish_course"
    UNPUBLISH_COURSE = "unpublish_course"
    ENROLL_COURSE = "enroll_course"
    UNENROLL_COURSE = "unenroll_course"

    # Resource management
    UPLOAD_RESOURCE = "upload_resource"
    UPDATE_RESOURCE = "update_resource"
    DELETE_RESOURCE = "delete_resource"
    DEPRECATE_RESOURCE = "deprecate_resource"

    # Quiz management
    CREATE_QUIZ = "create_quiz"
    UPDATE_QUIZ = "update_quiz"
    DELETE_QUIZ = "delete_quiz"

    # Topic management
    CREATE_TOPIC = "create_topic"
    UPDATE_TOPIC = "update_topic"
    DELETE_TOPIC = "delete_topic"

    # Academics
    CREATE_GRADE = "create_grade"
    UPDATE_GRADE = "update_grade"
    DELETE_GRADE = "delete_grade"
    CREATE_SUBJECT = "create_subject"
    UPDATE_SUBJECT = "update_subject"
    DELETE_SUBJECT = "delete_subject"

    # ZIM
    UPLOAD_ZIM = "upload_zim"
    DELETE_ZIM = "delete_zim"

    # Course resources
    UPLOAD_COURSE_RESOURCE = "upload_course_resource"
    IMPORT_ZIP = "import_zip"

    # Similar courses
    LINK_SIMILAR = "link_similar"
    UNLINK_SIMILAR = "unlink_similar"

    # Settings
    CHANGE_SETTINGS = "change_settings"

    # Security
    PERMISSION_DENIED = "permission_denied"
    RATE_LIMITED = "rate_limited"
    VALIDATION_ERROR = "validation_error"

    # System
    SERVER_START = "server_start"
    DATABASE_BACKUP = "database_backup"
    DATABASE_RESTORE = "database_restore"
    UPLOAD_REJECTED = "upload_rejected"
    SERVER_REBOOT = "server_reboot"
    WIFI_BAND_CHANGE = "wifi_band_change"


class Severity:
    """Log severity levels."""
    INFO = "info"
    NOTICE = "notice"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


# === Core logging function ===

async def audit(  # noqa: PLR0913
    action: str,
    username: str = "",
    *,
    severity: str = Severity.INFO,
    role: str = "",
    ip: str = "",
    target_user: str = "",
    resource_type: str = "",
    resource_id: str = "",
    resource_name: str = "",
    method: str = "",
    endpoint: str = "",
    status_code: int = 0,
    success: bool = True,
    error: str = "",
    changes: Optional[dict] = None,
    context: Optional[dict] = None,
    request: Optional[object] = None,
):
    """Write a structured audit event.

    Args:
        action: One of the Action constants (e.g. Action.LOGIN).
        username: The user performing the action.
        severity: One of the Severity constants.
        role: User role (admin/teacher/student).
        ip: Client IP address.
        target_user: Username of the user being acted upon (if different from actor).
        resource_type: Type of resource (course, resource, quiz, grade, subject).
        resource_id: ID of the affected resource.
        resource_name: Human-readable name of the resource.
        method: HTTP method (GET, POST, PUT, DELETE).
        endpoint: Request path.
        status_code: HTTP status code.
        success: Whether the operation succeeded.
        error: Error message if failed.
        changes: Dict of {field: {"old": x, "new": y}} for update operations.
        context: Additional metadata dict.
        request: FastAPI Request object. Extracts IP and User-Agent automatically.
    """
    event_id = uuid.uuid4().hex[:12]
    timestamp = datetime.now(timezone.utc).isoformat()

    if request and not ip:
        ip = _get_client_ip(request)

    request_id = ""
    if request:
        request_id = getattr(getattr(request, "state", None), "request_id", "")

    event = {
        "id": event_id,
        "ts": timestamp,
        "action": action,
        "severity": severity,
    }
    if request_id:
        event["request_id"] = request_id
    if username:
        event["user"] = username
    if role:
        event["role"] = role
    if ip:
        event["ip"] = ip
    if target_user:
        event["target"] = target_user
    if resource_type:
        event["resource_type"] = resource_type
    if resource_id:
        event["resource_id"] = resource_id
    if resource_name:
        event["resource_name"] = resource_name
    if method:
        event["method"] = method
    if endpoint:
        event["endpoint"] = endpoint
    if status_code:
        event["status"] = status_code
    if not success:
        event["success"] = False
    if error:
        event["error"] = error
    if changes:
        event["changes"] = changes
    if context:
        event["ctx"] = context

    await asyncio.to_thread(_write_audit_line, event)


def _get_client_ip(request) -> str:
    """Extract client IP from request, respecting X-Forwarded-For."""
    if not request:
        return ""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if hasattr(request, "client") and request.client:
        return request.client.host
    return ""


def _get_retention_cached() -> str:
    """Return the log retention setting, cached for 5 minutes to avoid a DB open per audit event."""
    global _RETENTION_CACHE, _RETENTION_CACHE_TS
    now = time.time()
    if _RETENTION_CACHE is not None and (now - _RETENTION_CACHE_TS) < _RETENTION_CACHE_TTL:
        return _RETENTION_CACHE
    try:
        conn = sqlite3.connect(_get_db_path(), timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute("SELECT value FROM settings WHERE key = 'log_retention'")
            row = cur.fetchone()
            _RETENTION_CACHE = row[0] if row else "30d"
        finally:
            conn.close()
    except Exception:
        _RETENTION_CACHE = "30d"
    _RETENTION_CACHE_TS = now
    return _RETENTION_CACHE


def _write_audit_line(event: dict):
    """Write one JSON line. Runs in worker thread."""
    retention = _get_retention_cached()

    if retention == "none":
        return

    json_line = json.dumps(event, ensure_ascii=False)
    log_line = f"{json_line}\n"

    try:
        with open("data/admin_actions.log", "a") as f:
            f.write(log_line)
    except Exception as e:
        logging.error(f"Could not write audit log: {e}")

    _prune_logs_if_needed(retention)


def _prune_logs_if_needed(retention):
    """Throttled log pruning: at most once per 60s."""
    if retention == "never":
        return
    now = time.time()
    if now - getattr(_prune_logs_if_needed, '_last_run', 0) < 60:
        return
    _prune_logs_if_needed._last_run = now
    _prune_logs_now(retention)


def _prune_logs_now(retention=None):
    """Immediate log pruning: used by scheduled background task."""
    if retention is None:
        try:
            conn = sqlite3.connect(_get_db_path(), timeout=5.0)
            try:
                cur = conn.cursor()
                cur.execute("SELECT value FROM settings WHERE key = 'log_retention'")
                row = cur.fetchone()
                retention = row[0] if row else "30d"
            finally:
                conn.close()
        except Exception:
            retention = "30d"
    if retention in ("never", "none"):
        return

    try:
        delta = _RETENTION_DELTAS.get(retention, 2592000)
        cutoff = datetime.now().timestamp() - delta
        kept_lines = []
        log_path = "data/admin_actions.log"
        if os.path.exists(log_path):
            original_count = 0
            with open(log_path, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    original_count += 1
                    try:
                        event = json.loads(line)
                        ts = event.get("ts", "")
                        log_time = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                        if log_time.timestamp() >= cutoff:
                            kept_lines.append(line + "\n")
                    except Exception:
                        kept_lines.append(line + "\n")
            if len(kept_lines) < original_count:
                with open(log_path, "w") as f:
                    f.writelines(kept_lines)
    except Exception as e:
        logging.error(f"Error pruning audit logs: {e}")
