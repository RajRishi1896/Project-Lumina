"""Rate-limit middleware for the Lumina EduMesh Hub.

Provides per-IP rate limiting with two tiers:
- Strict paths (auth/teacher/logout): 600 req/min (counted separately)
- General paths: 3000 req/min (includes all requests)
Stale records are pruned every 60 seconds.

Each record stores (timestamp, is_strict) so static-file requests
don't consume the strict (auth/teacher) budget.
"""
import time
import logging
import asyncio
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi import Request, Response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Per-IP rate limiter that blocks excessive requests within a 60-second window.

    Two tiers:
    - Strict paths (auth/teacher/logout): 600 req/min (counted separately)
    - General paths: 3000 req/min (includes all requests)
    Stale records are pruned every 60 seconds.
    """

    STRICT_PREFIXES = ("/token", "/teacher", "/register", "/logout", "/student/token")

    def __init__(self, app):
        super().__init__(app)
        self.ip_records = {}
        self._lock = asyncio.Lock()
        self._cleanup_started = False

    async def cleanup_stale(self):
        """Periodically remove IP records older than 60 seconds.

        Runs every 60 seconds in a background task to prevent unbounded
        memory growth from rate-limit tracking.

        Returns:
            None. Runs indefinitely in a daemon-style loop.
        """
        while True:
            await asyncio.sleep(60)
            async with self._lock:
                now = time.time()
                for ip, records in list(self.ip_records.items()):
                    self.ip_records[ip] = [(t, s) for (t, s) in records if now - t < 60]
                    if not self.ip_records[ip]:
                        del self.ip_records[ip]

    async def dispatch(self, request: Request, call_next):
        """Apply per-IP rate limiting to each incoming request.

        Two tiers: strict paths (auth, teacher, logout) allow 600 requests
        per 60-second window; general paths allow 3000. Static-file requests
        don't count toward the strict budget.

        Args:
            request: The incoming HTTP request.
            call_next: The next middleware or route handler in the chain.

        Returns:
            A Response object, either a 429 rate-limit response or the
            response from the next handler.
        """
        if not self._cleanup_started:
            self._cleanup_started = True
            asyncio.create_task(self.cleanup_stale())

        client_ip = (
            request.client.host
            if request.client
            else request.headers.get("X-Forwarded-For", "unknown")
        )
        path = request.url.path
        is_strict = path.startswith(self.STRICT_PREFIXES)

        async with self._lock:
            now = time.time()
            records = self.ip_records.get(client_ip, [])
            records = [(t, s) for (t, s) in records if now - t < 60]

            # Strict tier: count only strict-path records
            if is_strict:
                strict_count = sum(1 for (_, s) in records if s)
                if strict_count >= 600:
                    logging.warning(
                        "BLOCKED: Strict rate limit exceeded by IP %s on %s", client_ip, path
                    )
                    return Response(
                        content="Rate limit exceeded. Please wait 60 seconds.",
                        status_code=429,
                    )

            # General tier: count all records
            if len(records) >= 3000:
                logging.warning(
                    "BLOCKED: General flood limit exceeded by IP %s", client_ip
                )
                return Response(
                    content="Too many requests. Please slow down.", status_code=429
                )

            records.append((now, is_strict))
            self.ip_records[client_ip] = records

        return await call_next(request)
