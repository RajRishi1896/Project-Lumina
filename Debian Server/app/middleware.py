"""Request ID, structured logging, and global rate limiting middleware.

Request ID: UUID per HTTP request, attached to response headers and stored
on request.state for audit/logging use.

Structured logging: Every request logged with method, path, status, duration,
request ID, and client IP.

Rate limiting: Per-IP sliding window. Applied globally with per-route overrides.
"""
import time
import uuid
import logging
from collections import defaultdict
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("lumina.middleware")

# ── Request ID ────────────────────────────────────────────────────────────────

class RequestIDMiddleware(BaseHTTPMiddleware):
    """Attach a UUID4 request ID to every request/response cycle.

    Stores on request.state.request_id for downstream use by audit(), error
    handlers, etc. Sets X-Request-ID response header.
    """
    async def dispatch(self, request, call_next):
        """Attach a request ID to state and response headers for downstream logging."""
        request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex[:12]
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response


# ── Structured Request Logging ────────────────────────────────────────────────

class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Log every request with method, path, status, duration, IP, and request ID.

    Skips /ping and /generate_204 to reduce noise.
    """
    async def dispatch(self, request, call_next):
        """Time the request, log it, and feed response-time/slow-endpoint metrics."""
        path = request.url.path
        if path in ("/ping", "/generate_204"):
            return await call_next(request)

        from app.metrics import record_response_time, record_slow_endpoint
        start = time.monotonic()
        client_ip = request.client.host if request.client else "unknown"
        request_id = getattr(request.state, "request_id", "-")

        try:
            response = await call_next(request)
        except Exception:
            duration_ms = (time.monotonic() - start) * 1000
            logger.error(
                "request_error method=%s path=%s ip=%s rid=%s dur=%.1fms",
                request.method, path, client_ip, request_id, duration_ms,
            )
            raise

        duration_ms = (time.monotonic() - start) * 1000
        record_response_time(duration_ms)
        record_slow_endpoint(path, duration_ms)

        level = logging.WARNING if response.status_code >= 400 else logging.INFO
        logger.log(
            level,
            "request method=%s path=%s status=%d ip=%s rid=%s dur=%.1fms",
            request.method, path, response.status_code, client_ip, request_id, duration_ms,
        )
        return response


# ── Global Rate Limiting ──────────────────────────────────────────────────────

# Per-route overrides: path_prefix → (limit, window_seconds)
# Auth routes excluded -- auth.py has its own per-IP rate limiting.
ROUTE_RATE_LIMITS: dict[str, tuple[int, int]] = {
    "/api/upload": (20, 60),
    "/zim/upload": (5, 300),
}


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Per-IP sliding window rate limiter.

    Default: 200 requests/60s. Per-route overrides via ROUTE_RATE_LIMITS dict.
    Returns 429 with Retry-After header when exceeded.

    In-memory only -- resets on server restart. Good enough for a single-node hub
    serving 250 concurrent students.
    """

    def __init__(self, app, default_limit: int = 200, default_window: int = 60):
        super().__init__(app)
        self._default_limit = default_limit
        self._default_window = default_window
        self._hits: dict[str, list[float]] = defaultdict(list)
        self._max_ips = 500
        self._last_full_prune = time.time()

    def _prune_if_needed(self):
        """Periodic full sweep -- removes stale IPs and empty lists."""
        now = time.time()
        # Full sweep every 60 seconds
        if now - self._last_full_prune < 60:
            return
        self._last_full_prune = now
        cutoff = now - (self._default_window * 2)  # keep 2x window for safety
        stale = [ip for ip, ts_list in self._hits.items()
                 if not ts_list or ts_list[-1] < cutoff]
        for ip in stale:
            del self._hits[ip]
        if len(self._hits) > self._max_ips:
            excess = len(self._hits) - self._max_ips
            sorted_ips = sorted(self._hits.keys(), key=lambda ip: self._hits[ip][-1] if self._hits[ip] else 0)
            for ip in sorted_ips[:excess]:
                del self._hits[ip]

    def _check(self, ip: str, path: str) -> tuple[bool, int]:
        """Check if request is allowed. Returns (allowed, retry_after_seconds)."""
        now = time.time()
        limit = self._default_limit
        window = self._default_window

        for prefix, (l, w) in ROUTE_RATE_LIMITS.items():
            if path == prefix or path.startswith(prefix + "/"):
                limit, window = l, w
                break

        cutoff = now - window
        hits = self._hits[ip]
        self._hits[ip] = hits = [t for t in hits if t > cutoff]

        if len(hits) >= limit:
            retry_after = int(hits[0] - cutoff) + 1
            return False, retry_after

        hits.append(now)
        self._prune_if_needed()
        return True, 0

    async def dispatch(self, request, call_next):
        """Enforce the per-IP rate limit, returning 429 with Retry-After when exceeded."""
        # Skip rate limiting for static files, ZIM local reads, health checks, and localhost
        path = request.url.path
        if path.startswith("/static/") or path.startswith("/files/") or path.startswith("/zim/") or path in ("/ping", "/generate_204"):
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"
        if client_ip in ("127.0.0.1", "::1"):
            return await call_next(request)
        allowed, retry_after = self._check(client_ip, path)

        if not allowed:
            from fastapi.responses import JSONResponse
            return JSONResponse(
                {"error": "rate_limit_exceeded", "retry_after": retry_after},
                status_code=429,
                headers={
                    "Retry-After": str(retry_after),
                    "X-Content-Type-Options": "nosniff",
                    "X-Frame-Options": "DENY",
                    "Cache-Control": "no-cache, private",
                },
            )

        return await call_next(request)
