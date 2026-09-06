"""Recycle-bin purge for soft-deleted resources.

Runs in the DB thread pool via async_db; file I/O via asyncio.to_thread.
"""
import os
import asyncio
from app.async_db import db_run
from app.database import UPLOAD_DIR, THUMBNAILS_DIR


async def purge_recycled_resources(days: int = 30) -> dict:
    """Purge resources soft-deleted more than ``days`` days ago.

    Removes the physical file and thumbnail (tolerant of missing files),
    deletes scholar_downloads / student_bookmarks rows, removes ZIM archive
    rows for kiwix resources (using zim_path for the physical file), then
    deletes the resource row, all in a single transaction. All file I/O
    runs in the thread pool.
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

    # Collect ZIM paths before cleanup so we can delete the actual .zim files
    def _collect_zim_paths(conn):
        """Return {resource_filename: zim_path} for kiwix resources."""
        zim_map = {}
        for rid, fname, rtype in rows:
            if rtype == 'kiwix' and fname:
                zim_row = conn.execute("SELECT id, zim_path FROM zim_archives WHERE filename = ?", (fname,)).fetchone()
                if zim_row:
                    zim_map[fname] = zim_row[1]  # zim_path
        return zim_map

    zim_paths = await db_run(_collect_zim_paths)

    def _remove_files():
        """Delete resource files, thumbnails, and ZIM archives from disk, tolerating misses."""
        for rid, fname, _rtype in rows:
            if fname:
                try:
                    os.remove(os.path.join(UPLOAD_DIR, fname))
                except OSError:
                    pass
                # Also remove ZIM archive by its actual stored path
                zim_path = zim_paths.get(fname)
                if zim_path:
                    try:
                        os.remove(zim_path)
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
