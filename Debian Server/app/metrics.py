"""In-memory operational metrics collector.

Tracks login success/failure, uploads, quiz attempts, enrollments, API
response times, and slow endpoints. Thread-safe via GIL (all ops are
atomic dict/list appends).

Data resets on server restart -- acceptable for single-node LAN deployment.
Add persistence only if needed for historical analysis.
"""
import time
import threading
from collections import defaultdict
from datetime import datetime

_lock = threading.Lock()
_start_time = time.time()

# ── Counters ──────────────────────────────────────────────────────────────────

_counters: dict[str, int] = defaultdict(int)

def incr(name: str, n: int = 1):
    """Increment a named counter."""
    with _lock:
        _counters[name] += n


# ── Response time buckets ─────────────────────────────────────────────────────

_response_times: list[tuple[float, float]] = []  # (timestamp, duration_ms)

def record_response_time(duration_ms: float):
    """Record an API response time. Keeps last 1000 entries."""
    with _lock:
        _response_times.append((time.time(), duration_ms))
        if len(_response_times) > 1000:
            del _response_times[:500]


# ── Slow endpoint tracker ─────────────────────────────────────────────────────

_slow_endpoints: dict[str, list[float]] = defaultdict(list)

def record_slow_endpoint(path: str, duration_ms: float, threshold_ms: float = 1000):
    """Track slow endpoints. Keeps last 100 per path."""
    if duration_ms > threshold_ms:
        with _lock:
            _slow_endpoints[path].append(duration_ms)
            if len(_slow_endpoints[path]) > 100:
                _slow_endpoints[path] = _slow_endpoints[path][-100:]


# ── Active users (unique IPs in last 5 minutes) ──────────────────────────────

_active_ips: dict[str, float] = {}

def record_request(ip: str):
    """Track active client IPs. Updated on every request."""
    with _lock:
        _active_ips[ip] = time.time()
        # Prune entries older than 5 minutes
        cutoff = time.time() - 300
        stale = [k for k, v in _active_ips.items() if v < cutoff]
        for k in stale:
            del _active_ips[k]


# ── Query functions ───────────────────────────────────────────────────────────

def get_metrics() -> dict:
    """Return a snapshot of all metrics."""
    now = time.time()
    with _lock:
        # Response time stats
        if _response_times:
            recent = [d for t, d in _response_times if t > now - 300]
            all_times = [d for _, d in _response_times]
            avg_5m = sum(recent) / len(recent) if recent else 0
            avg_all = sum(all_times) / len(all_times) if all_times else 0
            p95_5m = sorted(recent)[int(len(recent) * 0.95)] if recent else 0
        else:
            avg_5m = avg_all = p95_5m = 0

        # Slow endpoints
        slow = {}
        for path, times in _slow_endpoints.items():
            if times:
                slow[path] = {
                    "count": len(times),
                    "avg_ms": round(sum(times) / len(times), 1),
                    "max_ms": round(max(times), 1),
                }

        # Active users (unique IPs in last 5 min)
        cutoff = now - 300
        active = sum(1 for t in _active_ips.values() if t > cutoff)

        return {
            "uptime_seconds": int(now - _start_time),
            "counters": dict(_counters),
            "active_users_5m": active,
            "response_times": {
                "avg_5m_ms": round(avg_5m, 1),
                "avg_all_ms": round(avg_all, 1),
                "p95_5m_ms": round(p95_5m, 1),
            },
            "slow_endpoints": slow,
            "tracked_ips": len(_active_ips),
            "collected_at": datetime.utcnow().isoformat() + "Z",
        }


def get_counters() -> dict:
    """Return just the counters."""
    with _lock:
        return dict(_counters)
