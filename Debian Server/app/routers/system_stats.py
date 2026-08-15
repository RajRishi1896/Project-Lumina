"""System statistics and health check routes."""
import os
import re
import time
import asyncio
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request
from app.async_db import db_fetch_one, db_fetch
from app.dependencies import verify_teacher, verify_admin
from app.models import TimeSync, HubStatsResponse, StatusResponse
from app.audit import audit, Action

router = APIRouter()

BAND_PREF_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "data", "band_pref.txt")
_wifi_caps: list[str] = []


async def detect_wifi_caps():
    """Detect WiFi adapter capabilities at startup (before hotspot is busy)."""
    global _wifi_caps
    try:
        proc = await asyncio.create_subprocess_exec(
            "/usr/sbin/iw", "list",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
        text = stdout.decode()
        caps = []
        if "Band 1" in text:
            caps.append("bg")
        if "Band 2" in text:
            caps.append("a")
        _wifi_caps = caps or ["bg"]
        logging.info(f"WiFi capabilities detected: {_wifi_caps}")
    except Exception as e:
        logging.warning(f"detect_wifi_caps failed, defaulting to [bg]: {e}")
        _wifi_caps = ["bg"]

@router.get("/stats", response_model=HubStatsResponse,
            summary="Get hub statistics",
            description="Returns scholar count, resource count, subject count, disk usage, battery percentage, and server uptime.",
            tags=["System"],
            responses={200: {"description": "Aggregate hub statistics"}})
async def get_stats():
    """Get aggregate hub statistics.

    Returns:
        Dict with scholars, resources, subjects counts, storage info,
        battery_percent, uptime string, and disk_usage.
    """
    import shutil
    async def _count(query):
        """Run a COUNT query, returning 0 when the table is missing."""
        try:
            row = await db_fetch_one(query)
            return row[0] if row else 0
        except Exception:
            return 0
    scholar_count = await _count("SELECT COUNT(*) FROM scholars")
    resource_count = await _count("SELECT COUNT(*) FROM resources")
    subject_count = await _count("SELECT COUNT(*) FROM subjects")
    published_courses = await _count("SELECT COUNT(*) FROM courses WHERE published = 1")
    draft_courses = await _count("SELECT COUNT(*) FROM courses WHERE published = 0")
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    battery_percent = 100
    battery_charging = False
    try:
        if await asyncio.to_thread(os.path.exists, "/sys/class/power_supply/BAT0/capacity"):
            def _read_battery():
                """Read battery percentage and charging status from sysfs."""
                with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
                    pct = int(f.read().strip())
                charging = False
                try:
                    with open("/sys/class/power_supply/BAT0/status", "r") as f:
                        charging = f.read().strip() == "Charging"
                except Exception:
                    pass
                return pct, charging
            battery_percent, battery_charging = await asyncio.to_thread(_read_battery)
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
              "battery_percent": battery_percent, "battery_charging": battery_charging,
              "uptime": uptime_str, "disk_usage": f"{used_str} / {total_str}"}
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


@router.get("/system/time", response_model=dict, summary="Get server time", tags=["System"],
            description="Returns the server's current UTC time for client clock skew correction.",
            responses={200: {"description": "ISO 8601 server time"}})
async def get_server_time():
    """Return the server's current UTC time for client clock skew correction."""
    return {"server_time": datetime.now(timezone.utc).isoformat()}


@router.get("/healthz", response_model=dict,
            summary="Deep health check",
            description="Returns SQLite connectivity, open file descriptor count, and RSS in MB. Used by the admin diagnostics page.",
            tags=["System Stats"],
            responses={200: {"description": "Health details"}, 500: {"description": "Database unreachable"}})
async def health():
    """Return SQLite connectivity, open FDs, RSS."""
    await db_fetch_one("SELECT 1")

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


@router.get("/api/admin/diagnostics", response_model=dict,
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
            """Read /proc/uptime and format it as a compact duration string."""
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


@router.get("/api/admin/maintenance/health", response_model=dict,
            summary="Database health check",
            description="Runs integrity check and returns DB health status. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_health(admin_user: str = Depends(verify_admin)):
    """Run database integrity check."""
    from app.maintenance import run_integrity_check
    return await run_integrity_check()


@router.post("/api/admin/maintenance/vacuum", response_model=dict,
             summary="VACUUM the database",
             description="Runs VACUUM to reclaim fragmentation. Admin-only.",
             tags=["System Stats"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_vacuum(admin_user: str = Depends(verify_admin)):
    """VACUUM the database."""
    from app.maintenance import run_vacuum
    return await run_vacuum()


@router.post("/api/admin/maintenance/analyze", response_model=dict,
             summary="ANALYZE the database",
             description="Runs ANALYZE to update query planner statistics. Admin-only.",
             tags=["System Stats"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_analyze(admin_user: str = Depends(verify_admin)):
    """ANALYZE the database."""
    from app.maintenance import run_analyze
    return await run_analyze()


@router.get("/api/admin/maintenance/orphans", response_model=dict,
            summary="Detect orphaned resources",
            description="Finds DB records with no corresponding file on disk. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_orphans(admin_user: str = Depends(verify_admin)):
    """Detect orphaned resources."""
    from app.maintenance import detect_orphans
    return await detect_orphans()


@router.get("/api/admin/maintenance/storage", response_model=dict,
            summary="Storage statistics",
            description="Returns disk usage and per-directory sizes. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_storage(admin_user: str = Depends(verify_admin)):
    """Get storage statistics."""
    from app.maintenance import get_storage_stats
    return await get_storage_stats()


@router.get("/api/admin/maintenance/tables", response_model=dict,
            summary="Table row counts",
            description="Returns row counts for all key tables. Admin-only.",
            tags=["System Stats"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_tables(admin_user: str = Depends(verify_admin)):
    """Get table row counts."""
    from app.maintenance import get_table_stats
    return await get_table_stats()


@router.post("/api/admin/maintenance/run-all", response_model=dict,
             summary="Run full maintenance",
             description="Runs integrity check, ANALYZE, VACUUM, orphan detection, and storage stats. Admin-only.",
             tags=["System Stats"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def maintenance_run_all(admin_user: str = Depends(verify_admin)):
    """Run all maintenance operations."""
    from app.maintenance import run_full_maintenance
    return await run_full_maintenance()


@router.get("/system/wifi-band", response_model=dict,
            summary="Get current WiFi band and capabilities",
            description="Returns the current WiFi hotspot band and supported bands. Admin-only.",
            tags=["System"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def get_wifi_band(admin_user: str = Depends(verify_admin)):
    """Get the current WiFi hotspot band and adapter capabilities.

    Returns:
        Dict with band, label, and supported_bands list.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            "nmcli", "-t", "-f", "802-11-wireless.band", "connection", "show", "LuminaHub",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, _ = await proc.communicate()
        band_raw = stdout.decode().strip()
        band = band_raw.split(":")[-1] if ":" in band_raw else band_raw

        supported = list(_wifi_caps) if _wifi_caps else ["bg"]

        return {
            "band": band or "bg",
            "label": "5 GHz" if band == "a" else "2.4 GHz",
            "supported": supported
        }
    except Exception as e:
        logging.error(f"get_wifi_band: {e}")
        return {"band": "bg", "label": "2.4 GHz", "supported": ["bg"]}


@router.post("/system/wifi-band", response_model=StatusResponse,
             summary="Switch WiFi band",
             description="Switches the hotspot between 5GHz and 2.4GHz. The hotspot restarts and clients reconnect. Admin-only.",
             tags=["System"],
             responses={400: {"description": "Invalid band or switch failed"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def set_wifi_band(request: Request, admin_user: str = Depends(verify_admin)):
    """Switch the WiFi hotspot band.

    Body:
        {"band": "a"} for 5GHz or {"band": "bg"} for 2.4GHz.

    Returns:
        Dict with status and the new band.
    """
    try:
        body = await request.json()
        band = body.get("band", "")
        if band not in ("a", "bg"):
            raise HTTPException(status_code=400, detail="Invalid band. Use 'a' for 5GHz or 'bg' for 2.4GHz.")
        channel = "149" if band == "a" else "1"
        wifi_if_proc = await asyncio.create_subprocess_exec(
            "nmcli", "-t", "-f", "DEVICE,TYPE", "device",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, _ = await wifi_if_proc.communicate()
        wifi_if = ""
        for line in stdout.decode().strip().split("\n"):
            parts = line.split(":")
            if len(parts) == 2 and parts[1] == "wifi":
                wifi_if = parts[0]
                break
        if not wifi_if:
            raise HTTPException(status_code=400, detail="No WiFi interface found.")
        cmds = [
            ["nmcli", "connection", "modify", "LuminaHub", f"802-11-wireless.band", band],
        ]
        if channel:
            cmds.append(["nmcli", "connection", "modify", "LuminaHub", "802-11-wireless.channel", channel])
        cmds.extend([
            ["nmcli", "device", "disconnect", wifi_if],
            ["nmcli", "connection", "up", "LuminaHub"],
        ])
        for cmd in cmds:
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            await proc.communicate()
        label = "5 GHz" if band == "a" else "2.4 GHz"
        try:
            os.makedirs(os.path.dirname(BAND_PREF_FILE), exist_ok=True)
            with open(BAND_PREF_FILE, "w") as f:
                f.write(band)
        except Exception:
            pass
        await audit(Action.WIFI_BAND_CHANGE, admin_user, severity="notice",
                     changes={"band": band, "label": label}, request=request)
        logging.info(f"WiFi band switched to {label} by {admin_user}. Rebooting.")
        # Reboot to apply the band change cleanly
        asyncio.get_event_loop().call_later(
            2.0,
            lambda: asyncio.ensure_future(_do_reboot())
        )
        return {"status": "success", "band": band, "label": label, "message": f"Switched to {label}. Server rebooting."}
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"set_wifi_band: {e}")
        raise HTTPException(status_code=400, detail="Failed to switch WiFi band.")


@router.post("/system/reboot", response_model=StatusResponse,
             summary="Reboot the server",
             description="Initiates a system reboot after a 2-second delay. Admin-only.",
             tags=["System"],
             responses={401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def reboot_server(request: Request, admin_user: str = Depends(verify_admin)):
    """Reboot the server.

    Schedules a reboot with a 2-second delay so the response is sent first.
    """
    try:
        await audit(Action.SERVER_REBOOT, admin_user, severity="notice", request=request)
        logging.info(f"Server reboot initiated by {admin_user}.")
        asyncio.get_event_loop().call_later(
            2.0,
            lambda: asyncio.ensure_future(
                _do_reboot()
            )
        )
        return {"status": "success", "message": "Server is rebooting. Reconnect in ~60 seconds."}
    except Exception as e:
        logging.error(f"reboot_server: {e}")
        raise HTTPException(status_code=500, detail="Failed to initiate reboot.")


async def _do_reboot():
    """Run the actual reboot command."""
    proc = await asyncio.create_subprocess_exec(
        "sudo", "/sbin/shutdown", "-r", "now",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    await proc.communicate()
