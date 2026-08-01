"""Tests for hub federation: pairing, request signing, and admin endpoints.

Follows the conftest fixtures (temp DB, client, admin_client). The signing
helpers in app.peer_sync are exercised both directly (unit-style, no
network) and end-to-end through a paired /peer/catalog request.
"""

import time

import pytest
from httpx import ASGITransport, AsyncClient

from app.api import app
from app.peer_sync import PeerManager, derive_shared_secret, signed_headers

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
