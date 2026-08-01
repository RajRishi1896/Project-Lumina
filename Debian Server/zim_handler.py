"""ZIM article router -- fully lazy ZIM content serving.

All articles and assets are served on-demand from the .zim binary.
No HTML extraction to disk. The database stores article metadata
(title, path) for search; content is always read from the ZIM file.

Endpoints:
    /archives       -- list all ZIM archives
    /articles       -- paginated article browsing
    /search         -- ranked title search with pagination
    /page           -- article HTML with rewritten asset paths
    /asset          -- on-demand asset (image/CSS/JS) from ZIM binary
    /thumbnail      -- thumbnail image from disk cache
"""

import os
import re
import time
import hashlib
import asyncio
import logging
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse, Response
from app.models import ZimArchiveResponse, ZimArticleResponse, ZimPageResponse, ZimSearchResponse
from app.async_db import db_fetch, db_fetch_one
from app.database import UPLOAD_DIR, DB_PATH

router = APIRouter()

ZIM_THUMBS_DIR = os.path.join(os.path.dirname(__file__), "zim_pages", "thumbs")
os.makedirs(ZIM_THUMBS_DIR, exist_ok=True)

# ponytail: archive_id -> libzim.Archive cache. Archive objects are lightweight
# (header-only open, ~0s even for 124GB). Keeps fd open for repeated lookups.
_archive_cache: dict[str, object] = {}

# ponytail: path->entry index per asset request. Avoids get_entry_by_path
# overhead for hot asset paths. Not needed for articles (low per-request variance).
_asset_cache: dict[str, object] = {}
_ASSET_CACHE_MAX = 500

# ponytail: cached article counts. COUNT(*) on 19M rows takes ~1s;
# this avoids it on every browse request. Refreshed every 60s.
_article_count_cache: dict[str, int] = {}
_article_count_ts: dict[str, float] = {}
_COUNT_CACHE_TTL = 60


def _cache_put(key, value):
    if len(_asset_cache) >= _ASSET_CACHE_MAX:
        # ponytail: evict oldest entry, not LRU. Good enough for static assets.
        _asset_cache.pop(next(iter(_asset_cache)))
    _asset_cache[key] = value


def invalidate_zim_cache(archive_id: str) -> None:
    """Remove all cached entries for a ZIM archive."""
    _archive_cache.pop(archive_id, None)
    _article_count_cache.pop(archive_id, None)
    _article_count_ts.pop(archive_id, None)
    prefix = f"{archive_id}:"
    keys_to_delete = [k for k in _asset_cache if k.startswith(prefix)]
    for k in keys_to_delete:
        _asset_cache.pop(k, None)
    if keys_to_delete:
        logging.info(f"Invalidated {len(keys_to_delete)} asset cache entries for archive {archive_id}")


_MIME_MAP = {
    '.html': 'text/html', '.htm': 'text/html',
    '.css': 'text/css', '.js': 'application/javascript',
    '.json': 'application/json', '.xml': 'application/xml',
    '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp',
    '.ico': 'image/x-icon', '.bmp': 'image/bmp',
    '.mp4': 'video/mp4', '.webm': 'video/webm', '.ogg': 'video/ogg',
    '.mp3': 'audio/mpeg', '.wav': 'audio/wav',
    '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
    '.eot': 'application/vnd.ms-fontobject',
    '.otf': 'font/otf', '.pdf': 'application/pdf',
    '.txt': 'text/plain', '.csv': 'text/csv',
}


def _get_mime(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return _MIME_MAP.get(ext, 'application/octet-stream')


def _rewrite_html_asset_paths(html: str, archive_id: str, base_url: str = '') -> str:
    """Rewrite relative asset paths in HTML to absolute /zim/asset URLs.

    Handles src, href, poster, data-src attributes, srcset (responsive images),
    and CSS url() references in inline styles and <style> blocks.
    Produces absolute URLs (base_url + /zim/asset?...) to avoid WebView
    baseUrl resolution issues with loadHtmlString.
    """
    def _make_zim_url(asset_path: str) -> str:
        asset_path = asset_path.lstrip('/')
        encoded = hashlib.md5(asset_path.encode()).hexdigest()[:8]
        return f'{base_url}/zim/asset?archive_id={archive_id}&path={asset_path}&h={encoded}'

    def _replace_attr(match):
        attr = match.group(1)
        quote = match.group(2)
        url = match.group(3)
        if url.startswith(('http://', 'https://', 'data:', '#', 'javascript:', 'mailto:')):
            return match.group(0)
        return f'{attr}{quote}{_make_zim_url(url)}{quote}'

    html = re.sub(r'((?:src|href|poster|data-src)=)(["\'])([^"\']+)(["\'])',
                  _replace_attr, html)

    def _replace_srcset(match):
        attr = match.group(1)
        value = match.group(2)
        def _rewrite_url(m):
            url = m.group(1).strip()
            desc = m.group(2) or ''
            if url.startswith(('http://', 'https://', 'data:', '#', 'javascript:', 'mailto:')):
                return m.group(0)
            return f'{_make_zim_url(url)}{desc}'
        rewritten = re.sub(r'(\S+)(\s+\d+[wx])?', _rewrite_url, value)
        return f'{attr}{rewritten}'

    html = re.sub(r'(srcset=)(["\'])([^"\']+)(["\'])', _replace_srcset, html)

    def _replace_css_url(match):
        prefix = match.group(1)
        url = match.group(2)
        suffix = match.group(3)
        if url.startswith(('http://', 'https://', 'data:', '#', 'javascript:', 'mailto:')):
            return match.group(0)
        return f'{prefix}{_make_zim_url(url)}{suffix}'

    html = re.sub(r"""(url\()(["']?)([^"')]+)(\2)""", _replace_css_url, html)
    return html


def _get_archive(archive_id: str, zim_path: str):
    """Get a cached libzim.Archive or open a new one."""
    cached = _archive_cache.get(archive_id)
    if cached is not None:
        return cached
    import libzim
    archive = libzim.Archive(zim_path)
    _archive_cache[archive_id] = archive
    return archive


# ── Search ranking ───────────────────────────────────────────────────

# ponytail: FTS5 trigram tokenizer requires queries >= 3 chars.
# Shorter queries return empty results (no useful trigrams).
_MIN_SEARCH_LEN = 3

# ponytail: ranking CASE expression for 19M Wikipedia rows.
# Uses TRIM() for robustness against whitespace variations in titles.
#   rank 0: exact title match (case-sensitive -- "Python" beats "PYTHON")
#   rank 1: case-insensitive exact match (with TRIM)
#   rank 2: title starts with query (prefix match)
#   rank 3: disambiguation -- title = "query (something)" e.g. "India (disambiguation)"
#   rank 4: query is a complete word boundary (surrounded by spaces or at start/end)
#   rank 5: title ends with query as a word
#   rank 6: FTS trigram substring match (weakest)
# ORDER BY rank, LENGTH(title), title ensures deterministic pagination.
_RANK_CASE = """
    CASE
      WHEN TRIM(za.title) = TRIM(?) THEN 0
      WHEN LOWER(TRIM(za.title)) = LOWER(TRIM(?)) THEN 1
      WHEN LOWER(TRIM(za.title)) LIKE LOWER(TRIM(?)) || '%%' THEN 2
      WHEN LOWER(TRIM(za.title)) LIKE LOWER(TRIM(?)) || ' (%%' THEN 3
      WHEN LOWER(TRIM(za.title)) LIKE '%% ' || LOWER(TRIM(?)) || ' %%' THEN 4
      WHEN LOWER(TRIM(za.title)) LIKE '%% ' || LOWER(TRIM(?)) THEN 5
      ELSE 6
    END
"""


def _fts_quote(query: str) -> str:
    """Wrap query in double quotes for FTS5 trigram literal matching.

    The trigram tokenizer interprets certain characters (+, *, -, etc.) as
    FTS5 query operators. Wrapping in double quotes forces literal matching.
    """
    return '"' + query.replace('"', '""') + '"'


async def _check_fts() -> bool:
    """Check if zim_articles_fts table exists AND has data.

    The table may exist but be empty if the FTS5 build was interrupted
    (e.g. ANALYZE hung before the commit). In that case, callers should
    fall back to LIKE-based search.
    """
    import sqlite3 as _sqlite3
    try:
        conn = _sqlite3.connect(DB_PATH)
        try:
            row = conn.execute("SELECT COUNT(*) FROM zim_articles_fts").fetchone()
            return row is not None and row[0] > 0
        except _sqlite3.OperationalError:
            return False
        finally:
            conn.close()
    except Exception:
        return False


# ── Endpoints ────────────────────────────────────────────────────────


@router.get(
    "/archives",
    summary="List all uploaded ZIM archives",
    tags=["ZIM"],
    response_model=list[ZimArchiveResponse],
)
async def list_zim_archives() -> list[ZimArchiveResponse]:
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
    summary="Browse ZIM articles with pagination",
    description="Returns articles in stable alphabetical order. "
                "Use offset to paginate. Filter by archive_id to scope results.",
    tags=["ZIM"],
    response_model=ZimSearchResponse,
)
async def list_zim_articles(
    archive_id: str = Query(default="", description="Filter by archive ID"),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=500),
) -> ZimSearchResponse:
    where = "WHERE za.namespace = 'A'"
    params: list = []
    if archive_id:
        where += " AND za.archive_id = ?"
        params.append(archive_id)

    cache_key = archive_id or "_all"
    now = time.time()
    cached_ts = _article_count_ts.get(cache_key, 0)
    if cache_key in _article_count_cache and (now - cached_ts) < _COUNT_CACHE_TTL:
        total = _article_count_cache[cache_key]
    else:
        count_row = await db_fetch_one(
            f"SELECT COUNT(*) as cnt FROM zim_articles za {where}", tuple(params)
        )
        total = count_row["cnt"] if count_row else 0
        _article_count_cache[cache_key] = total
        _article_count_ts[cache_key] = now

    rows = await db_fetch(
        f"SELECT za.article_id, za.title, za.archive_id, za.has_thumbnail "
        f"FROM zim_articles za {where} "
        f"ORDER BY za.title LIMIT ? OFFSET ?",
        (*params, limit, offset),
    )
    articles = [
        ZimArticleResponse(
            article_id=r["article_id"], title=r["title"],
            archive_id=r["archive_id"] or "",
            has_thumbnail=bool(r["has_thumbnail"]),
        )
        for r in rows
    ]
    return ZimSearchResponse(
        articles=articles,
        total=total,
        offset=offset,
        has_more=(offset + len(articles)) < total,
    )


@router.get(
    "/search",
    summary="Search ZIM articles by title with relevance ranking",
    description="Server-side ranked search using FTS5 trigram index. "
                "Results ordered by: exact match, case-insensitive exact, "
                "prefix, disambiguation, word boundary, word suffix, FTS substring. "
                "Quotes query for safe FTS matching. Queries < 3 chars return empty.",
    tags=["ZIM"],
    response_model=ZimSearchResponse,
)
async def search_zim(
    query: str = Query(..., min_length=1, description="Search term"),
    archive_id: str = Query(default="", description="Filter by archive ID"),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
) -> ZimSearchResponse:
    # Normalize: trim, collapse repeated whitespace, skip empty
    query = " ".join(query.split())
    if len(query) < _MIN_SEARCH_LEN:
        return ZimSearchResponse(articles=[], total=0, offset=offset, has_more=False)

    has_fts = await _check_fts()
    fts_query = _fts_quote(query)

    if has_fts:
        where_fts = "zim_articles_fts MATCH ?"
        base_params: list = [fts_query]
        if archive_id:
            where_fts += " AND za.archive_id = ?"
            base_params.append(archive_id)

        count_row = await db_fetch_one(
            f"SELECT COUNT(*) as cnt FROM zim_articles za "
            f"JOIN zim_articles_fts fts ON za.id = fts.rowid "
            f"WHERE {where_fts}",
            tuple(base_params),
        )
        total = count_row["cnt"] if count_row else 0

        rank_params = [query, query, query, query, query, query]
        rows = await db_fetch(
            f"SELECT za.article_id, za.title, za.archive_id, za.has_thumbnail, "
            f"  {_RANK_CASE} as rank "
            f"FROM zim_articles za "
            f"JOIN zim_articles_fts fts ON za.id = fts.rowid "
            f"WHERE {where_fts} "
            f"ORDER BY rank, LENGTH(za.title), za.title "
            f"LIMIT ? OFFSET ?",
            (*rank_params, *base_params, limit, offset),
        )
    else:
        pattern = f"%{query}%"
        where = "WHERE za.title LIKE ?"
        base_params = [pattern]
        if archive_id:
            where += " AND za.archive_id = ?"
            base_params.append(archive_id)

        count_row = await db_fetch_one(
            f"SELECT COUNT(*) as cnt FROM zim_articles za {where}",
            tuple(base_params),
        )
        total = count_row["cnt"] if count_row else 0

        rows = await db_fetch(
            f"SELECT za.article_id, za.title, za.archive_id, za.has_thumbnail "
            f"FROM zim_articles za {where} "
            f"ORDER BY LENGTH(za.title), za.title "
            f"LIMIT ? OFFSET ?",
            (*base_params, limit, offset),
        )

    articles = [
        ZimArticleResponse(
            article_id=r["article_id"], title=r["title"],
            archive_id=r["archive_id"] or "",
            has_thumbnail=bool(r["has_thumbnail"]),
        )
        for r in rows
    ]
    return ZimSearchResponse(
        articles=articles,
        total=total,
        offset=offset,
        has_more=(offset + len(articles)) < total,
    )


@router.get(
    "/page",
    summary="Get a ZIM article's HTML content",
    tags=["ZIM"],
    response_model=ZimPageResponse,
    responses={200: {"description": "Article HTML"}, 404: {"description": "Article not found"}},
)
async def get_zim_page(
    article_id: str = Query(..., description="The article ID to retrieve"),
    request=None,
):
    """Read article HTML directly from the ZIM binary.

    Looks up the article path in the DB, opens the ZIM archive,
    reads the HTML content, and rewrites asset paths to absolute
    /zim/asset URLs using the request's base URL.
    """
    from starlette.requests import Request
    article = await db_fetch_one(
        "SELECT article_id, archive_id, title, path FROM zim_articles WHERE article_id = ?",
        (article_id,),
    )
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    archive_id = article["archive_id"] or ""
    title = article["title"] or ""
    article_path = article["path"] or ""

    if not article_path:
        raise HTTPException(status_code=404, detail="Article path missing from index")

    archive_row = await db_fetch_one(
        "SELECT zim_path FROM zim_archives WHERE id = ?", (archive_id,)
    )
    if not archive_row or not archive_row["zim_path"]:
        raise HTTPException(status_code=404, detail="Archive not found")

    zim_path = archive_row["zim_path"]
    if not await asyncio.to_thread(os.path.isfile, zim_path):
        raise HTTPException(status_code=500, detail="ZIM file missing from disk")

    def _read_article():
        try:
            archive = _get_archive(archive_id, zim_path)
            if not archive.has_entry_by_path(article_path):
                return None
            entry = archive.get_entry_by_path(article_path)
            if entry.is_redirect:
                entry = entry.get_redirect_entry()
            item = entry.get_item()
            data = item.content if hasattr(item, 'content') else (item.data if hasattr(item, 'data') else b'')
            if isinstance(data, memoryview):
                data = bytes(data)
            return data.decode('utf-8', errors='replace')
        except Exception as e:
            logging.error(f"ZIM article read error: {e}")
            return None

    html_content = await asyncio.to_thread(_read_article)
    if html_content is None:
        raise HTTPException(status_code=404, detail="Article not found in ZIM archive")

    base_url = ''
    if request is not None:
        base_url = str(request.base_url).rstrip('/')
    html_content = await asyncio.to_thread(
        _rewrite_html_asset_paths, html_content, archive_id, base_url
    )
    return JSONResponse(content={"id": article_id, "html": html_content})


@router.get(
    "/asset",
    summary="Fetch an asset from a ZIM archive on-demand",
    description="Reads a non-HTML asset directly from the .zim binary. "
                "Returns the raw bytes with the correct Content-Type.",
    tags=["ZIM"],
    responses={200: {"description": "Asset bytes"}, 404: {"description": "Asset not found"}},
)
async def get_zim_asset(
    archive_id: str = Query(..., description="The ZIM archive ID"),
    path: str = Query(..., description="The asset path within the ZIM"),
):
    """Lazy-fetch an asset from the ZIM binary using get_entry_by_path."""
    archive_row = await db_fetch_one(
        "SELECT zim_path FROM zim_archives WHERE id = ?", (archive_id,)
    )
    if not archive_row or not archive_row["zim_path"]:
        raise HTTPException(status_code=404, detail="Archive not found")

    zim_path = archive_row["zim_path"]
    if not await asyncio.to_thread(os.path.isfile, zim_path):
        raise HTTPException(status_code=500, detail="ZIM file missing from disk")

    def _read_asset():
        try:
            index_key = f"{archive_id}:{path}"
            cached = _asset_cache.get(index_key)
            if cached is not None:
                return cached, _get_mime(path)
            archive = _get_archive(archive_id, zim_path)
            if not archive.has_entry_by_path(path):
                return None, None
            entry = archive.get_entry_by_path(path)
            if entry.is_redirect:
                entry = entry.get_redirect_entry()
            item = entry.get_item()
            data = item.content if hasattr(item, 'content') else (item.data if hasattr(item, 'data') else b'')
            if isinstance(data, memoryview):
                data = bytes(data)
            _cache_put(index_key, data)
            return data, _get_mime(path)
        except Exception as e:
            logging.error(f"ZIM asset fetch error: {e}")
            return None, None

    data, mime = await asyncio.to_thread(_read_asset)
    if data is None:
        raise HTTPException(status_code=404, detail="Asset not found in ZIM archive")
    return Response(content=data, media_type=mime, headers={"Cache-Control": "public, max-age=86400"})


@router.get(
    "/thumbnail",
    summary="Serve an article's thumbnail image",
    tags=["ZIM"],
)
async def get_zim_thumbnail(
    article_id: str = Query(..., description="The article ID"),
):
    thumb_path = os.path.join(ZIM_THUMBS_DIR, f"{article_id}.png")
    if await asyncio.to_thread(os.path.isfile, thumb_path):
        return FileResponse(thumb_path, media_type="image/png", headers={"Cache-Control": "public, max-age=86400"})
    raise HTTPException(status_code=404, detail="Thumbnail not found")
