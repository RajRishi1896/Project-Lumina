"""Stability regression tests.

Covers the STABILITY fix batch:
    - Rate limiter: route-specific limits get their own per-IP bucket, so
      ordinary API traffic never counts against the ZIM upload budget.
    - Range header handling: end clamped to file size, inverted ranges 416.
    - Security headers: route-set Cache-Control is preserved, not clobbered.
    - Media endpoints: video preview routes require auth; thumbnail stays
      cookieless (Flutter Image.network sends no Authorization header);
      generation locks are per-resource; blackdetect scan input is capped.
"""
import os
import pytest
from starlette.requests import Request
from starlette.responses import PlainTextResponse

from app.middleware import RateLimitMiddleware


# === Rate limiter bucket isolation (app/middleware.py) ===

def test_route_limit_has_its_own_bucket():
    """Default-route traffic must not consume a route-specific limit bucket."""
    mw = RateLimitMiddleware(app=None, default_limit=5, default_window=60)
    ip = "10.42.0.55"
    # Exhaust the default bucket with ordinary API traffic.
    for _ in range(5):
        assert mw._check(ip, "/api/resources")[0] is True
    allowed, _ = mw._check(ip, "/api/resources")
    assert allowed is False
    # The ZIM-upload bucket (5 per 300s) is independent: still allowed.
    allowed, _ = mw._check(ip, "/teacher/upload-zim")
    assert allowed is True
    # The route hit did not reset or extend the exhausted default bucket.
    allowed, _ = mw._check(ip, "/api/resources")
    assert allowed is False


def test_route_limit_enforces_its_own_limit():
    """A route-specific limit is enforced against its own bucket only."""
    mw = RateLimitMiddleware(app=None, default_limit=100, default_window=60)
    ip = "10.42.0.56"
    # Exhaust the /teacher/upload-zim override (5 per 300s per the config).
    for _ in range(5):
        assert mw._check(ip, "/teacher/upload-zim")[0] is True
    allowed, retry_after = mw._check(ip, "/teacher/upload-zim")
    assert allowed is False
    assert retry_after > 0
    # Default routes remain unaffected by the exhausted route bucket.
    assert mw._check(ip, "/api/resources")[0] is True


def test_route_limit_matches_subpaths_not_prefix_strings():
    """Route limits match the exact path and subpaths, not string prefixes."""
    mw = RateLimitMiddleware(app=None, default_limit=100, default_window=60)
    ip = "10.42.0.57"
    for _ in range(5):
        assert mw._check(ip, "/teacher/upload-zim")[0] is True
    assert mw._check(ip, "/teacher/upload-zim")[0] is False          # route bucket exhausted
    assert mw._check(ip, "/teacher/upload-zim/resume")[0] is False   # subpath shares the bucket
    assert mw._check(ip, "/teacher/upload-zimx")[0] is True          # different path: default bucket


def test_default_limit_still_enforced_per_ip():
    """The shared default bucket still enforces its own limit."""
    mw = RateLimitMiddleware(app=None, default_limit=3, default_window=60)
    for _ in range(3):
        assert mw._check("10.42.0.58", "/api/resources")[0] is True
    assert mw._check("10.42.0.58", "/api/other")[0] is False
    # A different IP has its own buckets.
    assert mw._check("10.42.0.59", "/api/resources")[0] is True


# === Range header handling (app/routers/media.py) ===

def _write_upload(name: str, size: int) -> None:
    """Write a test file of exactly ``size`` bytes into the uploads dir."""
    from app.routers.media import UPLOAD_DIR
    with open(os.path.join(UPLOAD_DIR, name), "wb") as f:
        f.write(b"x" * size)


@pytest.mark.asyncio
async def test_stream_range_end_clamped_to_file_size(admin_client):
    """bytes=0-999999999 on a small file serves exactly the file, not ~1e9 bytes."""
    _write_upload("range_test.bin", 1000)
    resp = await admin_client.get("/api/stream/range_test.bin",
                                  headers={"Range": "bytes=0-999999999"})
    assert resp.status_code == 206
    assert resp.headers["content-length"] == "1000"
    assert resp.headers["content-range"] == "bytes 0-999/1000"
    assert len(resp.content) == 1000


@pytest.mark.asyncio
async def test_stream_range_inverted_returns_416(admin_client):
    """bytes=100-50 must not produce a negative Content-Length."""
    _write_upload("range_test.bin", 1000)
    resp = await admin_client.get("/api/stream/range_test.bin",
                                  headers={"Range": "bytes=100-50"})
    assert resp.status_code == 416


@pytest.mark.asyncio
async def test_stream_range_open_ended_and_suffix(admin_client):
    """Open-ended and suffix ranges are clamped to the last byte."""
    _write_upload("range_test.bin", 1000)
    resp = await admin_client.get("/api/stream/range_test.bin",
                                  headers={"Range": "bytes=500-"})
    assert resp.status_code == 206
    assert resp.headers["content-range"] == "bytes 500-999/1000"
    assert resp.headers["content-length"] == "500"

    resp = await admin_client.get("/api/stream/range_test.bin",
                                  headers={"Range": "bytes=-100"})
    assert resp.status_code == 206
    assert resp.headers["content-range"] == "bytes 900-999/1000"


@pytest.mark.asyncio
async def test_stream_range_start_beyond_size_returns_416(admin_client):
    """A start past EOF stays a 416 (pre-existing behaviour preserved)."""
    _write_upload("range_test.bin", 1000)
    resp = await admin_client.get("/api/stream/range_test.bin",
                                  headers={"Range": "bytes=2000-3000"})
    assert resp.status_code == 416


# === Security headers preserve route Cache-Control (app/api.py) ===

def _request(path: str) -> Request:
    """Build a minimal ASGI request for direct middleware dispatch calls."""
    return Request({"type": "http", "method": "GET", "path": path,
                    "headers": [], "query_string": b"",
                    "client": ("10.42.0.9", 1234)})


@pytest.mark.asyncio
async def test_security_headers_preserve_route_cache_control():
    """A route-set Cache-Control (e.g. ZIM assets: public, max-age=86400) survives."""
    from app.api import add_security_headers
    resp = PlainTextResponse("asset", headers={"Cache-Control": "public, max-age=86400"})

    async def call_next(request):
        return resp

    out = await add_security_headers(_request("/zim/asset"), call_next)
    assert out.headers["cache-control"] == "public, max-age=86400"
    # The other security headers remain unconditional.
    assert out.headers["x-content-type-options"] == "nosniff"
    assert out.headers["x-frame-options"] == "DENY"


@pytest.mark.asyncio
async def test_security_headers_default_cache_control_still_applied():
    """Responses without a Cache-Control still get the private no-cache default."""
    from app.api import add_security_headers
    resp = PlainTextResponse("data")

    async def call_next(request):
        return resp

    out = await add_security_headers(_request("/api/resources"), call_next)
    assert out.headers["cache-control"] == "no-cache, private"


# === Media endpoint auth + single-flight (app/routers/media.py) ===

@pytest.mark.asyncio
async def test_video_preview_requires_auth(client):
    """GET /api/video/previews/{id} without a session returns 401, not a scan."""
    resp = await client.get("/api/video/previews/whatever")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_video_preview_sprite_requires_auth(client):
    """GET /api/video/previews/{id}/sprite without a session returns 401."""
    resp = await client.get("/api/video/previews/whatever/sprite")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_video_preview_authed_reaches_resource_lookup(admin_client):
    """With auth, an unknown resource id fails at the lookup (404), not auth."""
    resp = await admin_client.get("/api/video/previews/nonexistent-id")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_thumbnail_remains_fetchable_without_auth(client):
    """Thumbnails stay header-less: the Flutter app loads them via
    Image.network() with no Authorization header, so an unauthenticated
    request must reach the resource lookup (404 for unknown ids), not 401."""
    resp = await client.get("/api/thumbnail/nonexistent-id")
    assert resp.status_code == 404


def test_generation_lock_is_per_resource():
    """The single-flight lock table returns one lock per resource id."""
    from app.routers.media import _gen_lock
    a = _gen_lock("lock-res-1")
    b = _gen_lock("lock-res-1")
    c = _gen_lock("lock-res-2")
    assert a is b
    assert a is not c


def test_blackdetect_scan_is_time_capped(monkeypatch):
    """The blackdetect scan must bound its input duration (-t) so it cannot
    decode entire multi-hour videos."""
    from app.routers import media

    class _FakeResult:
        returncode = 0
        stdout = ""
        stderr = "black_start:0.0 black_end:2.0"

    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return _FakeResult()

    monkeypatch.setattr(media.subprocess, "run", fake_run)
    t = media._find_video_thumb_time("/nonexistent/video.mp4")
    assert 0 < t <= 30
    assert "-t" in captured["cmd"]
    idx = captured["cmd"].index("-t")
    assert 0 < int(captured["cmd"][idx + 1]) <= 60
