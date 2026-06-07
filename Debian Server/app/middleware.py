"""Rate-limit middleware for the Lumina EduMesh Hub.

Provides per-IP rate limiting with two tiers:
- Strict paths (auth/teacher/logout): 200 req/min
- General paths: 1000 req/min
Stale records are pruned every 60 seconds.
"""
import time
import logging
import asyncio
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi import Request, Response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Per-IP rate limiter that blocks excessive requests within a 60-second window.

    Two tiers:
    - Strict paths (auth/teacher/logout): 200 req/min
    - General paths: 1000 req/min
    Stale records are pruned every 60 seconds.
    """

    def __init__(self, app):
        super().__init__(app)
        self.ip_records = {}
        self._lock = asyncio.Lock()
        asyncio.create_task(self.cleanup_stale())

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
                self.ip_records = {
                    ip: [t for t in ts if now - t < 60]
                    for ip, ts in self.ip_records.items()
                }

    async def dispatch(self, request: Request, call_next):
        """Apply per-IP rate limiting to each incoming request.

        Two tiers: strict paths (auth, teacher, logout) allow 200 requests
        per 60-second window; general paths allow 1000. Returns a 429
        response when the limit is exceeded.

        Args:
            request: The incoming HTTP request.
            call_next: The next middleware or route handler in the chain.

        Returns:
            A Response object, either a 429 rate-limit response or the
            response from the next handler.
        """
        client_ip = request.client.host if request.client else request.headers.get("X-Forwarded-For", "unknown")
        path = request.url.path
        async with self._lock:
            now = time.time()
            timestamps = self.ip_records.get(client_ip, [])
            timestamps = [t for t in timestamps if now - t < 60]

            strict_paths = ["/token", "/teacher", "/register", "/logout", "/student/token"]
            if any(path.startswith(p) for p in strict_paths):
                if len(timestamps) >= 200:
                    logging.warning(f"BLOCKED: Strict rate limit exceeded by IP {client_ip} on {path}")
                    return Response(content="Rate limit exceeded. Please wait 60 seconds.", status_code=429)

            if len(timestamps) >= 1000:
                logging.warning(f"BLOCKED: General flood limit exceeded by IP {client_ip}")
                return Response(content="Too many requests. Please slow down.", status_code=429)

            timestamps.append(now)
            self.ip_records[client_ip] = timestamps
        return await call_next(request)
