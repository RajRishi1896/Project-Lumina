"""Hourly background refresh of paired peers' resource catalogs.

Every ``interval_seconds`` (default 3600), for each paired peer: fetch its
signed ``/peer/catalog``, replace the peer's cached rows in
``peer_resources`` inside one transaction, and bump ``last_catalog_sync``
and ``last_seen``. Failures are logged and left for the next pass -- a hub
that is offline keeps its last known catalog, so students still see the
peer's resources even while the peer hub is down.

The same refresh function is reused by the admin "Sync now" endpoint in
``app/routers/federation.py``.
"""

import asyncio
import logging

from app.async_db import db_run
from app.peer_sync import PeerManager, get_peers

logger = logging.getLogger("lumina.peer")


async def refresh_peer_resources(peer: dict) -> int:
    """Fetch and replace one peer's cached resource rows.

    Args:
        peer: The peer row from the ``peers`` table.

    Returns:
        The number of resources cached.

    Raises:
        Exception: Any network or database failure is left to the caller
            so the hourly loop can log and continue.
    """
    items = await PeerManager().request_catalog(peer)

    def _replace_catalog(conn):
        """Swap the peer's cached rows for the freshly fetched catalog."""
        conn.execute("DELETE FROM peer_resources WHERE peer_id = ?", (peer["id"],))
        conn.executemany(
            """INSERT OR REPLACE INTO peer_resources
               (peer_id, peer_resource_id, title, subject, grade, language,
                resource_type, file_size, page_count, duration_seconds, mtime)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            [
                (
                    peer["id"], str(item["id"]), item.get("title") or "",
                    item.get("subject") or "General", item.get("grade") or "",
                    item.get("language") or "en", item.get("resource_type") or "textbook",
                    int(item.get("file_size") or 0), int(item.get("page_count") or 0),
                    int(item.get("duration_seconds") or 0), float(item.get("mtime") or 0.0),
                )
                for item in items
            ],
        )
        conn.execute(
            "UPDATE peers SET last_catalog_sync = datetime('now'), last_seen = datetime('now') WHERE id = ?",
            (peer["id"],),
        )
        conn.commit()

    await db_run(_replace_catalog)
    logger.info("Peer %s catalog refreshed: %d resources", peer.get("name"), len(items))
    return len(items)


async def peer_refresh_loop(interval_seconds: int = 3600) -> None:
    """Background task: refresh every paired peer's catalog on an interval.

    Args:
        interval_seconds: Seconds between passes. Set to 0 to run once
            (useful for tests); the loop sleeps after each pass.
    """
    while True:
        await asyncio.sleep(interval_seconds)
        for peer in await get_peers():
            try:
                await refresh_peer_resources(peer)
            except Exception as exc:
                logger.warning(
                    "Peer refresh failed for %s (%s): %s",
                    peer.get("name"), peer.get("base_url"), exc,
                )
