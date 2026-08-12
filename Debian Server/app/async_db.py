"""Async SQLite helpers -- wraps sqlite3 calls in a dedicated thread pool.

Every function opens its own connection and closes it automatically.
A dedicated ThreadPoolExecutor (20 workers) prevents the 6-worker default
from bottlenecking under 250 concurrent students.

For single-query hot paths, use the per-query helpers (``db_fetch``,
``db_fetch_one``, ``db_exec``). For multi-statement transactions, pass a
callback to ``db_run()`` -- it executes the whole body in the thread pool.
"""
import sqlite3
import asyncio
from concurrent.futures import ThreadPoolExecutor
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
        """Run the SELECT inside the executor worker thread."""
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
        """Run the SELECT inside the executor worker thread."""
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
        """Run the write and commit inside the executor worker thread."""
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
        """Run the batch write inside the executor worker thread."""
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
    a value. The whole callback body (including any DML) runs inside the
    thread pool -- nothing blocks the event loop.
    """
    def _run():
        """Run the user callback inside the executor worker thread."""
        conn = _connect()
        try:
            return func(conn)
        finally:
            conn.close()
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_DB_EXECUTOR, _run)
