"""System statistics and health check routes."""
import os
import re
import time
import asyncio
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from app.async_db import db_conn, db_fetch_one, db_fetch
from app.dependencies import verify_teacher, verify_admin
from app.models import TimeSync, HubStatsResponse, StatusResponse

router = APIRouter()

@router.get("/stats", response_model=HubStatsResponse,
            summary="Get hub statistics",
            description="Returns scholar count, resource count, subject count, disk usage, battery percentage, and server uptime.",
            tags=["System"])
async def get_stats():
    """Get aggregate hub statistics.

    Returns:
        Dict with scholars, resources, subjects counts, storage info,
        battery_percent, uptime string, and disk_usage.
    """
    import shutil
    async with db_conn() as conn:
        c = conn.cursor()
        def _count(query):
            try:
                c.execute(query)
                return c.fetchone()[0]
            except Exception:
                return 0
        scholar_count = _count("SELECT COUNT(*) FROM scholars")
        resource_count = _count("SELECT COUNT(*) FROM resources")
        subject_count = _count("SELECT COUNT(*) FROM subjects")
        published_courses = _count("SELECT COUNT(*) FROM courses WHERE published = 1")
        draft_courses = _count("SELECT COUNT(*) FROM courses WHERE published = 0")
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
    uptime_str = "0s"
    try:
        def _read_uptime():
            """Read system uptime from /proc/uptime. Returns formatted string."""
            with open("/proc/uptime", "r") as f:
                up_secs = float(f.read().split()[0])
            h = int(up_secs // 3600)
            m = int((up_secs % 3600) // 60)
            s = int(up_secs % 60)
            parts = []
            if h: parts.append(f"{h}h")
            if m: parts.append(f"{m}m")
            if s or not parts: parts.append(f"{s}s")
            return " ".join(parts)
        uptime_str = await asyncio.to_thread(_read_uptime)
    except Exception:
        pass
    for i, unit in enumerate(['B', 'KB', 'MB', 'GB', 'TB']):
        if used < 1024 ** (i + 1):
            used_str = f"{used / 1024**i:.1f} {unit}"
            total_str = f"{total / 1024**i:.1f} {unit}"
            break
    result = {"scholars": scholar_count, "resources": resource_count, "subjects": subject_count,
              "published_courses": published_courses, "draft_courses": draft_courses,
              "storage": f"{used_str} / {total_str}", "storage_percent": (used / total) * 100,
              "battery_percent": battery_percent, "uptime": uptime_str, "disk_usage": f"{used_str} / {total_str}"}
    return result


@router.get("/system/stats", response_model=StatusResponse,
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


@router.post("/system/sync-time", response_model=StatusResponse,
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


@router.get("/healthz")
async def health():
    """Return SQLite connectivity, open FDs, RSS."""
    async with db_conn() as db:
        await asyncio.to_thread(db.execute, "SELECT 1")

    rss_mb = 0
    try:
        import resource as _resource
        rss_mb = _resource.getrusage(_resource.RUSAGE_SELF).ru_maxrss // 1024
    except (ImportError, AttributeError):
        pass
    try:
        open_fds = len(os.listdir(f"/proc/{os.getpid()}/fd"))
    except (FileNotFoundError, PermissionError):
        open_fds = -1
    return {
        "status": "ok",
        "open_fds": open_fds,
        "rss_mb": rss_mb,
    }


@router.get("/api/admin/diagnostics",
            summary="Diagnostics dashboard data",
            description="Returns comprehensive system health, metrics, and diagnostics. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def get_diagnostics(admin_user: str = Depends(verify_admin)):
    """Comprehensive diagnostics for the admin dashboard.

    Returns DB status, disk usage, resource counts, active sessions, cache
    metrics, uptime, backup status, queue sizes, and ZIM status.
    """
    from app.metrics import get_metrics
    from app.maintenance import get_storage_stats, get_table_stats

    # DB status
    db_ok = True
    db_size = 0
    try:
        result = await db_fetch_one("PRAGMA quick_check")
        db_ok = result and result[0] == "ok"
        db_stat = await asyncio.to_thread(os.stat, "data/hub.db")
        db_size = db_stat.st_size
    except Exception:
        db_ok = False

    # Storage
    storage = await get_storage_stats()
    table_stats = await get_table_stats()

    # Active sessions
    active_sessions = 0
    try:
        result = await db_fetch_one(
            "SELECT COUNT(*) FROM sessions WHERE last_accessed > datetime('now', '-1 hour')"
        )
        active_sessions = result[0] if result else 0
    except Exception:
        pass

    # Uptime
    uptime_str = "N/A"
    try:
        def _read_uptime():
            with open("/proc/uptime", "r") as f:
                up_secs = float(f.read().split()[0])
            h = int(up_secs // 3600)
            m = int((up_secs % 3600) // 60)
            s = int(up_secs % 60)
            parts = []
            if h: parts.append(f"{h}h")
            if m: parts.append(f"{m}m")
            if s or not parts: parts.append(f"{s}s")
            return " ".join(parts)
        uptime_str = await asyncio.to_thread(_read_uptime)
    except Exception:
        pass

    # Server uptime since start
    import app.api as api_module
    server_uptime = int(time.time() - getattr(api_module, "_startup_time", time.time()))

    # ZIM status
    zim_count = 0
    zim_articles = 0
    try:
        result = await db_fetch_one("SELECT COUNT(*) FROM zim_archives")
        zim_count = result[0] if result else 0
        result = await db_fetch_one("SELECT COUNT(*) FROM zim_articles")
        zim_articles = result[0] if result else 0
    except Exception:
        pass

    # Backup status (check if backup script exists)
    backup_exists = await asyncio.to_thread(os.path.exists, "backup_hub.sh")
    last_backup = None
    backup_dir = "backups"
    if await asyncio.to_thread(os.path.isdir, backup_dir):
        try:
            entries = await asyncio.to_thread(lambda: sorted(os.listdir(backup_dir)))
            if entries:
                last_backup = entries[-1]
        except Exception:
            pass

    # Pending downloads
    pending_downloads = 0
    try:
        result = await db_fetch_one("SELECT COUNT(*) FROM pending_downloads")
        pending_downloads = result[0] if result else 0
    except Exception:
        pass

    # Scheduler status
    scheduler_status = "running"

    return {
        "status": "ok" if db_ok else "degraded",
        "database": {
            "healthy": db_ok,
            "size_bytes": db_size,
            "path": "data/hub.db",
        },
        "storage": {
            "disk_total_bytes": storage["disk_total_bytes"],
            "disk_used_bytes": storage["disk_used_bytes"],
            "disk_free_bytes": storage["disk_free_bytes"],
            "app_total_bytes": storage["total_app_bytes"],
            "uploads_bytes": storage["uploads_bytes"],
            "database_bytes": storage["database_bytes"],
            "logs_bytes": storage["logs_bytes"],
            "profile_icons_bytes": storage["profile_icons_bytes"],
            "thumbnails_bytes": storage["thumbnails_bytes"],
        },
        "counts": {
            "users": table_stats.get("users", 0),
            "sessions": table_stats.get("sessions", 0),
            "resources": table_stats.get("resources", 0),
            "subjects": table_stats.get("subjects", 0),
            "grades": table_stats.get("grades", 0),
            "courses": table_stats.get("courses", 0),
            "enrollments": table_stats.get("enrollments", 0),
            "quiz_attempts": table_stats.get("quiz_attempts", 0),
            "zim_archives": zim_count,
            "zim_articles": zim_articles,
            "pending_downloads": pending_downloads,
        },
        "active_sessions": active_sessions,
        "uptime": {
            "system": uptime_str,
            "server_seconds": server_uptime,
        },
        "backup": {
            "script_exists": backup_exists,
            "last_backup": last_backup,
        },
        "scheduler": scheduler_status,
        "metrics": get_metrics(),
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/api/admin/maintenance/health",
            summary="Database health check",
            description="Runs integrity check and returns DB health status. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_health(admin_user: str = Depends(verify_admin)):
    """Run database integrity check."""
    from app.maintenance import run_integrity_check
    return await run_integrity_check()


@router.post("/api/admin/maintenance/vacuum",
             summary="VACUUM the database",
             description="Runs VACUUM to reclaim fragmentation. Admin-only.",
             tags=["System Stats"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_vacuum(admin_user: str = Depends(verify_admin)):
    """VACUUM the database."""
    from app.maintenance import run_vacuum
    return await run_vacuum()


@router.post("/api/admin/maintenance/analyze",
             summary="ANALYZE the database",
             description="Runs ANALYZE to update query planner statistics. Admin-only.",
             tags=["System Stats"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_analyze(admin_user: str = Depends(verify_admin)):
    """ANALYZE the database."""
    from app.maintenance import run_analyze
    return await run_analyze()


@router.get("/api/admin/maintenance/orphans",
            summary="Detect orphaned resources",
            description="Finds DB records with no corresponding file on disk. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_orphans(admin_user: str = Depends(verify_admin)):
    """Detect orphaned resources."""
    from app.maintenance import detect_orphans
    return await detect_orphans()


@router.get("/api/admin/maintenance/storage",
            summary="Storage statistics",
            description="Returns disk usage and per-directory sizes. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_storage(admin_user: str = Depends(verify_admin)):
    """Get storage statistics."""
    from app.maintenance import get_storage_stats
    return await get_storage_stats()


@router.get("/api/admin/maintenance/tables",
            summary="Table row counts",
            description="Returns row counts for all key tables. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_tables(admin_user: str = Depends(verify_admin)):
    """Get table row counts."""
    from app.maintenance import get_table_stats
    return await get_table_stats()


@router.post("/api/admin/maintenance/run-all",
             summary="Run full maintenance",
             description="Runs integrity check, ANALYZE, VACUUM, orphan detection, and storage stats. Admin-only.",
             tags=["System Stats"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_run_all(admin_user: str = Depends(verify_admin)):
    """Run all maintenance operations."""
    from app.maintenance import run_full_maintenance
    return await run_full_maintenance()
