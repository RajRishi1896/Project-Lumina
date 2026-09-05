"""System statistics and health check routes."""
import os
import asyncio
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request
from app.async_db import db_fetch_one
from app.dependencies import verify_admin
from app.models import HubStatsResponse, StatusResponse
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
    battery_percent = None
    battery_charging = False
    try:
        def _read_battery():
            """Read battery state from any sysfs power_supply battery device.

            Laptops name batteries BAT0, BAT1, BATX, CMB0, etc. and may have
            several (e.g. ThinkPad Power Bridge). Returns (None, False) when
            the machine has no battery at all (desktop, or battery removed).
            """
            import glob
            batts = []
            for d in glob.glob("/sys/class/power_supply/*"):
                tpath = os.path.join(d, "type")
                if os.path.exists(tpath):
                    with open(tpath) as f:
                        if f.read().strip() == "Battery":
                            batts.append(d)
            if not batts:
                return None, False

            def _read(d, name):
                p = os.path.join(d, name)
                if not os.path.exists(p):
                    return None
                with open(p) as f:
                    return f.read().strip()

            caps, nows, fulls, statuses = [], [], [], []
            for d in batts:
                cap = _read(d, "capacity")
                if cap is not None:
                    caps.append(int(cap))
                en, ef = _read(d, "energy_now"), _read(d, "energy_full")
                if en is not None and ef is not None and float(ef) > 0:
                    nows.append(float(en))
                    fulls.append(float(ef))
                st = _read(d, "status")
                if st:
                    statuses.append(st)
            if nows:
                pct = int(round(sum(nows) / sum(fulls) * 100))
            elif caps:
                pct = int(round(sum(caps) / len(caps)))
            else:
                return None, False
            charging = any(s in ("Charging", "Full", "Not charging") for s in statuses)
            return max(0, min(100, pct)), charging
        battery_percent, battery_charging = await asyncio.to_thread(_read_battery)
    except Exception:
        battery_percent = None
        battery_charging = False
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


@router.get("/system/time", response_model=dict, summary="Get server time", tags=["System"],
            description="Returns the server's current UTC time for client clock skew correction.",
            responses={200: {"description": "ISO 8601 server time"}})
async def get_server_time():
    """Return the server's current UTC time for client clock skew correction."""
    return {"server_time": datetime.now(timezone.utc).isoformat()}


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

        def _write_band_pref():
            try:
                os.makedirs(os.path.dirname(BAND_PREF_FILE), exist_ok=True)
                with open(BAND_PREF_FILE, "w") as f:
                    f.write(band)
            except Exception:
                pass

        await asyncio.to_thread(_write_band_pref)
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
