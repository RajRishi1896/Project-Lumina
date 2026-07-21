"""Async SQLite helpers -- wraps sqlite3 calls in a dedicated thread pool.

Every function opens its own connection and closes it automatically.
A dedicated ThreadPoolExecutor (20 workers) prevents the 6-worker default
from bottlenecking under 250 concurrent students.

For multi-statement transactions, use ``db_conn()`` as an async context
manager. For single-query hot paths, prefer the per-query helpers below.
"""
import sqlite3
import asyncio
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from app.database import DB_PATH

TIMEOUT = 5.0

# Dedicated executor -- 20 workers handles 250 concurrent students with
# headroom for burst activity.  On 2-core Celeron the default is only 6.
# ponytail: hardcoded cap, make configurable if deployed on 8+ core hw.
_DB_EXECUTOR = ThreadPoolExecutor(max_workers=20, thread_name_prefix="db")


def _connect():
    """Open a connection and apply performance pragmas.

    Every connection from this module goes through here so the pragmas
    are always set -- no sqlite3.connect() calls outside this module.
    """
    conn = sqlite3.connect(DB_PATH, timeout=TIMEOUT, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA cache_size=-8000")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


async def db_fetch(sql: str, params: tuple = ()) -> list:
    """Fetch all rows from a SELECT, running entirely in the thread pool.

    Opens its own connection -- safe for concurrent hot-path use.
    """
    def _fetch():
        conn = _connect()
        try:
            return conn.execute(sql, params).fetchall()
        finally:
            conn.close()
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_DB_EXECUTOR, _fetch)


async def db_fetch_one(sql: str, params: tuple = ()):
    """Fetch one row (or None) from a SELECT in the thread pool."""
    def _fetch():
        conn = _connect()
        try:
            return conn.execute(sql, params).fetchone()
        finally:
            conn.close()
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_DB_EXECUTOR, _fetch)


async def db_exec(sql: str, params: tuple = ()) -> int:
    """Execute a write (INSERT/UPDATE/DELETE) with auto-commit.

    Returns lastrowid (0 for non-INSERT statements).
    """
    def _exec():
        conn = _connect()
        try:
            cur = conn.execute(sql, params)
            conn.commit()
            return cur.lastrowid
        finally:
            conn.close()
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_DB_EXECUTOR, _exec)


async def db_exec_many(sql: str, params_list: list[tuple]) -> None:
    """Execute the same SQL with multiple parameter sets (batch INSERT/UPDATE).

    Uses a single connection + transaction for the whole batch.  Prefer this
    over calling ``db_exec`` in a loop when you need to insert many rows.
    """
    def _exec():
        conn = _connect()
        try:
            conn.executemany(sql, params_list)
            conn.commit()
        finally:
            conn.close()
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(_DB_EXECUTOR, _exec)


async def db_run(func):
    """Run a custom SQLite operation entirely in the DB thread pool.

    Use this for short multi-statement transactions that do not fit the
    single-query helpers. The callback receives a connection and may return
    a value.
    """
    def _run():
        conn = _connect()
        try:
            return func(conn)
        finally:
            conn.close()
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_DB_EXECUTOR, _run)


@asynccontextmanager
async def db_conn():
    """Async context manager for multi-statement transactions.

    Yields an open connection with pragmas already applied.  The *entire*
    ``async with`` block runs inside the thread pool -- no queries leak
    onto the event loop.

    Prefer the per-query helpers (``db_fetch`` etc.) for single-query
    hot paths -- they are leaner and avoid the context manager overhead.
    """
    loop = asyncio.get_running_loop()
    conn = await loop.run_in_executor(_DB_EXECUTOR, _connect)
    try:
        yield conn
    finally:
        await loop.run_in_executor(_DB_EXECUTOR, conn.close)
