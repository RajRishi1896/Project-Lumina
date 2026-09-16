"""Regression: total_resources is always the live course_resources count.

Enroll INSERT omits total_resources (defaults 0) and the column was echoed
back verbatim, so clients restoring enrollments saw "N/0". The stored column
is now only a cache: sync_progress writes the live COUNT, course detail
returns len(resources), and enrolled-courses uses a batched COUNT.
"""
import uuid

import pytest

from app.async_db import db_exec, db_fetch_one
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


async def _seed_course_with_resources(admin_client, n=2):
    """Create a published course with n resources; return its id."""
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Progress Total Course", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    for i in range(n):
        await db_exec(
            "INSERT INTO course_resources (id, course_id, resource_type, title, position) VALUES (?, ?, 'textbook', ?, ?)",
            (f"RES-pt-{uuid.uuid4().hex[:8]}", cid, f"Ch {i + 1}", i))
    r = await admin_client.post(f"/api/teacher/courses/{cid}/publish")
    assert r.is_success, r.text
    return cid


@pytest.mark.asyncio
async def test_sync_returns_live_total(admin_client, client):
    """Sync echoes the live COUNT (2), not the stale stored 0, and persists it."""
    sid, token = await _make_student("stu_pt_sync")
    cid = await _seed_course_with_resources(admin_client, n=2)
    r = await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 200, r.text

    r = await client.put(f"/api/courses/{cid}/progress", headers=_auth(token),
                         json={"current_position": 1, "completed_count": 1})
    assert r.status_code == 200, r.text
    assert r.json()["total_resources"] == 2

    row = await db_fetch_one(
        "SELECT total_resources FROM course_progress WHERE student_id = ? AND course_id = ?",
        (sid, cid))
    assert row["total_resources"] == 2


@pytest.mark.asyncio
async def test_enrolled_courses_survives_corrupted_stored_total(admin_client, client):
    """A stored total corrupted to 0 still yields live total 2 from enrolled-courses."""
    sid, token = await _make_student("stu_pt_enrolled")
    cid = await _seed_course_with_resources(admin_client, n=2)
    r = await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 200, r.text
    await db_exec(
        "UPDATE course_progress SET total_resources = 0 WHERE student_id = ? AND course_id = ?",
        (sid, cid))

    r = await client.get("/student/enrolled-courses", headers=_auth(token))
    assert r.status_code == 200, r.text
    by_id = {c["course_id"]: c for c in r.json()["courses"]}
    assert by_id[cid]["total_resources"] == 2


@pytest.mark.asyncio
async def test_course_detail_progress_shows_live_total(admin_client, client):
    """GET course detail progress shows the live total 2, not the stored 0."""
    _, token = await _make_student("stu_pt_detail")
    cid = await _seed_course_with_resources(admin_client, n=2)
    r = await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 200, r.text

    r = await client.get(f"/api/courses/{cid}", headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["progress"]["total_resources"] == 2
