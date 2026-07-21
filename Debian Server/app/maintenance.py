"""Database maintenance utilities.

VACUUM, ANALYZE, integrity check, orphan detection, and storage statistics.
All operations run in the DB thread pool via async_db.
"""
import os
import asyncio
from app.async_db import db_fetch, db_fetch_one, db_run
from app.database import DB_PATH


async def run_vacuum() -> dict:
    """VACUUM the database to reclaim fragmentation.

    Must run outside a transaction -- uses raw connection in thread pool.
    """
    def _vacuum():
        import sqlite3
        conn = sqlite3.connect(DB_PATH)
        try:
            size_before = os.path.getsize(DB_PATH)
            conn.execute("VACUUM")
            size_after = os.path.getsize(DB_PATH)
            return {
                "success": True,
                "size_before_bytes": size_before,
                "size_after_bytes": size_after,
                "freed_bytes": size_before - size_after,
            }
        finally:
            conn.close()
    return await asyncio.to_thread(_vacuum)


async def run_analyze() -> dict:
    """ANALYZE to update query planner statistics."""
    await db_fetch_one("ANALYZE")
    return {"success": True, "message": "ANALYZE completed"}


async def run_integrity_check() -> dict:
    """Run PRAGMA integrity_check."""
    result = await db_fetch_one("PRAGMA integrity_check")
    status = result[0] if result else "unknown"
    return {"success": status == "ok", "status": status}


async def detect_orphans() -> dict:
    """Detect orphaned resources (DB records with no file on disk).

    Returns list of resource IDs whose filename is missing from uploads/.
    """
    rows = await db_fetch("SELECT id, filename FROM resources WHERE filename IS NOT NULL")
    orphaned = []
    for row in rows:
        fpath = os.path.join("uploads", row[1])
        if not os.path.exists(fpath):
            orphaned.append({"id": row[0], "filename": row[1]})
    return {"orphaned_count": len(orphaned), "orphaned": orphaned}


async def get_storage_stats() -> dict:
    """Return disk usage and DB size statistics."""
    def _stats():
        import sqlite3
        db_size = os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0

        uploads_size = 0
        uploads_dir = "uploads"
        if os.path.isdir(uploads_dir):
            for f in os.listdir(uploads_dir):
                fp = os.path.join(uploads_dir, f)
                if os.path.isfile(fp):
                    uploads_size += os.path.getsize(fp)

        profile_size = 0
        icons_dir = "profile_icons"
        if os.path.isdir(icons_dir):
            for f in os.listdir(icons_dir):
                fp = os.path.join(icons_dir, f)
                if os.path.isfile(fp):
                    profile_size += os.path.getsize(fp)

        thumbnails_size = 0
        thumbs_dir = "thumbnails"
        if os.path.isdir(thumbs_dir):
            for f in os.listdir(thumbs_dir):
                fp = os.path.join(thumbs_dir, f)
                if os.path.isfile(fp):
                    thumbnails_size += os.path.getsize(fp)

        log_size = 0
        for f in ("data/hub.log", "data/admin_actions.log"):
            if os.path.exists(f):
                log_size += os.path.getsize(f)

        # Disk usage from OS
        try:
            st = os.statvfs(".")
            disk_total = st.f_blocks * st.f_frsize
            disk_free = st.f_bavail * st.f_frsize
            disk_used = disk_total - disk_free
        except (AttributeError, OSError):
            # Windows / unsupported -- skip
            disk_total = disk_used = disk_free = 0

        return {
            "database_bytes": db_size,
            "uploads_bytes": uploads_size,
            "profile_icons_bytes": profile_size,
            "thumbnails_bytes": thumbnails_size,
            "logs_bytes": log_size,
            "total_app_bytes": db_size + uploads_size + profile_size + thumbnails_size + log_size,
            "disk_total_bytes": disk_total,
            "disk_used_bytes": disk_used,
            "disk_free_bytes": disk_free,
        }

    return await asyncio.to_thread(_stats)


async def get_table_stats() -> dict:
    """Return row counts for key tables."""
    tables = ["users", "sessions", "resources", "subjects", "grades",
              "courses", "enrollments", "quiz_attempts", "zim_archives",
              "zim_articles", "pending_downloads", "activity", "settings"]
    stats = {}
    for t in tables:
        try:
            result = await db_fetch_one(f"SELECT COUNT(*) FROM {t}")
            stats[t] = result[0] if result else 0
        except Exception:
            stats[t] = -1  # table doesn't exist
    return stats


async def run_full_maintenance() -> dict:
    """Run all maintenance operations and return combined report."""
    results = {}

    results["integrity"] = await run_integrity_check()
    if results["integrity"]["success"]:
        results["analyze"] = await run_analyze()
        results["vacuum"] = await run_vacuum()
    else:
        results["analyze"] = {"skipped": True, "reason": "integrity check failed"}
        results["vacuum"] = {"skipped": True, "reason": "integrity check failed"}

    results["orphans"] = await detect_orphans()
    results["storage"] = await get_storage_stats()
    results["tables"] = await get_table_stats()

    return results
