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
from app.peer_sync import PeerManager, pairing_proof, sign_headers
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
    """POST /peer/pair with a key proof for the wrong code must return 403."""
    resp = await client.post(
        "/peer/pair",
        json={"key_proof": pairing_proof("000000", "peerA-pub"), "public_key": "peerA-pub"},
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_catalog_rejects_unsigned(client):
    """GET /peer/catalog without signature headers must return 401."""
    resp = await client.get("/peer/catalog")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_pair_then_signed_catalog(client):
    """A correct pairing must yield a session where Ed25519-signed requests pass."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    peer_a_key = Ed25519PrivateKey.generate()
    peer_a_pub = peer_a_key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()

    code = peer_manager.generate_pairing_code()
    my_pub = peer_manager.public_key_pem
    resp = await client.post(
        "/peer/pair",
        json={"key_proof": pairing_proof(code, peer_a_pub), "public_key": peer_a_pub},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert body["public_key"] == my_pub
    # Pairing must confirm the hub's key back to us, keyed by the code
    assert body["key_proof"] == pairing_proof(code, my_pub)

    ts, nonce = str(int(__import__("time").time())), __import__("secrets").token_hex(16)
    sig = peer_a_key.sign(f"{ts}:/peer/catalog".encode()).hex()
    headers = {"X-Peer-Ts": ts, "X-Peer-Nonce": nonce, "X-Peer-Sig": sig}
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


def test_pairing_proof_pins_the_public_key():
    """The key-confirmation MAC must bind the code AND the public key.

    Swapping either input must change the proof -- an attacker who knows
    the code but substitutes their own public key cannot fabricate a proof
    that matches the legitimate peer's.
    """
    pub_a, pub_b = "A" * 30, "B" * 30
    assert pairing_proof("123456", pub_a) != pairing_proof("123456", pub_b)
    assert pairing_proof("123456", pub_a) != pairing_proof("654321", pub_a)
    assert pairing_proof("123456", pub_a) == pairing_proof("123456", pub_a)


@pytest.mark.asyncio
async def test_brute_forced_code_cannot_forge_signatures(client):
    """Even with the 6-digit code brute-forced, signatures cannot be forged.

    Signatures are Ed25519 keyed by the sender's private key, not the code.
    An attacker with the code can confirm pairing but cannot reproduce the
    peer's signature (the private key never leaves its hub); an HMAC-style
    forgery built from the code/proof material is rejected by
    verify_peer_sig.
    """
    import hashlib
    import hmac
    import secrets as _secrets
    import time as _time

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    peer_a_key = Ed25519PrivateKey.generate()
    peer_a_pub = peer_a_key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()

    code = peer_manager.generate_pairing_code()
    resp = await client.post(
        "/peer/pair",
        json={"key_proof": pairing_proof(code, peer_a_pub), "public_key": peer_a_pub},
    )
    assert resp.status_code == 200

    # Attacker knows the code, both public keys, and the signed data shape.
    # The old scheme's HMAC secret is exactly what this recomputes.
    shared = hmac.new(
        code.encode(),
        b"".join(sorted((peer_a_pub.encode(), peer_manager.public_key_pem.encode()))),
        hashlib.sha256,
    ).hexdigest()
    ts = str(int(_time.time()))
    forged_sig = hmac.new(shared.encode(), f"{ts}:/peer/catalog".encode(), hashlib.sha256).hexdigest()
    headers = {"X-Peer-Ts": ts, "X-Peer-Nonce": _secrets.token_hex(16), "X-Peer-Sig": forged_sig}

    resp = await client.get("/peer/catalog", headers=headers)
    assert resp.status_code == 401, "HMAC forgery from a brute-forced code must be rejected"


@pytest.mark.asyncio
async def test_peer_zim_receive_requires_signature(client):
    """The signed /peer/zim/search receive endpoint must reject unsigned requests."""
    resp = await client.get("/peer/zim/search", params={"query": "test"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_peer_zim_receive_signed(client):
    """A paired peer can search local ZIM articles with a valid signature."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    peer_a_key = Ed25519PrivateKey.generate()
    peer_a_pub = peer_a_key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()

    code = peer_manager.generate_pairing_code()
    resp = await client.post(
        "/peer/pair",
        json={"key_proof": pairing_proof(code, peer_a_pub), "public_key": peer_a_pub},
    )
    assert resp.status_code == 200

    path = "/peer/zim/search?query=test&offset=0&limit=50"
    ts, nonce = str(int(__import__("time").time())), __import__("secrets").token_hex(16)
    sig = peer_a_key.sign(f"{ts}:{path}".encode()).hex()
    headers = {"X-Peer-Ts": ts, "X-Peer-Nonce": nonce, "X-Peer-Sig": sig}
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
