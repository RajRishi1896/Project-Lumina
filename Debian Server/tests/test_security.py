"""Security regression tests for audit findings.

Covers: teacher-only course operations (suggest-similar auth, course
detail ownership), admin-only scholar deletion and subject deletion,
and session invalidation on student password reset.
"""
import uuid

from app.async_db import db_exec
from app.dependencies import hash_password


def _auth(token):
    """Build the Authorization header for a token."""
    return {"Authorization": f"Bearer {token}"}


async def _make_student(name):
    """Create a student account and session; return (id, token)."""
    sid = f"LUMINA_TEST-{uuid.uuid4().hex[:12]}"
    token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    await db_exec(
        "INSERT INTO scholars (id, username, name, hashed_password, reset_required, grade) VALUES (?, ?, ?, ?, 0, 'General')",
        (sid, name, name, hash_password("TestPass123")))
    await db_exec(
        "INSERT INTO sessions (token, username, role, used, expiry) VALUES (?, ?, 'student', 0, datetime('now', '+1 day'))",
        (token, sid))
    return sid, token


async def _make_teacher(name):
    """Create a teacher account and session; return (name, token)."""
    token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    await db_exec(
        "INSERT INTO users (username, hashed_password, name, role) VALUES (?, ?, ?, 'teacher')",
        (name, hash_password("TestPass123"), name))
    await db_exec(
        "INSERT INTO sessions (token, username, role, used, expiry) VALUES (?, ?, 'teacher', 0, datetime('now', '+1 day'))",
        (token, name))
    return name, token


async def test_suggest_similar_requires_teacher(client, admin_client):
    """suggest-similar is unusable unauthenticated or as a student."""
    resp = await client.get("/api/teacher/courses/suggest-similar?q=math")
    assert resp.status_code == 401

    _, student_token = await _make_student("stud_suggest")
    resp = await client.get("/api/teacher/courses/suggest-similar?q=math",
                            headers=_auth(student_token))
    assert resp.status_code == 403

    resp = await admin_client.get("/api/teacher/courses/suggest-similar?q=math")
    assert resp.status_code == 200


async def test_course_detail_available_to_any_teacher(client, admin_client):
    """Any authenticated teacher may read any course's detail (shared content)."""
    owner, owner_token = await _make_teacher("course_owner")
    other, other_token = await _make_teacher("course_other")

    resp = await client.post("/api/teacher/courses",
                             headers=_auth(owner_token),
                             json={"title": "Owner's course", "description": "d",
                                   "subject": "Math", "grade": 9, "language": "en"})
    assert resp.status_code == 200, resp.text
    course_id = resp.json()["id"]

    resp = await client.get(f"/api/teacher/courses/{course_id}",
                            headers=_auth(other_token))
    assert resp.status_code == 200, resp.text

    resp = await client.get(f"/api/teacher/courses/{course_id}",
                            headers=_auth(owner_token))
    assert resp.status_code == 200


async def test_scholar_delete_requires_admin(client, admin_client):
    """Only admins may hard-delete a student account."""
    sid, _ = await _make_student("stud_delete")
    _, teacher_token = await _make_teacher("delete_teacher")

    resp = await client.delete(f"/teacher/scholars/{sid}", headers=_auth(teacher_token))
    assert resp.status_code == 403

    resp = await admin_client.delete(f"/teacher/scholars/{sid}")
    assert resp.status_code == 200
    rows = await _fetch_rows("SELECT id FROM scholars WHERE id = ?", (sid,))
    assert rows == []


async def test_subject_delete_requires_admin(client, admin_client):
    """Only admins may delete a subject from the shared taxonomy."""
    resp = await admin_client.post("/teacher/subjects",
                                   json={"name": "SecurityTestSubject", "symbol": "ST", "class_name": "9"})
    assert resp.status_code == 200, resp.text
    subject_id = resp.json()["id"]

    _, teacher_token = await _make_teacher("subject_teacher")
    resp = await client.delete(f"/teacher/subjects/{subject_id}", headers=_auth(teacher_token))
    assert resp.status_code == 403

    resp = await admin_client.delete(f"/teacher/subjects/{subject_id}")
    assert resp.status_code == 200


async def test_reset_password_invalidates_old_sessions(client, admin_client):
    """Resetting a student password kills all existing sessions."""
    sid, student_token = await _make_student("stud_reset")
    _, teacher_token = await _make_teacher("reset_teacher")

    resp = await client.post(f"/teacher/scholars/reset-password/{sid}", headers=_auth(teacher_token))
    assert resp.status_code == 200, resp.text
    assert resp.json()["temporary_password"]
    assert resp.json()["status"] == "success"

    rows = await _fetch_rows("SELECT token FROM sessions WHERE username = ?", (sid,))
    assert rows == []

    # Student's old token no longer authenticates
    resp = await client.get("/whoami", headers=_auth(student_token))
    assert resp.status_code == 401


async def _fetch_rows(sql, params=()):
    """Fetch rows outside a request context (SQLite thread wrapper)."""
    from app.async_db import db_fetch
    return await db_fetch(sql, params)
