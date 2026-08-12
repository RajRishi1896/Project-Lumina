"""Database maintenance utilities.

VACUUM, ANALYZE, integrity check, orphan detection, and storage statistics.
All operations run in the DB thread pool via async_db.
"""
import os
import asyncio
from app.async_db import db_fetch, db_fetch_one, db_run
from app.database import DB_PATH, UPLOAD_DIR, THUMBNAILS_DIR


async def run_vacuum() -> dict:
    """VACUUM the database to reclaim fragmentation.

    Must run outside a transaction -- uses raw connection in thread pool.
    """
    def _vacuum():
        """Run VACUUM and report bytes reclaimed."""
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
    """ANALYZE to update query planner statistics.

    ANALYZE cannot run inside a transaction, so it uses a raw connection
    in the thread pool -- same pattern as VACUUM.
    """
    def _analyze():
        """Run ANALYZE inside the thread pool."""
        import sqlite3
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("ANALYZE")
        finally:
            conn.close()
    await asyncio.to_thread(_analyze)
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
        if not await asyncio.to_thread(os.path.exists, fpath):
            orphaned.append({"id": row[0], "filename": row[1]})
    return {"orphaned_count": len(orphaned), "orphaned": orphaned}


async def get_storage_stats() -> dict:
    """Return disk usage and DB size statistics."""
    def _stats():
        """Sum sizes of all app data directories and OS disk usage."""
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
              "courses", "course_progress", "quiz_attempts", "zim_archives",
              "zim_articles", "settings"]
    stats = {}
    for t in tables:
        try:
            result = await db_fetch_one(f"SELECT COUNT(*) FROM {t}")
            stats[t] = result[0] if result else 0
        except Exception:
            stats[t] = -1  # table doesn't exist
    return stats


async def purge_recycled_resources(days: int = 30) -> dict:
    """Purge resources soft-deleted more than ``days`` days ago.

    Removes the physical file and thumbnail (tolerant of missing files),
    deletes scholar_downloads / student_bookmarks rows, removes ZIM archive
    rows for kiwix resources, then deletes the resource row -- all in a
    single transaction. All file I/O runs in the thread pool.
    """
    def _select(conn):
        """Return resource rows deleted more than ``days`` days ago."""
        return conn.execute(
            "SELECT id, filename, resource_type FROM resources "
            "WHERE status = 'deleted' AND deleted_at IS NOT NULL "
            "AND deleted_at < datetime('now', ?)", (f"-{days} days",)).fetchall()

    rows = await db_run(_select)
    if not rows:
        return {"purged_count": 0}

    def _remove_files():
        """Delete resource files and thumbnails from disk, tolerating misses."""
        for rid, fname, _rtype in rows:
            if fname:
                try:
                    os.remove(os.path.join(UPLOAD_DIR, fname))
                except OSError:
                    pass
            try:
                os.remove(os.path.join(THUMBNAILS_DIR, f"{rid}.png"))
            except OSError:
                pass
    await asyncio.to_thread(_remove_files)

    def _cleanup(conn):
        """Delete dependent rows (downloads, bookmarks, ZIM) and the resource row."""
        ids = [(r[0],) for r in rows]
        conn.executemany("DELETE FROM scholar_downloads WHERE resource_id = ?", ids)
        conn.executemany("DELETE FROM student_bookmarks WHERE resource_id = ?", ids)
        for rid, fname, rtype in rows:
            if rtype == 'kiwix' and fname:
                zim_row = conn.execute("SELECT id FROM zim_archives WHERE filename = ?", (fname,)).fetchone()
                if zim_row:
                    conn.execute("DELETE FROM zim_articles WHERE archive_id = ?", (zim_row[0],))
                    conn.execute("DELETE FROM zim_archives WHERE id = ?", (zim_row[0],))
        conn.executemany("DELETE FROM resources WHERE id = ?", ids)
        conn.commit()
    await db_run(_cleanup)
    return {"purged_count": len(rows)}


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
