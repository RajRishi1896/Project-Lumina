"""Security tests: resource editing/deletion, course export ownership,
and auth gating on upload-status / quiz-resource endpoints."""
import os
import uuid

from app.async_db import db_exec, db_fetch_one
from app.dependencies import hash_password


def _auth(token):
    """Build the Authorization header for a token."""
    return {"Authorization": f"Bearer {token}"}


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


async def _make_resource(owner, title="A's book"):
    """Insert an approved textbook resource owned by `owner`; return its id."""
    rid = f"RES-{uuid.uuid4().hex[:12]}"
    await db_exec(
        "INSERT INTO resources (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, status) VALUES (?, ?, 'General', 'General', 'en', 'textbook', ?, 'book.pdf', 'Test', 'Internal Only', ?, 'approved')",
        (rid, title, f"{rid}.pdf", owner))
    return rid


async def test_any_teacher_can_edit_and_delete_others_resource(client, admin_client):
    """Any teacher may edit or soft-delete any resource."""
    teacher_a, token_a = await _make_teacher("teacher.a")
    _, token_b = await _make_teacher("teacher.b")
    rid = await _make_resource(teacher_a)

    # Any authenticated teacher may edit any resource (no ownership check).
    resp = await client.put(f"/teacher/resources/{rid}",
                            json={"title": "Edited by B"}, headers=_auth(token_b))
    assert resp.status_code == 200, resp.text

    # Delete moves the resource to the recycle bin (soft delete).
    resp = await client.delete(f"/teacher/resources/{rid}", headers=_auth(token_b))
    assert resp.status_code == 200, resp.text
    assert resp.json()["action"] == "recycled"

    row = await db_fetch_one("SELECT title, status FROM resources WHERE id = ?", (rid,))
    assert row and row["title"] == "Edited by B"
    assert row["status"] == "deleted"

    # Deleted resources stay out of the catalog until the 30-day purge.
    resp = await client.get("/api/catalog", headers=_auth(token_b))
    assert all(item["id"] != rid for item in resp.json()), resp.text

    # Admin may delete any teacher's resource too.
    rid2 = await _make_resource(teacher_a, "Second")
    resp = await admin_client.delete(f"/teacher/resources/{rid2}")
    assert resp.status_code == 200, resp.text
    assert resp.json()["action"] == "recycled"

    # Owner can still edit and delete their own resource.
    rid3 = await _make_resource(teacher_a, "Third")
    resp = await client.put(f"/teacher/resources/{rid3}",
                            json={"title": "Owner edit"}, headers=_auth(token_a))
    assert resp.status_code == 200, resp.text
    resp = await client.delete(f"/teacher/resources/{rid3}", headers=_auth(token_a))
    assert resp.status_code == 200, resp.text
    assert resp.json()["action"] == "recycled"


async def test_purge_recycled_resources_deletes_old_and_keeps_fresh(client):
    """Purge hard-deletes recycled resources older than 30 days only."""
    from app.database import UPLOAD_DIR
    from app.maintenance import purge_recycled_resources

    async def _seed(rid, title, deleted_days_ago):
        """Insert a deleted resource with a file, deleted N days ago."""
        fname = f"{rid}.pdf"
        with open(os.path.join(UPLOAD_DIR, fname), "w") as f:
            f.write("x")
        await db_exec(
            "INSERT INTO resources (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, status, deleted_at) "
            "VALUES (?, ?, 'General', 'General', 'en', 'textbook', ?, ?, 'Test', 'Internal Only', 'admin', 'deleted', datetime('now', ?))",
            (rid, title, fname, title, deleted_days_ago))

    old_rid = f"RES-{uuid.uuid4().hex[:12]}"
    fresh_rid = f"RES-{uuid.uuid4().hex[:12]}"
    await _seed(old_rid, "Old", "-31 days")
    await _seed(fresh_rid, "Fresh", "-1 day")

    result = await purge_recycled_resources(days=30)
    assert result == {"purged_count": 1}

    assert not os.path.exists(os.path.join(UPLOAD_DIR, f"{old_rid}.pdf"))
    assert os.path.exists(os.path.join(UPLOAD_DIR, f"{fresh_rid}.pdf"))
    assert await db_fetch_one("SELECT id FROM resources WHERE id = ?", (old_rid,)) is None
    fresh_row = await db_fetch_one("SELECT id, status FROM resources WHERE id = ?", (fresh_rid,))
    assert fresh_row and fresh_row["status"] == "deleted"


async def test_upload_status_requires_auth(client, admin_client):
    """Upload-status requires auth; students are forbidden."""
    resp = await client.get("/upload-status/some-upload-id")
    assert resp.status_code == 401

    _, student_token = await _make_student("s.upload")
    resp = await client.get("/upload-status/some-upload-id", headers=_auth(student_token))
    assert resp.status_code == 403

    resp = await admin_client.get("/upload-status/some-upload-id")
    assert resp.status_code == 200
    assert resp.json()["found"] is False


async def test_quiz_resource_requires_auth_but_students_may_fetch(client, admin_client):
    """Quiz-resource fetch requires auth but students may read published quizzes."""
    resp = await client.get("/api/quiz-resource/nonexistent")
    assert resp.status_code == 401

    created = await admin_client.post("/api/teacher/quiz-resource", json={
        "title": "Sec quiz",
        "questions": [{"id": "q1", "type": "mcq", "question": "2+2?"}],
    })
    assert created.status_code == 200, created.text
    quiz_id = created.json()["id"]

    # The Flutter student app fetches standalone quizzes via this route.
    _, student_token = await _make_student("s.quiz")
    resp = await client.get(f"/api/quiz-resource/{quiz_id}", headers=_auth(student_token))
    assert resp.status_code == 200
    assert "questions" in resp.json()["quiz"]


async def test_teacher_cannot_update_others_quiz(client, admin_client):
    """A teacher cannot update another teacher's quiz resource."""
    created = await admin_client.post("/api/teacher/quiz-resource", json={
        "title": "A quiz",
        "questions": [{"id": "q1", "type": "mcq", "question": "2+2?"}],
    })
    quiz_id = created.json()["id"]

    _, token_b = await _make_teacher("teacher.quizb")
    resp = await client.put(f"/api/teacher/quiz-resource/{quiz_id}",
                            json={"title": "Tampered",
                                  "questions": [{"id": "q1", "type": "mcq", "question": "Hijacked?"}]},
                            headers=_auth(token_b))
    assert resp.status_code == 403, resp.text

    row = await db_fetch_one("SELECT title FROM resources WHERE id = ?", (quiz_id,))
    assert row and row["title"] == "A quiz"


async def test_course_export_available_to_any_teacher(client):
    """Any teacher may export any course (shared hub content)."""
    teacher_a, token_a = await _make_teacher("teacher.expA")
    _, token_b = await _make_teacher("teacher.expB")
    cid = f"CRS-{uuid.uuid4().hex[:12]}"
    await db_exec(
        "INSERT INTO courses (id, title, teacher_username, published) VALUES (?, 'A course', ?, 1)",
        (cid, teacher_a))

    # Any authenticated teacher may export any course (shared hub content).
    resp = await client.get(f"/api/teacher/courses/{cid}/export", headers=_auth(token_b))
    assert resp.status_code == 200, resp.text
    assert resp.headers["content-type"].startswith("application/zip")

    resp = await client.get(f"/api/teacher/courses/{cid}/export", headers=_auth(token_a))
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("application/zip")
