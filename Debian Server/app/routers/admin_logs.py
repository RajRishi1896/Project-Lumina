"""Admin audit log and settings routes."""
import os
import asyncio
import logging
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Response
from app.database import log_admin_action, RETENTION_DELTAS
from app.async_db import db_conn
from app.models import LogRetentionUpdate, AuditLogResponse, SettingsResponse, StatusResponse
from app.dependencies import verify_admin

router = APIRouter()


@router.get("/admin/log", response_model=AuditLogResponse,
            summary="View admin audit log",
            description="Returns the most recent admin action log entries. Admin-only.",
            tags=["Admin"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def admin_log(limit: int = 20, admin_user: str = Depends(verify_admin)):
    """Read the admin audit log.

    Args:
        limit: Maximum number of log lines to return (default 20).

    Returns:
        Dict with a log list of trimmed log lines.
    """
    try:
        def _read_log():
            """Read the last N lines from the admin audit log. Runs in worker thread."""
            try:
                with open("data/admin_actions.log", "r") as f:
                    return [line.strip() for line in f.readlines()[-limit:]]
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
async def set_admin_settings(data: LogRetentionUpdate, admin_user: str = Depends(verify_admin)):
    """Update the log retention policy.

    Args:
        data: LogRetentionUpdate with a policy field.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If the policy value is not recognized.
    """
    if data.policy not in ("24h", "7d", "30d", "3m", "6m", "never", "none"):
        raise HTTPException(status_code=400, detail="Invalid log retention policy.")
    async with db_conn() as conn:
        c = conn.cursor()
        c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('log_retention', ?)", (data.policy,))
        conn.commit()
    await log_admin_action(admin_user, f"changed log retention policy to {data.policy}")
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
        return Response(content="No logs found.", media_type="text/plain")

    ALLOWED_DURATIONS = {"24h", "7d", "30d", "3m", "6m", "all"}
    if duration not in ALLOWED_DURATIONS:
        duration = "all"

    cutoff = None
    now = datetime.now().timestamp()
    delta = RETENTION_DELTAS.get(duration)
    if delta is not None:
        cutoff = now - delta

    def _filter_log_file():
        """Read and filter admin audit log by duration cutoff. Runs in worker thread."""
        try:
            result = []
            with open("data/admin_actions.log", "r") as f:
                for line in f:
                    if cutoff is None:
                        result.append(line)
                    else:
                        parts = line.split(" - ", 1)
                        try:
                            log_time = datetime.fromisoformat(parts[0])
                            if log_time.timestamp() >= cutoff:
                                result.append(line)
                        except Exception:
                            result.append(line)
            return "".join(result)
        except FileNotFoundError:
            return ""

    content = await asyncio.to_thread(_filter_log_file)
    if not content:
        return Response(content="No logs found.", media_type="text/plain")
    return Response(
        content=content,
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=admin_logs_{duration}.txt"}
    )
