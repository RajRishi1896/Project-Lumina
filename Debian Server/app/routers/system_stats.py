"""System statistics and health check routes."""
import os
import re
import time
import asyncio
import logging
from fastapi import APIRouter, Depends
from app.database import _startup_time
from app.async_db import db_conn
from app.dependencies import verify_teacher, verify_admin
from app.models import TimeSync

router = APIRouter()

_stats_cache = {"data": None, "expires": 0.0}


@router.get("/stats",
            summary="Get hub statistics",
            description="Returns scholar count, resource count, subject count, disk usage, battery percentage, and server uptime.",
            tags=["System"])
async def get_stats():
    """Get aggregate hub statistics (cached for 5s).

    Returns:
        Dict with scholars, resources, subjects counts, storage info,
        battery_percent, uptime string, and disk_usage.
    """
    now = time.time()
    if _stats_cache["data"] and now < _stats_cache["expires"]:
        return _stats_cache["data"]
    import shutil
    async with db_conn() as conn:
        c = conn.cursor()
        try:
            c.execute("SELECT COUNT(*) FROM scholars")
            scholar_count = c.fetchone()[0]
        except Exception:
            scholar_count = 0
        try:
            c.execute("SELECT COUNT(*) FROM resources")
            resource_count = c.fetchone()[0]
        except Exception:
            resource_count = 0
        try:
            c.execute("SELECT COUNT(*) FROM subjects")
            subject_count = c.fetchone()[0]
        except Exception:
            subject_count = 0
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    battery_percent = 100
    try:
        if await asyncio.to_thread(os.path.exists, "/sys/class/power_supply/BAT0/capacity"):
            def _read_battery():
                """Read battery percentage from sysfs. Runs in worker thread."""
                with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
                    return int(f.read().strip())
            battery_percent = await asyncio.to_thread(_read_battery)
    except Exception:
        pass
    uptime_secs = int(time.time() - _startup_time)
    hours, rem = divmod(uptime_secs, 3600)
    mins, secs = divmod(rem, 60)
    uptime_str = f"{hours}h {mins}m" if hours else f"{mins}m {secs}s"
    du = used
    dt = total
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if du < 1024:
            used_str = f"{du:.1f} {unit}"
            total_str = f"{dt:.1f} {unit}"
            break
        du /= 1024
        dt /= 1024
    result = {"scholars": scholar_count, "resources": resource_count, "subjects": subject_count,
              "storage": f"{used_str} / {total_str}", "storage_percent": (used / total) * 100,
              "battery_percent": battery_percent, "uptime": uptime_str, "disk_usage": f"{used_str} / {total_str}"}
    _stats_cache["data"] = result
    _stats_cache["expires"] = now + 5
    return result


@router.get("/system/stats",
            summary="System health check",
            description="Simple health-check endpoint returning a healthy status. Requires teacher authentication.",
            tags=["System"],
            responses={401: {"description": "Unauthorized"}})
async def system_stats(teacher_user: str = Depends(verify_teacher)):
    """Simple system health check.

    Returns:
        Dict with status set to "healthy".
    """
    return {"status": "healthy"}


@router.post("/system/sync-time",
             summary="Sync server time",
             description="Sets the server system time via the date command. Admin-only.",
             tags=["System"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def sync_time(data: TimeSync, admin_user: str = Depends(verify_admin)):
    """Synchronise the server's system clock.

    Args:
        data: TimeSync payload with current_time in YYYY-MM-DD HH:MM:SS format.

    Returns:
        Dict with status ("ok" on success, "failed" on invalid input or error).
    """
    try:
        if not data.current_time or len(data.current_time) >= 64:
            return {"status": "failed"}
        if not re.match(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$', data.current_time):
            return {"status": "failed"}
        proc = await asyncio.create_subprocess_exec(
            "date", "-s", data.current_time,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        logging.info(f"Time Synced: {data.current_time}")
        return {"status": "ok"}
    except Exception:
        return {"status": "failed"}
