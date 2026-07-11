"""Tests for Lumina Hub API endpoints."""
import pytest


@pytest.mark.asyncio
async def test_login_success(admin_client):
    """POST /token with valid credentials returns 200 + sets session cookie."""
    resp = await admin_client.post("/token", data={"username": "admin", "password": "lumina2026"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["username"] == "admin"
    assert body["role"] == "admin"
    assert "access_token" in body


@pytest.mark.asyncio
async def test_login_failure(client):
    """POST /token with bad password returns 401."""
    resp = await client.post("/token", data={"username": "admin", "password": "wrong"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_whoami(admin_client):
    """GET /whoami with valid session returns user info."""
    resp = await admin_client.get("/whoami")
    assert resp.status_code == 200
    body = resp.json()
    assert body["username"] == "admin"
    assert body["role"] == "admin"


@pytest.mark.asyncio
async def test_whoami_unauthorized(client):
    """GET /whoami without session returns non-ok status."""
    resp = await client.get("/whoami")
    assert resp.status_code != 200


@pytest.mark.asyncio
async def test_static_serve(admin_client):
    """GET /static/css/lumina.css returns a CSS file."""
    resp = await admin_client.get("/static/css/lumina.css")
    assert resp.status_code == 200
    assert "text/css" in resp.headers.get("content-type", "")


@pytest.mark.asyncio
async def test_404(admin_client):
    """GET /nonexistent returns 404."""
    resp = await admin_client.get("/nonexistent")
    assert resp.status_code == 404
