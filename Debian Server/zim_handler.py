"""ZIM article router — DB-backed ZIM content with lazy asset fetching.

Provides six endpoints under the ``/zim`` prefix: archive listing, article
listing, article search, HTML page retrieval with rewritten asset paths,
thumbnail serving, and on-demand asset fetching from the ZIM binary.

Assets (images, CSS, JS, video) are NOT extracted to disk. They are read
on-demand from the persisted ``.zim`` file via ``/zim/asset``, keeping
disk usage minimal while supporting full article rendering.
"""

import os
import re
import hashlib
import sqlite3
import asyncio
import logging
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse, Response
from app.models import ZimArchiveResponse, ZimArticleResponse, ZimPageResponse
from app.async_db import db_fetch, db_fetch_one
from app.database import UPLOAD_DIR, DB_PATH

router = APIRouter()

ZIM_PAGES_DIR = os.path.join(os.path.dirname(__file__), "zim_pages")
ZIM_THUMBS_DIR = os.path.join(ZIM_PAGES_DIR, "thumbs")
os.makedirs(ZIM_PAGES_DIR, exist_ok=True)
os.makedirs(ZIM_THUMBS_DIR, exist_ok=True)

# ponytail: in-memory path→entry index per archive. Avoids O(N) linear scan
# per /zim/asset request. Cache grows ~50 bytes per entry — 10K articles = 500KB.
# Invalidate on archive delete (not implemented yet, acceptable ceiling).
_zim_path_index: dict[str, dict[str, object]] = {}

# MIME type mapping for ZIM assets
_MIME_MAP = {
    '.html': 'text/html', '.htm': 'text/html',
    '.css': 'text/css', '.js': 'application/javascript',
    '.json': 'application/json', '.xml': 'application/xml',
    '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp',
    '.ico': 'image/x-icon', '.bmp': 'image/bmp',
    '.mp4': 'video/mp4', '.webm': 'video/webm', '.ogg': 'video/ogg',
    '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.ogg': 'audio/ogg',
    '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
    '.eot': 'application/vnd.ms-fontobject',
    '.otf': 'font/otf', '.pdf': 'application/pdf',
    '.txt': 'text/plain', '.csv': 'text/csv',
}


def _get_mime(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return _MIME_MAP.get(ext, 'application/octet-stream')


def _rewrite_html_asset_paths(html: str, archive_id: str) -> str:
    """Rewrite relative src/href paths in HTML to /zim/asset URLs.

    Handles: src=, href=, poster=, data-src=, srcset= (simplified).
    Skips absolute URLs (http://, https://, data:, #, javascript:).
    """
    def _replace_attr(match):
        attr = match.group(1)
        quote = match.group(2)
        url = match.group(3)
        if url.startswith(('http://', 'https://', 'data:', '#', 'javascript:', 'mailto:')):
            return match.group(0)
        asset_path = url.lstrip('/')
        encoded = hashlib.md5(asset_path.encode()).hexdigest()[:8]
        new_url = f'/zim/asset?archive_id={archive_id}&path={asset_path}&h={encoded}'
        return f'{attr}{quote}{new_url}{quote}'

    html = re.sub(r'((?:src|href|poster|data-src)=)(["\'])([^"\']+)(["\'])',
                  _replace_attr, html)
    return html


@router.get(
    "/archives",
    summary="List all uploaded ZIM archives",
    description="Returns metadata for every ZIM archive stored in the hub database, "
                "ordered by upload time (newest first). No authentication required.",
    tags=["ZIM"],
    response_model=list[ZimArchiveResponse],
    responses={200: {"description": "List of ZIM archives"}},
)
async def list_zim_archives() -> list[ZimArchiveResponse]:
    """List all ZIM archives from the database."""
    rows = await db_fetch(
        "SELECT id, filename, title, article_count, language, uploaded_at, file_size "
        "FROM zim_archives ORDER BY uploaded_at DESC"
    )
    return [
        ZimArchiveResponse(
            id=r["id"], filename=r["filename"], title=r["title"],
            article_count=r["article_count"], language=r["language"],
            uploaded_at=r["uploaded_at"], file_size=r["file_size"],
        )
        for r in rows
    ]


@router.get(
    "/articles",
    summary="List ZIM articles with pagination (DB-backed)",
    description="Returns a paginated list of ZIM articles from the database. "
                "Optionally filter by archive_id.",
    tags=["ZIM"],
    response_model=list[ZimArticleResponse],
    responses={200: {"description": "Paginated list of articles"}},
)
async def list_zim_articles(
    archive_id: str = Query(default="", description="Filter by archive ID"),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=500),
) -> list[ZimArticleResponse]:
    """List ZIM articles from the database with optional archive filter."""
    if archive_id:
        rows = await db_fetch(
            "SELECT article_id, title, archive_id, has_thumbnail FROM zim_articles "
            "WHERE archive_id = ? ORDER BY title LIMIT ? OFFSET ?",
            (archive_id, limit, offset),
        )
    else:
        rows = await db_fetch(
            "SELECT article_id, title, archive_id, has_thumbnail FROM zim_articles "
            "ORDER BY title LIMIT ? OFFSET ?",
            (limit, offset),
        )
    return [
        ZimArticleResponse(
            article_id=r["article_id"], title=r["title"],
            archive_id=r["archive_id"] or "",
            has_thumbnail=bool(r["has_thumbnail"]),
        )
        for r in rows
    ]


@router.get(
    "/search",
    summary="Search ZIM articles by title (DB-backed)",
    description="Performs a case-insensitive substring search against ZIM article "
                "titles in the database. Optionally filter by archive_id.",
    tags=["ZIM"],
    response_model=list[ZimArticleResponse],
    responses={200: {"description": "Matching articles"}},
)
async def search_zim(
    query: str = Query(..., min_length=1, description="Search term"),
    archive_id: str = Query(default="", description="Filter by archive ID"),
) -> list[ZimArticleResponse]:
    """Search ZIM articles by title substring via SQL LIKE."""
    pattern = f"%{query}%"
    if archive_id:
        rows = await db_fetch(
            "SELECT article_id, title, archive_id, has_thumbnail FROM zim_articles "
            "WHERE title LIKE ? AND archive_id = ? ORDER BY title LIMIT 200",
            (pattern, archive_id),
        )
    else:
        rows = await db_fetch(
            "SELECT article_id, title, archive_id, has_thumbnail FROM zim_articles "
            "WHERE title LIKE ? ORDER BY title LIMIT 200",
            (pattern,),
        )
    return [
        ZimArticleResponse(
            article_id=r["article_id"], title=r["title"],
            archive_id=r["archive_id"] or "",
            has_thumbnail=bool(r["has_thumbnail"]),
        )
        for r in rows
    ]


@router.get(
    "/page",
    summary="Get a ZIM article's HTML content with rewritten asset paths",
    description="Returns the full HTML content of a single ZIM article. "
                "Relative asset paths (images, CSS, JS) are rewritten to "
                "point to /zim/asset for lazy fetching from the ZIM binary.",
    tags=["ZIM"],
    response_model=ZimPageResponse,
    responses={
        200: {"description": "Article HTML wrapped in JSON"},
        404: {"description": "Article not found"},
    },
)
async def get_zim_page(
    article_id: str = Query(..., description="The unique ID of the article to retrieve"),
):
    """Return the HTML content of a ZIM article as JSON.

    Asset paths are rewritten to ``/zim/asset?archive_id=X&path=Y`` so the
    client fetches images, CSS, and JS on-demand from the ZIM binary.
    """
    article = await db_fetch_one(
        "SELECT article_id, archive_id, title FROM zim_articles WHERE article_id = ?",
        (article_id,),
    )
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    archive_id = article["archive_id"] or ""
    title = article["title"] or ""

    # ponytail: use glob with article_id prefix instead of os.listdir on entire dir.
    # ~10K files in zim_pages/ makes os.listdir slow; glob only scans matches.
    import glob as glob_mod
    pattern = os.path.join(ZIM_PAGES_DIR, f"{article_id}__*.html")
    matches = await asyncio.to_thread(glob_mod.glob, pattern)
    if not matches:
        raise HTTPException(status_code=404, detail="Article not found")

    file_path = matches[0]
    try:
        def _read_file():
            with open(file_path, "r", encoding="utf-8") as f:
                return f.read()
        html_content = await asyncio.to_thread(_read_file)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Article not found")

    if archive_id:
        html_content = await asyncio.to_thread(
            _rewrite_html_asset_paths, html_content, archive_id
        )
    return JSONResponse(content={"id": article_id, "html": html_content})


@router.get(
    "/asset",
    summary="Fetch an asset from a ZIM archive on-demand",
    description="Reads a non-HTML asset (image, CSS, JS, video) directly from "
                "the persisted .zim binary file. No extraction to disk needed. "
                "Returns the raw bytes with the correct Content-Type.",
    tags=["ZIM"],
    responses={
        200: {"description": "Asset bytes with appropriate Content-Type"},
        404: {"description": "Asset not found in ZIM archive"},
        500: {"description": "ZIM file unavailable"},
    },
)
async def get_zim_asset(
    archive_id: str = Query(..., description="The ZIM archive ID"),
    path: str = Query(..., description="The asset path within the ZIM (e.g. I/image.png)"),
):
    """Lazy-fetch an asset from the ZIM binary.

    Opens the .zim file, looks up the entry by path, and returns its bytes.
    The file handle is not cached — each request opens/closes independently.
    This is fine for ZIM serving (low concurrency per archive).
    """
    archive_row = await db_fetch_one(
        "SELECT zim_path FROM zim_archives WHERE id = ?", (archive_id,)
    )
    if not archive_row or not archive_row["zim_path"]:
        raise HTTPException(status_code=404, detail="Archive not found or ZIM file missing.")

    zim_path = archive_row["zim_path"]
    if not await asyncio.to_thread(os.path.isfile, zim_path):
        raise HTTPException(status_code=500, detail="ZIM file not found on disk.")

    def _read_asset():
        try:
            import libzim
            index_key = f"{archive_id}:{path}"
            cached = _zim_path_index.get(index_key)
            if cached is not None:
                item = cached
            else:
                archive = libzim.Archive(zim_path)
                item = None
                for entry in archive:
                    if entry.path == path and entry.namespace != 'A':
                        item = entry
                        break
                if item is not None:
                    _zim_path_index[index_key] = item
            if item is None:
                return None, None
            item_data = item.get_item()
            data = item_data.data if hasattr(item_data, 'data') else item_data.content
            if isinstance(data, memoryview):
                data = bytes(data)
            return data, _get_mime(path)
        except ImportError:
            raise HTTPException(status_code=500, detail="ZIM parsing requires python-libzim.")
        except Exception as e:
            logging.error(f"ZIM asset fetch error: {e}")
            return None, None

    data, mime = await asyncio.to_thread(_read_asset)
    if data is None:
        raise HTTPException(status_code=404, detail="Asset not found in ZIM archive.")
    return Response(content=data, media_type=mime)


@router.get(
    "/thumbnail",
    summary="Serve an article's thumbnail image",
    description="Returns the thumbnail PNG for a ZIM article from ``zim_pages/thumbs/``. "
                "Returns 404 if no thumbnail exists.",
    tags=["ZIM"],
    responses={
        200: {"description": "Thumbnail PNG image"},
        404: {"description": "Thumbnail not found"},
    },
)
async def get_zim_thumbnail(
    article_id: str = Query(..., description="The article ID to fetch a thumbnail for"),
):
    """Serve a ZIM article thumbnail from disk."""
    thumb_path = os.path.join(ZIM_THUMBS_DIR, f"{article_id}.png")
    if await asyncio.to_thread(os.path.isfile, thumb_path):
        return FileResponse(thumb_path, media_type="image/png")
    raise HTTPException(status_code=404, detail="Thumbnail not found")
