"""Read-only resource catalog, detail, file listing, and upload limits routes."""
import os
import time
import shutil
import asyncio
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from app.database import UPLOAD_DIR
from app.async_db import db_fetch, db_fetch_one
from app.dependencies import verify_user, verify_teacher
from app.models import CatalogResourceResponse, FileEntryResponse, LimitsResponse

router = APIRouter()

# Catalog response cache. Keyed by the full filter tuple; entries expire after
# _CATALOG_CACHE_TTL seconds. invalidate_catalog_cache() is called from every
# resource-mutating route so uploads appear instantly in a single-worker
# deployment; the TTL bounds staleness across workers.
_catalog_cache: dict = {}
_CATALOG_CACHE_TTL = 30.0


def invalidate_catalog_cache():
    """Clear the cached catalog response. Call after any resource mutation."""
    _catalog_cache.clear()


def _catalog_item_dict(r: tuple, mtime: float) -> dict:
    """Build a catalog item dict from a resource row tuple.

    Shared by list_resources and get_resource so both return the exact same
    shape. Row layout: id, title, filename, resource_type, subject, grade,
    language, source, license, status, downloads, topic_id, topic_name,
    page_count, duration_seconds, file_size.
    """
    return {
        "id": r[0], "title": r[1],
        "pdfUrl": f"/files/{os.path.basename(r[2])}" if r[2] else "",
        "type": r[3], "subject": r[4] or "General",
        "grade": str(r[5]) if r[5] is not None else "", "mtime": mtime,
        "downloads": r[10] if len(r) > 10 else 0,
        "topic_name": r[12] if len(r) > 12 else "",
        "page_count": r[13] if len(r) > 13 else 0,
        "duration_seconds": r[14] if len(r) > 14 else 0,
        "file_size": r[15] if len(r) > 15 else 0,
    }


@router.get("/resources", response_model=list[CatalogResourceResponse],
            summary="List all resources", tags=["Resources"],
            description="Lists approved resources with combined filters (subject, grade, language, resource_type, title search). Deprecated/deleted items are excluded by default.",
            responses={401: {"description": "Unauthorized"}})
@router.get("/api/catalog", response_model=list[CatalogResourceResponse],
            summary="List all resources (alias)", tags=["Resources"],
            description="Alias of GET /resources for the Flutter client catalog sync.",
            responses={401: {"description": "Unauthorized"}})
async def list_resources(
    _: str = Depends(verify_user),
    subject: Optional[str] = Query(None, description="Filter by subject"),
    grade: Optional[int] = Query(None, description="Filter by grade"),
    language: Optional[str] = Query(None, description="Filter by language (ISO 639-1)"),
    resource_type: Optional[str] = Query(None, description="Filter by resource type"),
    search: Optional[str] = Query(None, description="Search by title substring"),
    include_deprecated: bool = Query(False, description="Include deprecated resources"),
    include_kiwix: bool = Query(False, description="Include kiwix/ZIM archive resources"),
):
    """List approved resources with optional filters.

    Supports combined filtering by subject, grade, language, resource_type,
    and title substring.  Deprecated and deleted (recycle bin) resources are
    excluded by default; ``include_deprecated`` shows both.
    File modification times are batched into a single thread call.
    """
    cache_key = (
        subject, grade, language, resource_type, search,
        include_deprecated, include_kiwix,
    )
    now = time.time()
    hit = _catalog_cache.get(cache_key)
    if hit and now - hit[0] < _CATALOG_CACHE_TTL:
        return hit[1]

    conditions = []
    params = []
    if not include_deprecated:
        conditions.append("r.status NOT IN ('deprecated', 'deleted')")
    if not include_kiwix:
        conditions.append("r.resource_type != 'kiwix'")
    if subject:
        if subject == "General":
            conditions.append("(r.subject = 'General' OR r.grade = 'General')")
        else:
            conditions.append("r.subject = ?")
            params.append(subject)
    if grade is not None:
        # Grade 'General' means "all grades" -- include it in any grade filter
        conditions.append("(r.grade = ? OR r.grade = 'General')")
        params.append(grade)
    if language:
        conditions.append("r.language = ?")
        params.append(language)
    if resource_type:
        conditions.append("r.resource_type = ?")
        params.append(resource_type)
    if search:
        conditions.append("title LIKE ?")
        params.append(f"%{search}%")
    where_clause = ""
    if conditions:
        where_clause = " WHERE " + " AND ".join(conditions)

    query = f"""SELECT r.id, r.title, r.filename, r.resource_type, r.subject, r.grade, r.language, r.source, r.license, r.status,
        COALESCE(sd.dl_count, 0) AS downloads, r.topic_id,
        COALESCE(rt.name, '') AS topic_name,
        r.page_count, r.duration_seconds, r.file_size
        FROM resources r
        LEFT JOIN (SELECT resource_id, COUNT(*) AS dl_count FROM scholar_downloads GROUP BY resource_id) sd
            ON sd.resource_id = r.id
        LEFT JOIN resource_topics rt ON rt.id = r.topic_id
        {where_clause}"""
    rows = await db_fetch(query, tuple(params))

    def _get_all_mtimes():
        """Batch stat every listed file in one call (avoids N+1)."""
        mtimes = {}
        for r in rows:
            try:
                full_path = os.path.join(UPLOAD_DIR, r[2]) if r[2] else None
                mtimes[r[0]] = os.path.getmtime(full_path) if full_path and os.path.exists(full_path) else 0.0
            except OSError:
                mtimes[r[0]] = 0.0
        return mtimes

    mtimes = await asyncio.to_thread(_get_all_mtimes)
    result = []
    for r in rows:
        result.append(_catalog_item_dict(r, mtimes.get(r[0], 0.0)))
    _catalog_cache[cache_key] = (now, result)
    return result


@router.get("/resources/{resource_id}", response_model=CatalogResourceResponse,
            summary="Get a single resource by ID", tags=["Resources"],
            description="Returns one approved resource by its ID (kiwix included; recycled/deprecated excluded). Used by the Flutter resource detail page when navigating with only a resource ID.",
            responses={401: {"description": "Unauthorized"}, 404: {"description": "Resource not found"}})
async def get_resource(resource_id: str, _: str = Depends(verify_user)):
    """Fetch a single resource by id for the Flutter detail page.

    Returns the same catalog item shape as list_resources so the client
    model parses identically. Single file stat runs in a worker thread.
    """
    row = await db_fetch_one(
        """SELECT r.id, r.title, r.filename, r.resource_type, r.subject, r.grade, r.language, r.source, r.license, r.status,
           COALESCE(sd.dl_count, 0) AS downloads, r.topic_id,
           COALESCE(rt.name, '') AS topic_name,
           r.page_count, r.duration_seconds, r.file_size
           FROM resources r
           LEFT JOIN (SELECT resource_id, COUNT(*) AS dl_count FROM scholar_downloads GROUP BY resource_id) sd
               ON sd.resource_id = r.id
           LEFT JOIN resource_topics rt ON rt.id = r.topic_id
           WHERE r.id = ? AND r.status NOT IN ('deprecated', 'deleted')""",
        (resource_id,))
    if row is None:
        raise HTTPException(status_code=404, detail="Resource not found")
    mtime = 0.0
    if row[2]:
        full_path = os.path.join(UPLOAD_DIR, row[2])
        try:
            mtime = await asyncio.to_thread(os.path.getmtime, full_path)
        except OSError:
            mtime = 0.0
    return _catalog_item_dict(row, mtime)


@router.get("/api/files", response_model=list[FileEntryResponse],
            summary="List uploaded files", tags=["Resources"],
            description="Lists every file in uploads/ with its size, for the content manager.",
            responses={401: {"description": "Unauthorized"}})
async def list_files(teacher_user: str = Depends(verify_teacher)):
    """List all uploaded files in the uploads directory with sizes.

    Runs the directory scan in a worker thread to avoid blocking the
    event loop.
    """
    if not os.path.exists(UPLOAD_DIR):
        return []
    return await asyncio.to_thread(lambda: [
        {"name": f, "size": os.path.getsize(os.path.join(UPLOAD_DIR, f))}
        for f in os.listdir(UPLOAD_DIR)
        if os.path.isfile(os.path.join(UPLOAD_DIR, f))
    ])


@router.get("/api/limits", response_model=LimitsResponse,
            summary="Get upload limits", tags=["Resources"],
            description="Returns the max ZIM upload size: free disk space minus a 2 GB safety reserve.",
            responses={401: {"description": "Unauthorized"}})
async def get_limits(teacher_user: str = Depends(verify_teacher)):
    """Return the maximum allowed ZIM upload size in bytes.

    Calculated as free disk space minus a 2 GB safety reserve.
    """
    _, _, free = await asyncio.to_thread(shutil.disk_usage, "/")
    return {"zim_upload_max_size": max(0, free - 2 * 1024 * 1024 * 1024)}