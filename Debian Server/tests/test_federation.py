"""Tests for hub federation: pairing, request signing, and admin endpoints.

Follows the conftest fixtures (temp DB, client, admin_client). The signing
helpers in app.peer_sync are exercised both directly (unit-style, no
network) and end-to-end through a paired /peer/catalog request. Peer ZIM
tests cover the signed receive side plus the merged /zim/* student flow
(peer-namespaced ids proxy to paired hubs; unpaired hubs are 404s).
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.api import app
from app.async_db import db_exec
from app.peer_sync import PeerManager, derive_shared_secret, signed_headers
from zim_handler import _split_peer_id

peer_manager = PeerManager()


@pytest.mark.asyncio
async def test_pairing_code_requires_admin(client):
    """The pairing-code endpoint must reject anonymous requests."""
    resp = await client.get("/peer/pairing-code")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_hello_is_public(client):
    """GET /peer/hello must work without any authentication."""
    resp = await client.get("/peer/hello")
    assert resp.status_code == 200
    data = resp.json()
    assert data["name"]
    assert data["nonce"]


@pytest.mark.asyncio
async def test_pair_rejects_wrong_code(client):
    """POST /peer/pair with a wrong 6-digit code must return 403."""
    resp = await client.post("/peer/pair", json={"code": "000000", "public_key": "peerA-pub"})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_catalog_rejects_unsigned(client):
    """GET /peer/catalog without signature headers must return 401."""
    resp = await client.get("/peer/catalog")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_pair_then_signed_catalog(client):
    """A correct pairing must yield a shared secret that signs /peer/catalog."""
    code = peer_manager.generate_pairing_code()
    my_pub = peer_manager.public_key_pem
    resp = await client.post("/peer/pair", json={"code": code, "public_key": "peerA-pub"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert body["public_key"] == my_pub

    secret = derive_shared_secret(code, "peerA-pub", my_pub)
    headers = signed_headers(secret, "/peer/catalog")
    resp = await client.get("/peer/catalog", headers=headers)
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_admin_peers_list_requires_admin(client, admin_client):
    """GET /api/peers must require an admin session."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as anon:
        resp = await anon.get("/api/peers")
        assert resp.status_code == 401
    resp = await admin_client.get("/api/peers")
    assert resp.status_code == 200


def test_derive_secret_symmetric():
    """Both pairing sides must derive the same secret regardless of order."""
    pub_a, pub_b = "A" * 30, "B" * 30
    assert derive_shared_secret("123456", pub_a, pub_b) == derive_shared_secret("123456", pub_b, pub_a)
    assert derive_shared_secret("123456", pub_a, pub_b) != derive_shared_secret("654321", pub_a, pub_b)


@pytest.mark.asyncio
async def test_peer_zim_receive_requires_signature(client):
    """The signed /peer/zim/search receive endpoint must reject unsigned requests."""
    resp = await client.get("/peer/zim/search", params={"query": "test"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_peer_zim_receive_signed(client):
    """A paired peer can search local ZIM articles with a valid signature."""
    code = peer_manager.generate_pairing_code()
    resp = await client.post("/peer/pair", json={"code": code, "public_key": "peerZim-pub"})
    assert resp.status_code == 200
    secret = derive_shared_secret(code, "peerZim-pub", peer_manager.public_key_pem)

    path = "/peer/zim/search?query=test&offset=0&limit=50"
    headers = signed_headers(secret, path)
    resp = await client.get(path, headers=headers)
    assert resp.status_code == 200
    assert resp.json() == {"articles": [], "total": 0, "offset": 0, "has_more": False}


@pytest.mark.asyncio
async def test_zim_search_merge_empty_without_peers(client):
    """/zim/search works with no paired hubs: local-only results, no peer prefix."""
    await db_exec("DELETE FROM peers")
    resp = await client.get("/zim/search", params={"query": "qwerty12345"})
    assert resp.status_code == 200
    body = resp.json()
    assert set(body) == {"articles", "total", "offset", "has_more"}
    assert body["articles"] == []
    assert body["total"] == 0
    assert body["has_more"] is False
    for article in body["articles"]:
        assert not article["article_id"].startswith("peer:")


@pytest.mark.asyncio
async def test_zim_page_peer_unpaired_404(client):
    """A peer-namespaced article id proxies via /zim/page; unpaired peer is 404."""
    resp = await client.get("/zim/page", params={"article_id": "peer:nope:abc"})
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_zim_asset_peer_unpaired_404(client):
    """A peer-namespaced archive id proxies via /zim/asset; unpaired peer is 404."""
    resp = await client.get("/zim/asset", params={"archive_id": "peer:nope:abc", "path": "X"})
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_zim_thumbnail_peer_unpaired_404(client):
    """A peer-namespaced article id proxies via /zim/thumbnail; unpaired peer is 404."""
    resp = await client.get("/zim/thumbnail", params={"article_id": "peer:nope:abc"})
    assert resp.status_code == 404


def test_split_peer_id():
    """Peer id splitting: prefixed -> (peer_id, rest); otherwise passthrough."""
    assert _split_peer_id("peer:abc:ZIM-1") == ("abc", "ZIM-1")
    assert _split_peer_id("peer:abc:ZIM-1:more") == ("abc", "ZIM-1:more")
    assert _split_peer_id("ZIM-1") == (None, "ZIM-1")
    assert _split_peer_id("peer:only") == (None, "peer:only")
    assert _split_peer_id("peer:") == (None, "peer:")
