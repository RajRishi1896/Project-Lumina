"""Course content-version helper: single bump point for client cache invalidation."""
from app.async_db import db_exec


async def bump_course_version(course_id: str) -> None:
    """Bump a course's content version and refresh its updated_at timestamp.

    Call after every content change (resource upload, quiz create/update,
    topic create/update/delete/reorder, resource topic-assign/reorder,
    cover change) so offline clients can detect stale caches.
    """
    await db_exec(
        "UPDATE courses SET version = COALESCE(version, 1) + 1, updated_at = datetime('now') WHERE id = ?",
        (course_id,),
    )


def normalize_unlock_mode(value) -> str:
    """Return 'sequential' for a sequential opt-in, else the 'all' default."""
    return "sequential" if value == "sequential" else "all"
