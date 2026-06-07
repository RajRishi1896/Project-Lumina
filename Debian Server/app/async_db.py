"""Async SQLite helpers — wraps sqlite3 calls in asyncio.to_thread.

All functions in this module open a fresh connection for each call
and close it automatically.  For transactions spanning multiple
statements, use `db_conn()` as an async context manager and run the
SQL statements synchronously within the managed block.
"""
import sqlite3
import asyncio
from contextlib import asynccontextmanager
from app.database import DB_PATH

TIMEOUT = 5.0


@asynccontextmanager
async def db_conn():
    """Async context manager that yields an open SQLite connection.

    The connection is automatically closed when the context manager exits.
    Use this for multi-statement transactions.

    Yields:
        A sqlite3.Connection object.
    """
    conn = await asyncio.to_thread(
        lambda: sqlite3.connect(DB_PATH, timeout=TIMEOUT, check_same_thread=False)
    )
    try:
        yield conn
    finally:
        await asyncio.to_thread(conn.close)


async def db_exec(sql: str, params: tuple = ()) -> sqlite3.Cursor:
    """Execute a SQL statement and commit, returning the cursor.

    Opens a fresh connection, runs the statement, commits, and closes.

    Args:
        sql: SQL statement string.
        params: Optional tuple of parameters for the statement.

    Returns:
        The sqlite3.Cursor after execution.
    """
    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=TIMEOUT)
        try:
            cur = conn.cursor()
            cur.execute(sql, params)
            conn.commit()
            return cur
        finally:
            conn.close()
    return await asyncio.to_thread(_run)


async def db_fetchone(sql: str, params: tuple = ()):
    """Execute a query and return the first matching row.

    Args:
        sql: SQL query string.
        params: Optional tuple of parameters for the query.

    Returns:
        A single row as a sqlite3.Row or None if no match.
    """
    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=TIMEOUT)
        try:
            cur = conn.cursor()
            cur.execute(sql, params)
            return cur.fetchone()
        finally:
            conn.close()
    return await asyncio.to_thread(_run)


async def db_fetchall(sql: str, params: tuple = ()):
    """Execute a query and return all matching rows.

    Args:
        sql: SQL query string.
        params: Optional tuple of parameters for the query.

    Returns:
        List of rows as sqlite3.Row objects.
    """
    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=TIMEOUT)
        try:
            cur = conn.cursor()
            cur.execute(sql, params)
            return cur.fetchall()
        finally:
            conn.close()
    return await asyncio.to_thread(_run)


async def db_execute(sql: str, params: tuple = ()):
    """Execute a SQL statement and commit without returning a cursor.

    Fire-and-forget variant of db_exec for statements where the cursor
    is not needed.

    Args:
        sql: SQL statement string.
        params: Optional tuple of parameters for the statement.
    """
    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=TIMEOUT)
        try:
            cur = conn.cursor()
            cur.execute(sql, params)
            conn.commit()
        finally:
            conn.close()
    await asyncio.to_thread(_run)
