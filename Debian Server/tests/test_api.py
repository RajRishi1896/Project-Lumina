"""Tests for Lumina Hub API endpoints."""
import json
import os
import pytest

import app.database as db_mod


@pytest.mark.asyncio
async def test_login_success(admin_client):
    """POST /token with valid credentials returns 200 + sets session cookie."""
    resp = await admin_client.post("/token", data={"username": "admin", "password": db_mod.DEFAULT_ADMIN_PASSWORD})
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


# === Audit logging tests ===

def _read_audit_log():
    """Read all JSON lines from the test audit log."""
    from tests.conftest import _admin_log
    if not os.path.exists(_admin_log):
        return []
    events = []
    with open(_admin_log, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except Exception:
                pass
    return events


def _clear_audit_log():
    """Truncate the test audit log."""
    from tests.conftest import _admin_log
    if os.path.exists(_admin_log):
        with open(_admin_log, "w") as f:
            f.truncate(0)


@pytest.mark.asyncio
async def test_audit_login_success_emits_event(admin_client):
    """Successful login emits an audit event with action=login."""
    _clear_audit_log()
    await admin_client.post("/token", data={"username": "admin", "password": db_mod.DEFAULT_ADMIN_PASSWORD})
    events = _read_audit_log()
    login_events = [e for e in events if e.get("action") == "login"]
    assert len(login_events) >= 1, f"Expected login audit event, got: {events}"
    evt = login_events[-1]
    assert evt["user"] == "admin"
    assert evt.get("success", True) is not False


@pytest.mark.asyncio
async def test_audit_login_failure_emits_event(client):
    """Failed login emits an audit event with action=login_failed."""
    _clear_audit_log()
    await client.post("/token", data={"username": "admin", "password": "wrong"})
    events = _read_audit_log()
    fail_events = [e for e in events if e.get("action") == "login_failed"]
    assert len(fail_events) >= 1, f"Expected login_failed audit event, got: {events}"
    evt = fail_events[-1]
    assert evt.get("success") is False


@pytest.mark.asyncio
async def test_audit_create_teacher_emits_event(admin_client):
    """Creating a teacher account emits an audit event with action=create_account."""
    _clear_audit_log()
    resp = await admin_client.post("/api/admin/create-teacher",
                                   json={"username": "audit_test_teacher", "password": "AuditTest123", "name": "Audit Test"})
    assert resp.status_code == 200
    events = _read_audit_log()
    create_events = [e for e in events if e.get("action") == "create_account"
                     and e.get("target") == "audit_test_teacher"]
    assert len(create_events) >= 1, f"Expected create_account audit event, got: {events}"
    evt = create_events[-1]
    assert evt["user"] == "admin"
    assert evt.get("resource_type") == "account"


@pytest.mark.asyncio
async def test_audit_change_settings_emits_event(admin_client):
    """Changing log retention policy emits an audit event."""
    _clear_audit_log()
    resp = await admin_client.post("/api/admin/settings", json={"policy": "7d"})
    assert resp.status_code == 200
    events = _read_audit_log()
    settings_events = [e for e in events if e.get("action") == "change_settings"]
    assert len(settings_events) >= 1, f"Expected change_settings audit event, got: {events}"
    evt = settings_events[-1]
    assert evt.get("ctx", {}).get("policy") == "7d"
    # Restore default
    await admin_client.post("/api/admin/settings", json={"policy": "30d"})


@pytest.mark.asyncio
async def test_audit_force_reset_password_emits_event(admin_client):
    """Admin resetting a teacher password emits an audit event."""
    _clear_audit_log()
    resp = await admin_client.post("/teacher/reset-password/audit_test_teacher")
    assert resp.status_code == 200
    events = _read_audit_log()
    reset_events = [e for e in events if e.get("action") == "reset_password"
                    and e.get("target") == "audit_test_teacher"]
    assert len(reset_events) >= 1, f"Expected reset_password audit event, got: {events}"
    evt = reset_events[-1]
    assert evt["user"] == "admin"


@pytest.mark.asyncio
async def test_audit_log_viewer_returns_json(admin_client):
    """The admin log viewer returns structured JSON events."""
    _clear_audit_log()
    await admin_client.post("/api/admin/settings", json={"policy": "30d"})
    resp = await admin_client.get("/admin/log?limit=5")
    assert resp.status_code == 200
    body = resp.json()
    assert "log" in body
    assert isinstance(body["log"], list)
    assert len(body["log"]) >= 1
    # Each entry should be a dict (structured event), not a raw string
    for entry in body["log"]:
        assert isinstance(entry, dict), f"Expected dict, got {type(entry)}: {entry}"


@pytest.mark.asyncio
async def test_audit_event_structure():
    """Audit events have the required JSON structure."""
    from app.audit import audit, Action, Severity
    _clear_audit_log()
    await audit(
        action=Action.LOGIN,
        username="test_user",
        severity=Severity.INFO,
        resource_type="session",
        resource_id="test123",
        resource_name="Test Session",
    )
    events = _read_audit_log()
    struct_events = [e for e in events if e.get("action") == "login" and e.get("user") == "test_user"]
    assert len(struct_events) >= 1
    evt = struct_events[-1]
    assert "id" in evt
    assert "ts" in evt
    assert evt["action"] == "login"
    assert evt["user"] == "test_user"
    assert evt.get("resource_type") == "session"
    assert evt.get("resource_id") == "test123"
    assert evt.get("resource_name") == "Test Session"
