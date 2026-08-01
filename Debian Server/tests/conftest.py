"""pytest fixtures for Lumina Hub API tests."""
import os
import sys
import json
import tempfile
import asyncio
import logging
import unittest.mock
import pytest

_tmp = tempfile.mkdtemp()
_db_path = os.path.join(_tmp, "test.db")
_upload_dir = os.path.join(_tmp, "uploads")
_thumb_dir = os.path.join(_tmp, "thumbnails")
_profile_dir = os.path.join(_tmp, "profile_icons")
_data_dir = os.path.join(_tmp, "data")
_admin_log = os.path.join(_data_dir, "admin_actions.log")

os.makedirs(_data_dir, exist_ok=True)
os.makedirs(_upload_dir, exist_ok=True)
os.makedirs(_thumb_dir, exist_ok=True)
os.makedirs(_profile_dir, exist_ok=True)

# Override BEFORE importing router modules that copy these values at import time
import app.database
app.database.DB_PATH = _db_path
app.database.UPLOAD_DIR = _upload_dir
app.database.THUMBNAILS_DIR = _thumb_dir
app.database.PROFILE_ICONS_DIR = _profile_dir

# Redirect audit log writes to the temp directory
import app.audit
app.audit._DB_PATH = _db_path
_orig_write = app.audit._write_audit_line
def _patched_write_audit_line(event):
    """Write audit events to the test temp directory instead of data/."""
    try:
        with open(_admin_log, "a") as f:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
    except Exception:
        pass
app.audit._write_audit_line = _patched_write_audit_line

# Now safe to import the rest -- DB values are already overridden
from httpx import ASGITransport, AsyncClient
from app.api import app


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    yield loop
    loop.close()


@pytest.fixture(autouse=True)
async def setup_db():
    from app.database import init_db
    await asyncio.to_thread(init_db)
    from app.async_db import db_exec
    await db_exec('UPDATE users SET role = ? WHERE username = ?', ('admin', 'admin'))
    yield


@pytest.fixture
async def client(setup_db):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture
async def admin_client(client):
    resp = await client.post("/token", data={"username": "admin", "password": "lumina2026"})
    assert resp.status_code == 200, f"Login failed: {resp.status_code}"
    return client
