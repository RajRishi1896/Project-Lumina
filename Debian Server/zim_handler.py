"""ZIM article router — serves cached HTML pages extracted from ZIM archives.

Provides three endpoints under the ``/zim`` prefix for listing, searching,
and retrieving individual ZIM articles. Articles are stored as flat HTML
files in ``zim_pages/`` using the naming convention ``<id>__<title>.html``.
"""

import os
import asyncio
import logging
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from app.models import ZimArticleResponse, ZimPageResponse

router = APIRouter()

# Directory where ZIM article HTML files are stored (server side)
ZIM_PAGES_DIR = os.path.join(os.path.dirname(__file__), "zim_pages")
os.makedirs(ZIM_PAGES_DIR, exist_ok=True)


@router.get(
    "/articles",
    summary="List ZIM articles with pagination",
    description="Returns a paginated list of all cached ZIM articles. Each entry "
                "contains an ``article_id`` and a human-readable ``title`` derived "
                "from the filename.",
    tags=["ZIM"],
    response_model=list[ZimArticleResponse],
    responses={
        200: {"description": "Paginated list of articles"},
    },
)
async def list_zim_articles(offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=200)) -> list[ZimArticleResponse]:
    """List all ZIM articles with pagination.

    Scans the ``zim_pages`` directory for ``.html`` files and parses
    each filename to extract the article ID and title.

    Args:
        offset: Number of articles to skip (for pagination).
        limit: Maximum number of articles to return (default 20, max 200).

    Returns:
        A list of dicts with keys ``article_id`` and ``title``.
    """
    results: list[dict[str, str]] = []
    try:
        entries = await asyncio.to_thread(os.listdir, ZIM_PAGES_DIR)
        entries = sorted(entries)
    except FileNotFoundError:
        return results
    for fname in entries:
        if fname.endswith('.html'):
            parts = fname.rsplit('__', 1)
            if len(parts) == 2:
                article_id, title_part = parts
                title = title_part.rsplit('.html', 1)[0]
                results.append({"article_id": article_id, "title": title})
    return results[offset:offset + limit]


@router.get(
    "/search",
    summary="Search ZIM articles by title",
    description="Performs a case-insensitive substring search against cached ZIM "
                "article titles. Returns matching articles with their ID and title.",
    tags=["ZIM"],
    response_model=list[ZimArticleResponse],
    responses={
        200: {"description": "Matching articles"},
    },
)
async def search_zim(query: str = Query(..., min_length=1, description="Search term to match against article titles")) -> list[ZimArticleResponse]:
    """Search ZIM articles by title substring.

    Returns a list of objects with ``article_id`` and ``title``.

    Args:
        query: The search term (case-insensitive substring match).

    Returns:
        A list of matching article dicts, or an empty list if no matches
        or the directory is missing.
    """
    results: list[dict[str, str]] = []
    # Simple filename based search; assume files are named "<id>__<title>.html"
    try:
        entries = await asyncio.to_thread(os.listdir, ZIM_PAGES_DIR)
    except FileNotFoundError:
        return results
    for fname in entries:
        if fname.endswith('.html'):
            parts = fname.rsplit('__', 1)
            if len(parts) == 2:
                article_id, title_part = parts
                title = title_part.rsplit('.html', 1)[0]
                if query.lower() in title.lower():
                    results.append({"article_id": article_id, "title": title})
    return results


@router.get(
    "/page",
    summary="Get a ZIM article's HTML content",
    description="Returns the full HTML content of a single ZIM article as a JSON "
                "object. The server looks up the file by ``article_id`` using the "
                "``<id>__*.html`` naming pattern.",
    tags=["ZIM"],
    response_model=ZimPageResponse,
    responses={
        200: {"description": "Article HTML wrapped in JSON", "content": {"application/json": {}}},
        404: {"description": "Article not found"},
    },
)
async def get_zim_page(article_id: str = Query(..., description="The unique ID of the article to retrieve")):
    """Return the HTML content of a ZIM article as JSON.

    The server looks for a file named ``<id>__*.html`` on disk and
    returns its raw HTML string inside a JSON body.

    Args:
        article_id: The unique identifier for the article.

    Returns:
        JSON with keys ``id`` and ``html``.

    Raises:
        HTTPException 404: If no file matching the ID is found.
    """
    try:
        entries = await asyncio.to_thread(os.listdir, ZIM_PAGES_DIR)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail='Article not found')
    for fname in entries:
        if fname.startswith(f"{article_id}__") and fname.endswith('.html'):
            file_path = os.path.join(ZIM_PAGES_DIR, fname)
            try:
                def _read_file():
                    with open(file_path, 'r', encoding='utf-8') as f:
                        return f.read()
                html_content = await asyncio.to_thread(_read_file)
            except FileNotFoundError:
                continue
            return JSONResponse(content={'id': article_id, 'html': html_content})
    raise HTTPException(status_code=404, detail='Article not found')
