"""Admin audit log and settings routes."""
import os
import re
import json
import asyncio
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Response, Query
from app.audit import audit, Action
from app.async_db import db_conn
from app.models import AuditLogResponse, SettingsResponse, StatusResponse
from app.dependencies import verify_admin

router = APIRouter()

# Pattern for old-format plain text log lines:
# 2026-07-15T19:12:26.922028 - admin: created teacher account 'test_teacher'
_LEGACY_RE = re.compile(r'^(\S+)\s+-\s+(\S+):\s+(.*)')

# Map old human-readable action text to structured action constants
_LEGACY_ACTION_MAP = {
    'logged in': 'login',
    'logged out': 'logout',
    'failed login attempt': 'login_failed',
    'created admin account': 'create_account',
    'created teacher account': 'create_account',
    'created student account': 'create_account',
    'deleted account': 'delete_account',
    'reset password': 'reset_password',
    'changed password': 'change_password',
    'force-changed password': 'force_password_change',
    'created course': 'create_course',
    'updated course': 'update_course',
    'deleted course': 'delete_course',
    'published course': 'publish_course',
    'unpublished course': 'unpublish_course',
    'enrolled in course': 'enroll_course',
    'uploaded resource': 'upload_resource',
    'deleted resource': 'delete_resource',
    'deprecated resource': 'deprecate_resource',
    'created quiz': 'create_quiz',
    'updated quiz': 'update_quiz',
    'deleted quiz': 'delete_quiz',
    'created standalone quiz': 'create_quiz',
    'uploaded zim archive': 'upload_zim',
    'deleted zim archive': 'delete_zim',
    'changed settings': 'change_settings',
    'changed log retention': 'change_settings',
    'created grade': 'create_grade',
    'deleted grade': 'delete_grade',
    'created subject': 'create_subject',
    'deleted subject': 'delete_subject',
    'created topic': 'create_topic',
    'deleted topic': 'delete_topic',
    'created teacher': 'create_teacher',
    'deleted teacher': 'delete_teacher',
    'reset teacher password': 'reset_teacher_password',
    'toggled default admin': 'toggle_default_admin',
    'disabled the default admin': 'toggle_default_admin',
    'enabled the default admin': 'toggle_default_admin',
}


def _parse_legacy_line(line: str) -> dict:
    """Parse an old-format plain text log line into a structured event dict."""
    m = _LEGACY_RE.match(line)
    if not m:
        return {"ts": "", "action": "unknown", "severity": "info", "user": "", "raw": line}
    ts_raw, user, summary = m.group(1), m.group(2), m.group(3)

    # Normalize timestamp to ISO format with Z
    ts = ts_raw
    if not ts.endswith('Z'):
        ts = ts + 'Z'

    # Try to map the summary to a structured action
    action = 'unknown'
    summary_lower = summary.lower().rstrip('.')
    for pattern, act in _LEGACY_ACTION_MAP.items():
        if summary_lower.startswith(pattern):
            action = act
            break

    return {
        "ts": ts,
        "action": action,
        "severity": "info",
        "user": user,
        "summary": summary,
        "success": True,
    }


@router.get("/admin/log",
            summary="View admin audit log",
            description="Returns the most recent admin action log entries. Supports filtering by action, user, severity, success, date range, and request ID. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def admin_log(
    limit: int = Query(default=50, ge=1, le=500),
    action: Optional[str] = Query(default=None),
    user: Optional[str] = Query(default=None),
    severity: Optional[str] = Query(default=None),
    success: Optional[str] = Query(default=None),
    search: Optional[str] = Query(default=None),
    rid: Optional[str] = Query(default=None),
    since: Optional[str] = Query(default=None),
    until: Optional[str] = Query(default=None),
    admin_user: str = Depends(verify_admin),
):
    """Read the admin audit log with optional filters.

    Args:
        limit: Maximum number of log entries to return.
        action: Filter by action type (e.g., "LOGIN", "CREATE_ACCOUNT").
        user: Filter by username (substring match).
        severity: Filter by severity ("info", "notice", "warning", "error", "critical").
        success: Filter by success field ("true" or "false").
        search: Full-text search across summary, action, user, and error fields.
        rid: Filter by request ID.
        since: ISO 8601 timestamp -- only include events after this time.
        until: ISO 8601 timestamp -- only include events before this time.

    Returns:
        Dict with a log list of structured event objects.
    """
    try:
        def _read_log():
            try:
                with open("data/admin_actions.log", "r") as f:
                    lines = f.readlines()
                result = []
                # Read from end for most recent
                for line in reversed(lines):
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                    except Exception:
                        event = _parse_legacy_line(line)

                    # Apply filters
                    if action and event.get("action", "") != action:
                        continue
                    if user and user.lower() not in event.get("user", "").lower():
                        continue
                    if severity and event.get("severity", "") != severity:
                        continue
                    if success is not None:
                        evt_success = event.get("success")
                        want = success.lower() == "true"
                        if evt_success is not None and evt_success != want:
                            continue
                    if rid and event.get("request_id", "") != rid and event.get("ctx", {}).get("request_id", "") != rid:
                        continue
                    if search:
                        search_lower = search.lower()
                        haystack = " ".join(str(v) for v in [
                            event.get("summary", ""),
                            event.get("action", ""),
                            event.get("user", ""),
                            event.get("error", ""),
                            event.get("resource_name", ""),
                        ]).lower()
                        if search_lower not in haystack:
                            continue
                    if since:
                        try:
                            evt_ts = event.get("ts", "")
                            if evt_ts and evt_ts < since:
                                continue
                        except Exception:
                            pass
                    if until:
                        try:
                            evt_ts = event.get("ts", "")
                            if evt_ts and evt_ts > until:
                                continue
                        except Exception:
                            pass

                    result.append(event)
                    if len(result) >= limit:
                        break

                result.reverse()
                return result
            except FileNotFoundError:
                return []

        log_lines = await asyncio.to_thread(_read_log)
        return {"log": log_lines}
    except FileNotFoundError:
        return {"log": []}


@router.get("/api/admin/settings", response_model=SettingsResponse,
            summary="Get admin settings",
            description="Returns current admin settings (log retention policy). Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def get_admin_settings(admin_user: str = Depends(verify_admin)):
    """Get current admin settings.

    Returns:
        Dict with log_retention policy value (defaults to "30d").
    """
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("SELECT value FROM settings WHERE key = 'log_retention'")
        row = c.fetchone()
    return {"log_retention": row[0] if row else "30d"}


@router.post("/api/admin/settings", response_model=StatusResponse,
             summary="Update admin settings",
             description="Updates the log retention policy. Admin-only. Valid policies: 24h, 7d, 30d, 3m, 6m, never, none.",
             tags=["Admin"],
             responses={400: {"description": "Invalid retention policy"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def set_admin_settings(data: dict, admin_user: str = Depends(verify_admin)):
    """Update the log retention policy.

    Args:
        data: LogRetentionUpdate with a policy field.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If the policy value is not recognized.
    """
    if data.get('policy') not in ("24h", "7d", "30d", "3m", "6m", "never", "none"):
        raise HTTPException(status_code=400, detail="Invalid log retention policy.")  # i18n: user-facing error message
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('log_retention', ?)", (data.get('policy'),))
        conn.commit()
    await audit(action=Action.CHANGE_SETTINGS, username=admin_user, resource_type="settings",
                resource_name="log_retention", context={"policy": data.get('policy')})
    return {"status": "success"}


@router.get("/api/admin/logs/download",
            summary="Download admin audit logs",
            description="Downloads admin action logs as a plain-text file, optionally filtered by duration. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def download_admin_logs(duration: str = "all", admin_user: str = Depends(verify_admin)):
    """Download admin audit log entries as a text file.

    Args:
        duration: Filter duration ("24h", "7d", "30d", "3m", "6m", or "all").

    Returns:
        Plain-text Response with log content and Content-Disposition header.
    """
    if not await asyncio.to_thread(os.path.exists, "data/admin_actions.log"):
        return Response(content="No logs found.", media_type="text/plain")  # i18n: user-facing message (download)

    ALLOWED_DURATIONS = {"24h", "7d", "30d", "3m", "6m", "all"}
    if duration not in ALLOWED_DURATIONS:
        duration = "all"

    cutoff = None
    now = datetime.now(timezone.utc).timestamp()
    from app.audit import _RETENTION_DELTAS
    delta = _RETENTION_DELTAS.get(duration)
    if delta is not None:
        cutoff = now - delta

    def _filter_log_file():
        """Read and filter admin audit log by duration cutoff. Runs in worker thread."""
        try:
            result = []
            with open("data/admin_actions.log", "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    if cutoff is None:
                        result.append(line)
                    else:
                        try:
                            event = json.loads(line)
                            ts = event.get("ts", "")
                            log_time = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                            if log_time.timestamp() >= cutoff:
                                result.append(line)
                        except Exception:
                            result.append(line)
            return "\n".join(result)
        except FileNotFoundError:
            return ""

    content = await asyncio.to_thread(_filter_log_file)
    if not content:
        return Response(content="No logs found.", media_type="text/plain")  # i18n: user-facing message (download)
    return Response(
        content=content,
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=admin_logs_{duration}.txt"}
    )



