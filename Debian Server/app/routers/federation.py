"""Hub federation: /peer/* signing endpoints and admin peer management.

Two Lumina hubs on the same LAN pair using a 6-digit code. After pairing
they exchange only *approved* resources -- student data never crosses.

Peer-facing endpoints (signed with X-Peer-* headers after pairing):
    GET /peer/hello              -- public, reachability check
    POST /peer/pair              -- public, code-gated pairing
    GET /peer/pairing-code       -- admin-only, shows our current code
    GET /peer/catalog            -- signed, approved resources only
    GET /peer/file/{id}          -- signed, Range-aware file serving
    GET /peer/zim/page|asset|thumbnail
                                 -- signed, local ZIM content for a peer

Student-facing proxy:
    GET /peer/file/{peer_id}/{peer_resource_id}
                                 -- Range-forwards bytes from a paired hub

Admin endpoints (session auth):
    GET    /api/peers            -- list paired peers
    POST   /api/peers/pair       -- pair with {ip, port, code}
    DELETE /api/peers/{id}       -- unpair
    GET    /api/peers/discover   -- mDNS browse for EduMeshHub services
    POST   /api/peers/{id}/sync  -- trigger a catalog refresh now

Peer ZIM content reaches students through the same /zim/* endpoints as
local content: article and archive ids are namespaced peer:{peer_id}:{id}
and zim_handler proxies pages, assets, and thumbnails back to the owning
hub (peer catalog still excludes kiwix resources from peer_refresh).
"""

import asyncio
import logging
import os
import socket
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, Response, StreamingResponse

from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.database import UPLOAD_DIR
from app.dependencies import verify_admin
from app.peer_refresh import refresh_peer_resources
from app.peer_sync import (
    PeerManager,
    _stream_local_file,
    discover_peers_blocking,
    fetch_file,
    get_peer,
    get_peers,
    handle_pair_request,
    verify_peer_sig,
)

router = APIRouter()
peer_manager = PeerManager()
logger = logging.getLogger("lumina.federation")


@router.get(
    "/peer/hello",
    tags=["Federation"],
    summary="Identify this hub to another hub",
    description="Public. Lets a pairing hub confirm this hub is reachable and learn its name.",
    response_model=dict,
    responses={200: {"description": "Hub name and pairing nonce"}},
)
async def peer_hello():
    """Public -- no auth. Name + nonce used during the pairing handshake."""
    return {"name": socket.gethostname(), "nonce": uuid.uuid4().hex}


@router.post(
    "/peer/pair",
    tags=["Federation"],
    summary="Accept a pairing request from another hub",
    description="Public but gated by the 6-digit pairing code shown in this hub's Settings > Peer Hubs. The code itself is never sent -- the peer proves knowledge of it via a key-confirmation MAC over its public key.",
    response_model=dict,
    responses={400: {"description": "Missing key_proof or public_key"}, 403: {"description": "Wrong or expired pairing code"}},
)
async def peer_pair(request: Request, payload: dict):
    """Verify the pairing proof, store the peer, and return our key proof.

    Args:
        request: Incoming request -- name comes from the X-Peer-Name header,
            IP from the client address.
        payload: JSON body with ``key_proof`` and ``public_key``.

    Returns:
        Dict with ``ok``, ``public_key`` (ours), ``key_proof``, and ``id``.

    Raises:
        HTTPException: 400 for missing fields, 403 for a wrong proof.
    """
    key_proof = str(payload.get("key_proof") or "")
    public_key = str(payload.get("public_key") or "")
    if not key_proof or not public_key:
        raise HTTPException(status_code=400, detail="key_proof and public_key are required")
    name = request.headers.get("x-peer-name") or None
    client_ip = request.client.host if request.client else "unknown"
    return await handle_pair_request(key_proof, public_key, name, client_ip)


@router.get(
    "/peer/pairing-code",
    tags=["Federation"],
    summary="Get this hub's current pairing code",
    description="Admin only. Generates a fresh 6-digit code when none is active; expires after 10 minutes.",
    response_model=dict,
    responses={401: {"description": "Not authenticated"}, 403: {"description": "Admin role required"}},
)
async def pairing_code(_: str = Depends(verify_admin)):
    """Return the active pairing code, generating one on demand."""
    code = peer_manager.current_pairing_code()
    if code is None:
        code = peer_manager.generate_pairing_code()
    return {"code": code, "expires_in": 600}


@router.get(
    "/peer/catalog",
    tags=["Federation"],
    summary="List approved resources for a paired peer",
    description="Signed. Returns only approved, non-kiwix resources -- never student data, uploaders, or pending/deprecated items.",
    response_model=list[dict],
    responses={401: {"description": "Missing or invalid peer signature"}},
)
async def peer_catalog(peer: dict = Depends(verify_peer_sig)):
    """Serve the approved resource catalog to a paired peer.

    File mtimes are batched into a single thread call (N+1 rule).
    """
    rows = await db_fetch(
        """SELECT id, title, subject, grade, language, resource_type, file_size,
                  page_count, duration_seconds, filename, original_name
           FROM resources WHERE status = 'approved' AND resource_type != 'kiwix'"""
    )

    def _get_all_mtimes():
        """Batch stat all catalog files in one call (avoids N+1)."""
        mtimes = {}
        for r in rows:
            try:
                full_path = os.path.join(UPLOAD_DIR, r["filename"]) if r["filename"] else None
                mtimes[r["filename"]] = os.path.getmtime(full_path) if full_path and os.path.exists(full_path) else 0.0
            except OSError:
                mtimes[r["filename"]] = 0.0
        return mtimes

    mtimes = await asyncio.to_thread(_get_all_mtimes)
    return [
        {
            "id": r["id"], "title": r["title"], "subject": r["subject"] or "General",
            "grade": r["grade"], "language": r["language"], "resource_type": r["resource_type"],
            "file_size": r["file_size"] or 0, "page_count": r["page_count"] or 0,
            "duration_seconds": r["duration_seconds"] or 0,
            "mtime": mtimes.get(r["filename"], 0.0),
            "original_name": r["original_name"] or "",
        }
        for r in rows
    ]


@router.get(
    "/peer/file/{resource_id}",
    tags=["Federation"],
    summary="Serve a local file to a paired peer",
    description="Signed. Range-aware streaming of an approved local resource file.",
    responses={401: {"description": "Invalid peer signature"}, 404: {"description": "Resource or file not found"}},
)
async def peer_file(resource_id: str, request: Request, peer: dict = Depends(verify_peer_sig)):
    """Serve an approved local resource file to a paired peer with Range support."""
    row = await db_fetch_one(
        "SELECT filename FROM resources WHERE id = ? AND status = 'approved'",
        (resource_id,),
    )
    if not row or not row["filename"]:
        raise HTTPException(status_code=404, detail="Resource not found")
    return await _stream_local_file(
        os.path.join(UPLOAD_DIR, row["filename"]), request.headers.get("range")
    )


@router.get(
    "/peer/zim/page",
    tags=["Federation"],
    summary="Serve a local ZIM article to a paired peer",
    description="Signed. Mirrors /zim/page for paired peers; asset paths are rewritten to this hub's public /zim/asset URLs.",
    responses={401: {"description": "Invalid peer signature"}, 404: {"description": "Article not found"}},
)
async def peer_zim_page(request: Request, article_id: str, peer: dict = Depends(verify_peer_sig)):
    """Read a ZIM article's HTML and rewrite asset paths for the peer."""
    from zim_handler import _rewrite_html_asset_paths, _get_archive
    article = await db_fetch_one(
        "SELECT archive_id, path FROM zim_articles WHERE article_id = ?", (article_id,)
    )
    if not article or not article["path"]:
        raise HTTPException(status_code=404, detail="Article not found")
    archive_row = await db_fetch_one(
        "SELECT zim_path FROM zim_archives WHERE id = ?", (article["archive_id"],)
    )
    if not archive_row or not archive_row["zim_path"]:
        raise HTTPException(status_code=404, detail="Archive not found")

    def _read_article():
        """Read the article HTML from the .zim archive, following redirects."""
        try:
            archive = _get_archive(article["archive_id"], archive_row["zim_path"])
            if not archive.has_entry_by_path(article["path"]):
                return None
            entry = archive.get_entry_by_path(article["path"])
            if entry.is_redirect:
                entry = entry.get_redirect_entry()
            item = entry.get_item()
            data = item.content if hasattr(item, "content") else (item.data if hasattr(item, "data") else b"")
            return bytes(data).decode("utf-8", errors="replace") if not isinstance(data, str) else data
        except Exception as exc:
            logger.error("Peer ZIM page read error: %s", exc)
            return None

    html = await asyncio.to_thread(_read_article)
    if html is None:
        raise HTTPException(status_code=404, detail="Article not found in ZIM archive")
    base_url = str(request.base_url).rstrip("/")
    html = await asyncio.to_thread(_rewrite_html_asset_paths, html, article["archive_id"], base_url)
    return JSONResponse(content={"id": article_id, "html": html})


@router.get(
    "/peer/zim/asset",
    tags=["Federation"],
    summary="Serve a local ZIM asset to a paired peer",
    description="Signed. Mirrors /zim/asset for paired peers.",
    responses={401: {"description": "Invalid peer signature"}, 404: {"description": "Asset not found"}},
)
async def peer_zim_asset(archive_id: str, path: str, peer: dict = Depends(verify_peer_sig)):
    """Read a non-HTML ZIM asset from the archive for a paired peer."""
    from zim_handler import _get_archive, _get_mime
    archive_row = await db_fetch_one(
        "SELECT zim_path FROM zim_archives WHERE id = ?", (archive_id,)
    )
    if not archive_row or not archive_row["zim_path"]:
        raise HTTPException(status_code=404, detail="Archive not found")

    def _read_asset():
        """Read the raw asset bytes from the .zim archive, following redirects."""
        try:
            archive = _get_archive(archive_id, archive_row["zim_path"])
            if not archive.has_entry_by_path(path):
                return None
            entry = archive.get_entry_by_path(path)
            if entry.is_redirect:
                entry = entry.get_redirect_entry()
            item = entry.get_item()
            data = item.content if hasattr(item, "content") else (item.data if hasattr(item, "data") else b"")
            return bytes(data) if not isinstance(data, bytes) else data
        except Exception as exc:
            logger.error("Peer ZIM asset read error: %s", exc)
            return None

    data = await asyncio.to_thread(_read_asset)
    if data is None:
        raise HTTPException(status_code=404, detail="Asset not found in ZIM archive")
    return Response(content=data, media_type=_get_mime(path), headers={"Cache-Control": "public, max-age=86400"})


@router.get(
    "/peer/zim/thumbnail",
    tags=["Federation"],
    summary="Serve a local ZIM article thumbnail to a paired peer",
    description="Signed. Mirrors /zim/thumbnail for paired peers.",
    responses={401: {"description": "Invalid peer signature"}, 404: {"description": "Thumbnail not found"}},
)
async def peer_zim_thumbnail(article_id: str, peer: dict = Depends(verify_peer_sig)):
    """Read an article's thumbnail from the on-disk cache for a paired peer."""
    from zim_handler import ZIM_THUMBS_DIR
    thumb_path = os.path.join(ZIM_THUMBS_DIR, f"{article_id}.png")
    if await asyncio.to_thread(os.path.isfile, thumb_path):
        return FileResponse(thumb_path, media_type="image/png", headers={"Cache-Control": "public, max-age=86400"})
    raise HTTPException(status_code=404, detail="Thumbnail not found")


@router.get(
    "/peer/file/{peer_id}/{peer_resource_id}",
    tags=["Federation"],
    summary="Stream a resource from a paired hub to this hub's students",
    description="Looks up the cached peer resource, then Range-forwards the student's request to the peer hub and streams bytes back.",
    responses={404: {"description": "Peer resource not found"}, 410: {"description": "Peer no longer paired"}},
)
async def peer_proxy_file(peer_id: str, peer_resource_id: str, request: Request):
    """Proxy a file from a paired hub, forwarding the client's Range header."""
    row = await db_fetch_one(
        "SELECT peer_id FROM peer_resources WHERE peer_id = ? AND peer_resource_id = ?",
        (peer_id, peer_resource_id),
    )
    if not row:
        raise HTTPException(status_code=404, detail="Peer resource not found")
    peer = await get_peer(peer_id)
    if not peer or not peer.get("public_key"):
        raise HTTPException(status_code=410, detail="Peer hub is no longer paired")
    status, headers, body = await fetch_file(peer, peer_resource_id, request.headers.get("range"))
    return StreamingResponse(body, status_code=status, media_type="application/octet-stream", headers=headers)


@router.get(
    "/api/peers",
    tags=["Federation"],
    summary="List paired peers",
    description="Admin only. Includes each peer's cached resource count and last sync time.",
    response_model=list[dict],
    responses={401: {"description": "Not authenticated"}, 403: {"description": "Admin role required"}},
)
async def list_peers(_: str = Depends(verify_admin)):
    """Return paired peers with resource counts for the Settings page."""
    peers = await get_peers()
    counts = await db_fetch("SELECT peer_id, COUNT(*) AS n FROM peer_resources GROUP BY peer_id")
    count_map = {r["peer_id"]: r["n"] for r in counts}
    return [
        {
            "id": p["id"], "name": p["name"], "base_url": p["base_url"],
            "last_sync": p["last_catalog_sync"], "last_seen": p["last_seen"],
            "resource_count": count_map.get(p["id"], 0),
        }
        for p in peers
    ]


@router.post(
    "/api/peers/pair",
    tags=["Federation"],
    summary="Pair with another hub",
    description="Admin only. Takes {ip, port, code}; the code is the 6-digit code shown on the other hub's Settings page.",
    response_model=dict,
    responses={400: {"description": "Missing ip or code"}, 403: {"description": "Invalid pairing code"}, 502: {"description": "Peer unreachable"}},
)
async def api_pair(payload: dict, _: str = Depends(verify_admin)):
    """Pair with the hub at the given address using its pairing code."""
    ip = str(payload.get("ip") or "").strip()
    code = str(payload.get("code") or "").strip()
    try:
        port = int(payload.get("port") or 8000)
    except (TypeError, ValueError):
        port = 8000
    if not ip or not code:
        raise HTTPException(status_code=400, detail="ip and code are required")
    return await peer_manager.pair(f"{ip}:{port}", code)


@router.delete(
    "/api/peers/{peer_id}",
    tags=["Federation"],
    summary="Unpair a peer",
    description="Admin only. Removes the peer and its cached resources.",
    response_model=dict,
    responses={401: {"description": "Not authenticated"}, 403: {"description": "Admin role required"}},
)
async def unpair_peer(peer_id: str, _: str = Depends(verify_admin)):
    """Remove a paired peer and all its cached resources."""
    def _unpair(conn):
        """Delete the peer row and its cached resources in one transaction."""
        conn.execute("DELETE FROM peers WHERE id = ?", (peer_id,))
        conn.execute("DELETE FROM peer_resources WHERE peer_id = ?", (peer_id,))
        conn.commit()
    await db_run(_unpair)
    logger.info("Unpaired peer %s", peer_id)
    return {"status": "ok"}


@router.get(
    "/api/peers/discover",
    tags=["Federation"],
    summary="Discover hubs on the LAN",
    description="Admin only. Browses mDNS for EduMeshHub services, excluding this host. Returns [{name, ip, port}].",
    response_model=list[dict],
    responses={401: {"description": "Not authenticated"}, 403: {"description": "Admin role required"}},
)
async def discover(_: str = Depends(verify_admin)):
    """Browse the LAN for EduMeshHub mDNS advertisements."""
    return await asyncio.to_thread(discover_peers_blocking)


@router.post(
    "/api/peers/{peer_id}/sync",
    tags=["Federation"],
    summary="Trigger an immediate catalog refresh for a peer",
    description="Admin only. Fetches the peer's catalog now and replaces its cached resources.",
    response_model=dict,
    responses={401: {"description": "Not authenticated"}, 403: {"description": "Admin role required"}, 404: {"description": "Peer not found"}},
)
async def sync_peer(peer_id: str, _: str = Depends(verify_admin)):
    """Refresh one peer's cached catalog immediately."""
    peer = await get_peer(peer_id)
    if not peer:
        raise HTTPException(status_code=404, detail="Peer not found")
    count = await refresh_peer_resources(peer)
    return {"status": "ok", "resource_count": count}
