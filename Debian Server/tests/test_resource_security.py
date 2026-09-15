"""Security tests: resource editing/deletion, course export ownership,
and auth gating on quiz-resource endpoints."""
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


async def test_teacher_ownership_enforced_on_edit_and_delete(client, admin_client):
    """Teachers can only edit/delete their own resources; admins can manage all."""
    teacher_a, token_a = await _make_teacher("teacher.a")
    _, token_b = await _make_teacher("teacher.b")
    rid = await _make_resource(teacher_a)

    # Teacher B cannot edit teacher A's resource (ownership enforced).
    resp = await client.put(f"/teacher/resources/{rid}",
                            json={"title": "Edited by B"}, headers=_auth(token_b))
    assert resp.status_code == 403, resp.text

    # Teacher B cannot delete teacher A's resource either.
    resp = await client.delete(f"/teacher/resources/{rid}", headers=_auth(token_b))
    assert resp.status_code == 403, resp.text

    # Owner can edit and delete their own resource.
    resp = await client.put(f"/teacher/resources/{rid}",
                            json={"title": "Owner edit"}, headers=_auth(token_a))
    assert resp.status_code == 200, resp.text
    resp = await client.delete(f"/teacher/resources/{rid}", headers=_auth(token_a))
    assert resp.status_code == 200, resp.text
    assert resp.json()["action"] == "recycled"

    row = await db_fetch_one("SELECT title, status FROM resources WHERE id = ?", (rid,))
    assert row and row["title"] == "Owner edit"
    assert row["status"] == "deleted"

    # Deleted resources stay out of the catalog until the 30-day purge.
    resp = await client.get("/api/catalog", headers=_auth(token_a))
    assert all(item["id"] != rid for item in resp.json()), resp.text

    # Admin may delete any teacher's resource.
    rid2 = await _make_resource(teacher_a, "Second")
    resp = await admin_client.delete(f"/teacher/resources/{rid2}")
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


async def test_quiz_resource_requires_auth_but_students_may_fetch(client, admin_client):
    """Quiz-resource fetch requires auth but students may read published quizzes."""
    resp = await client.get("/api/quiz-resource/nonexistent")
    assert resp.status_code == 401

    created = await admin_client.post("/api/teacher/quiz-resource", json={
        "title": "Sec quiz",
        "questions": [{"id": "q1", "type": "mcq", "question": "2+2?", "options": ["3", "4"], "correct_answer": 1}],
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
        "questions": [{"id": "q1", "type": "mcq", "question": "2+2?", "options": ["3", "4"], "correct_answer": 1}],
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


async def _make_course(title="BM course", published=0):
    """Insert a course row; return its id."""
    cid = f"CRS-{uuid.uuid4().hex[:12]}"
    await db_exec(
        "INSERT INTO courses (id, title, teacher_username, published) VALUES (?, ?, 'admin', ?)",
        (cid, title, published))
    return cid


async def test_bookmark_roundtrip_push_get(client):
    """POST sync-bookmarks then GET returns the same entries."""
    rid = await _make_resource("admin", "BM book")
    cid = await _make_course()
    _, token = await _make_student("s.bmround")
    payload = {"bookmarks": [
        {"resource_id": rid, "title": "BM book", "subject": "General", "grade": "General", "resource_type": "textbook"},
        {"resource_id": cid, "title": "BM course", "subject": "General", "grade": "5", "resource_type": "course"},
    ]}
    resp = await client.post("/student/sync-bookmarks", json=payload, headers=_auth(token))
    assert resp.status_code == 200, resp.text
    resp = await client.get("/student/bookmarks", headers=_auth(token))
    assert resp.status_code == 200, resp.text
    got = {b["resource_id"]: b for b in resp.json()["bookmarks"]}
    assert got[rid]["title"] == "BM book"
    assert got[rid]["resource_type"] == "textbook"
    assert got[cid]["resource_type"] == "course"


async def test_bookmark_get_requires_auth(client):
    """GET /student/bookmarks without a session returns 401."""
    resp = await client.get("/student/bookmarks")
    assert resp.status_code == 401


async def test_resource_soft_delete_removes_bookmarks(client, admin_client):
    """Soft-deleting a resource removes its student_bookmarks rows."""
    from app.async_db import db_fetch
    rid = await _make_resource("admin", "Doomed book")
    _, token = await _make_student("s.bmdel")
    resp = await client.post("/student/sync-bookmarks", json={"bookmarks": [
        {"resource_id": rid, "title": "Doomed book", "subject": "General", "grade": "General", "resource_type": "textbook"},
    ]}, headers=_auth(token))
    assert resp.status_code == 200, resp.text
    resp = await admin_client.delete(f"/teacher/resources/{rid}")
    assert resp.status_code == 200, resp.text
    rows = await db_fetch("SELECT resource_id FROM student_bookmarks WHERE resource_id = ?", (rid,))
    assert rows == []
    resp = await client.get("/student/bookmarks", headers=_auth(token))
    assert resp.status_code == 200
    assert all(b["resource_id"] != rid for b in resp.json()["bookmarks"])


async def test_course_soft_delete_removes_course_bookmarks(client, admin_client):
    """Archiving a course removes resource_type='course' bookmarks for it."""
    cid = await _make_course("Doomed course")
    _, token = await _make_student("s.bmcourse")
    resp = await client.post("/student/sync-bookmarks", json={"bookmarks": [
        {"resource_id": cid, "title": "Doomed course", "subject": "General", "grade": "5", "resource_type": "course"},
    ]}, headers=_auth(token))
    assert resp.status_code == 200, resp.text
    resp = await admin_client.delete(f"/api/teacher/courses/{cid}")
    assert resp.status_code == 200, resp.text
    resp = await client.get("/student/bookmarks", headers=_auth(token))
    assert resp.status_code == 200
    assert all(b["resource_id"] != cid for b in resp.json()["bookmarks"])


async def test_sync_prunes_tombstones_but_keeps_drafts(client):
    """Sync drops bookmarks for deleted/missing resources and archived/missing courses, keeps live + drafts."""
    live = await _make_resource("admin", "Live book")
    dead = await _make_resource("admin", "Dead book")
    await db_exec("UPDATE resources SET status = 'deleted', deleted_at = datetime('now') WHERE id = ?", (dead,))
    draft = await _make_course("Draft course", published=0)
    archived = await _make_course("Archived course", published=-1)
    ghost_res = f"RES-{uuid.uuid4().hex[:12]}"
    ghost_course = f"CRS-{uuid.uuid4().hex[:12]}"
    _, token = await _make_student("s.bmprune")
    payload = {"bookmarks": [
        {"resource_id": live, "title": "Live", "subject": "General", "grade": "General", "resource_type": "textbook"},
        {"resource_id": dead, "title": "Dead", "subject": "General", "grade": "General", "resource_type": "textbook"},
        {"resource_id": ghost_res, "title": "Ghost", "subject": "General", "grade": "General", "resource_type": "textbook"},
        {"resource_id": draft, "title": "Draft", "subject": "General", "grade": "5", "resource_type": "course"},
        {"resource_id": archived, "title": "Archived", "subject": "General", "grade": "5", "resource_type": "course"},
        {"resource_id": ghost_course, "title": "Ghost course", "subject": "General", "grade": "5", "resource_type": "course"},
    ]}
    resp = await client.post("/student/sync-bookmarks", json=payload, headers=_auth(token))
    assert resp.status_code == 200, resp.text
    resp = await client.get("/student/bookmarks", headers=_auth(token))
    assert resp.status_code == 200, resp.text
    got = {b["resource_id"] for b in resp.json()["bookmarks"]}
    assert got == {live, draft}, f"expected only live + draft bookmarks, got: {got}"


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
