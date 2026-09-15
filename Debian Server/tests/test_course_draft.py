"""Regression: Save Draft must unpublish a published course via PUT."""
import uuid

import pytest


def _auth(token):
    """Build the Authorization header for a token."""
    return {"Authorization": f"Bearer {token}"}


async def _make_student(name):
    """Create a student account and session; return (id, token)."""
    from app.async_db import db_exec
    from app.dependencies import hash_password
    sid = f"LUMINA_TEST-{uuid.uuid4().hex[:12]}"
    token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    await db_exec(
        "INSERT INTO scholars (id, username, name, hashed_password, reset_required, grade) VALUES (?, ?, ?, ?, 0, 'General')",
        (sid, name, name, hash_password("TestPass123")))
    await db_exec(
        "INSERT INTO sessions (token, username, role, used, expiry) VALUES (?, ?, 'student', 0, datetime('now', '+1 day'))",
        (token, sid))
    return sid, token


@pytest.mark.asyncio
async def test_put_status_draft_unpublishes(admin_client):
    """PUT with status='draft' flips published 1 -> 0; 'published' flips back."""
    from app.async_db import db_exec
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Draft Test", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]

    # Empty courses cannot be published: seed one resource first.
    await db_exec(
        "INSERT INTO course_resources (id, course_id, resource_type, title, position) VALUES (?, ?, 'textbook', 'Ch 1', 0)",
        ("RES-draft-seed", cid))

    # Publish via toggle, then Save Draft must revert it
    r = await admin_client.post(f"/api/teacher/courses/{cid}/publish")
    assert r.is_success and r.json()["published"] == 1

    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Draft Test", "subject": "General", "grade": 5,
        "language": "en", "status": "draft"})
    assert r.is_success and r.json()["published"] == 0

    # Re-publish explicitly through the same metadata save path
    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Draft Test", "subject": "General", "grade": 5,
        "language": "en", "status": "published"})
    assert r.is_success and r.json()["published"] == 1

    # No status field -> publish state untouched
    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Renamed", "subject": "General", "grade": 5, "language": "en"})
    assert r.is_success and r.json()["published"] == 1 and r.json()["title"] == "Renamed"


@pytest.mark.asyncio
async def test_empty_publish_400(admin_client):
    """Publishing or status='published' on a resourceless course is rejected."""
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Empty Course", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]

    r = await admin_client.post(f"/api/teacher/courses/{cid}/publish")
    assert r.status_code == 400

    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Empty Course", "subject": "General", "grade": 5,
        "language": "en", "status": "published"})
    assert r.status_code == 400


@pytest.mark.asyncio
async def test_course_detail_returns_version_and_topics(admin_client, client):
    """Student detail carries version, topics[] with unlock_mode, and per-resource topic_id/updated_at/quiz_version."""
    from app.async_db import db_exec, db_fetch_one
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Versioned Course", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    assert r.json()["version"] == 1

    await db_exec(
        "INSERT INTO course_resources (id, course_id, resource_type, title, position) VALUES (?, ?, 'textbook', 'Ch 1', 0)",
        ("RES-ver-seed", cid))
    r = await admin_client.post(f"/api/teacher/courses/{cid}/publish")
    assert r.is_success

    v0 = (await db_fetch_one("SELECT version FROM courses WHERE id = ?", (cid,)))["version"]

    # Topic create accepts unlock_mode and bumps the version.
    r = await admin_client.post(f"/api/teacher/courses/{cid}/topics", json={
        "title": "Chapter 1", "unlock_mode": "sequential"})
    assert r.status_code == 200, r.text
    assert r.json()["unlock_mode"] == "sequential"
    tid = r.json()["id"]
    v1 = (await db_fetch_one("SELECT version FROM courses WHERE id = ?", (cid,)))["version"]
    assert v1 == v0 + 1

    # Assigning the seeded resource to the topic bumps again.
    r = await admin_client.put(f"/api/teacher/courses/{cid}/resources/RES-ver-seed/topic",
                               json={"topic_id": tid})
    assert r.is_success
    v2 = (await db_fetch_one("SELECT version FROM courses WHERE id = ?", (cid,)))["version"]
    assert v2 == v1 + 1

    # Quiz create bumps once more.
    r = await admin_client.post(f"/api/teacher/courses/{cid}/quiz", json={
        "title": "Quiz 1", "topic_id": tid, "questions": [
            {"id": "q1", "type": "mcq", "question": "1+1?",
             "options": ["2", "3"], "correct_answer": 0}]})
    assert r.status_code == 200, r.text
    quiz_rid = r.json()["id"]
    v3 = (await db_fetch_one("SELECT version FROM courses WHERE id = ?", (cid,)))["version"]
    assert v3 == v2 + 1

    _, token = await _make_student("stu_ver")

    r = await client.get(f"/api/courses/{cid}", headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["version"] == v3
    assert len(body["topics"]) == 1
    topic = body["topics"][0]
    assert (topic["id"], topic["title"], topic["position"], topic["unlock_mode"]) == (tid, "Chapter 1", 0, "sequential")

    by_id = {res["id"]: res for res in body["resources"]}
    assert by_id["RES-ver-seed"]["topic_id"] == tid
    assert "updated_at" in by_id["RES-ver-seed"]
    assert by_id[quiz_rid]["quiz_version"] == 1
    assert "quiz_version" not in by_id["RES-ver-seed"]

    r = await client.get("/api/courses", headers=_auth(token))
    assert r.status_code == 200
    versions = {item["id"]: item["version"] for item in r.json()["items"]}
    assert versions[cid] == v3


@pytest.mark.asyncio
async def test_enroll_unenroll_roundtrip(admin_client, client):
    """Enroll then unenroll returns 200, removes the row, decrements count."""
    from app.async_db import db_exec, db_fetch_one
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Unenroll Course", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    await db_exec(
        "INSERT INTO course_resources (id, course_id, resource_type, title, position) VALUES (?, ?, 'textbook', 'Ch 1', 0)",
        ("RES-unenroll-seed", cid))
    r = await admin_client.post(f"/api/teacher/courses/{cid}/publish")
    assert r.is_success

    sid, token = await _make_student("stu_unenroll")
    r = await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 200, r.text
    count = (await db_fetch_one("SELECT enrollment_count FROM courses WHERE id = ?", (cid,)))["enrollment_count"]
    assert count == 1

    r = await client.delete(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "ok" and r.json()["course_id"] == cid

    row = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (sid, cid))
    assert row is None, "unenroll must delete the enrollment row"
    count = (await db_fetch_one("SELECT enrollment_count FROM courses WHERE id = ?", (cid,)))["enrollment_count"]
    assert count == 0, "unenroll must decrement the enrollment count"

    # Second unenroll has no row left: 404, and the count stays floored at 0.
    r = await client.delete(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 404
    count = (await db_fetch_one("SELECT enrollment_count FROM courses WHERE id = ?", (cid,)))["enrollment_count"]
    assert count == 0


@pytest.mark.asyncio
async def test_unenroll_when_not_enrolled_404(admin_client, client):
    """DELETE enroll without an enrollment row returns 404 and touches nothing."""
    from app.async_db import db_fetch_one
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Never Enrolled", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]

    _, token = await _make_student("stu_never")
    r = await client.delete(f"/api/courses/{cid}/enroll", headers=_auth(token))
    assert r.status_code == 404
    count = (await db_fetch_one("SELECT enrollment_count FROM courses WHERE id = ?", (cid,)))["enrollment_count"]
    assert count == 0


@pytest.mark.asyncio
async def test_quiz_create_names_answerless_question(admin_client):
    """Quiz create with one answerless question 400s naming Q<number> + text."""
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Quiz Error Course", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]

    r = await admin_client.post(f"/api/teacher/courses/{cid}/quiz", json={
        "title": "Quiz 1", "questions": [
            {"id": "q1", "type": "mcq", "question": "1+1?",
             "options": ["2", "3"], "correct_answer": 0},
            {"id": "q2", "type": "mcq", "question": "What is the photosynthesis equation?",
             "options": ["A", "B"]}]})
    assert r.status_code == 400, r.text
    detail = r.json()["detail"]
    assert "Q2" in detail, f"error must name the 1-based question number: {detail}"
    assert "photosynthesis equation" in detail, f"error must quote the question text: {detail}"
