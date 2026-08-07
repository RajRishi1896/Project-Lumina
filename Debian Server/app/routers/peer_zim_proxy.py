"""ZIM peer receive: signed local search for paired hubs.

Paired hubs call this endpoint during fan-out search (see
zim_handler._merge_peer_search); the results are merged into the caller's
own /zim/search response. No student-facing routes live here -- student
traffic goes through the single /zim/* flow, and peer-hosted content is
routed by zim_handler via peer: prefixed ids.
"""

from fastapi import APIRouter, Depends, Query

from app.models import ZimSearchResponse
from app.peer_sync import verify_peer_sig
from zim_handler import _search_local

router = APIRouter()


@router.get(
    "/peer/zim/search",
    tags=["Federation"],
    summary="Search local ZIM articles for a paired peer",
    description="Signed. Mirrors /zim/search for paired peers with the same ranking and pagination.",
    response_model=ZimSearchResponse,
    responses={401: {"description": "Invalid peer signature"}},
)
async def peer_zim_search(
    query: str = Query(..., min_length=1, description="Search term"),
    archive_id: str = Query(default="", description="Filter by archive ID"),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
    peer: dict = Depends(verify_peer_sig),
) -> ZimSearchResponse:
    """Run a local ranked ZIM title search for a paired peer.

    Deliberately calls ``_search_local``, not the public ``search_zim`` --
    the public route fans out to peers, which would recurse back into this
    endpoint forever.

    Args:
        query: Search term (short queries return empty results).
        archive_id: Restrict to a single archive, or empty for all.
        offset: Pagination offset.
        limit: Maximum results (1-100).
        peer: The authenticated peer row.

    Returns:
        A ZimSearchResponse with matching articles, total, offset, and has_more.

    Raises:
        HTTPException: 401 when the request is not properly signed.
    """
    return await _search_local(query, archive_id, offset, limit)
