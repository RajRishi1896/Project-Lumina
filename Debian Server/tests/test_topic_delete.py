"""Chapter delete flows: ungroup, transfer, delete-with-resources (+files)."""
import os

import pytest


async def _make_course(admin_client, n_topics=2):
    """Create a course with topics; return (course_id, [topic_ids])."""
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Topic Delete", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    tids = []
    for i in range(n_topics):
        t = await admin_client.post(
            f"/api/teacher/courses/{cid}/topics", json={"title": f"Ch {i + 1}"})
        assert t.status_code == 200, t.text
        tids.append(t.json()["id"])
    return cid, tids


async def _upload(admin_client, cid, topic_id):
    """Upload one PDF into a topic; return (resource_id, filename)."""
    up = await admin_client.post(
        f"/api/teacher/courses/{cid}/upload-resource"
        f"?resource_type=document&title=Doc&topic_id={topic_id}",
        files={"file": ("doc.pdf", b"%PDF-1.4 fake", "application/pdf")})
    assert up.status_code == 200, up.text
    return up.json()["id"], up.json()["filename"]


@pytest.mark.asyncio
async def test_delete_plain_ungroups(admin_client):
    """Plain delete removes the topic and ungroups its resources."""
    from app.async_db import db_fetch_one
    cid, (t1, _t2) = await _make_course(admin_client)
    rid, _fn = await _upload(admin_client, cid, t1)
    r = await admin_client.delete(f"/api/teacher/courses/{cid}/topics/{t1}")
    assert r.status_code == 200, r.text
    row = await db_fetch_one("SELECT topic_id FROM course_resources WHERE id = ?", (rid,))
    assert row["topic_id"] == ""
    gone = await db_fetch_one("SELECT id FROM topics WHERE id = ?", (t1,))
    assert gone is None


@pytest.mark.asyncio
async def test_delete_transfer_moves(admin_client):
    """Transfer moves rows to the target topic before deleting."""
    from app.async_db import db_fetch_one
    cid, (t1, t2) = await _make_course(admin_client)
    rid, _fn = await _upload(admin_client, cid, t1)
    r = await admin_client.delete(
        f"/api/teacher/courses/{cid}/topics/{t1}?transfer_to={t2}")
    assert r.status_code == 200, r.text
    row = await db_fetch_one("SELECT topic_id FROM course_resources WHERE id = ?", (rid,))
    assert row["topic_id"] == t2
    gone = await db_fetch_one("SELECT id FROM topics WHERE id = ?", (t1,))
    assert gone is None


@pytest.mark.asyncio
async def test_delete_resources_removes_files(admin_client):
    """delete_resources removes DB rows AND the files from disk."""
    from app.async_db import db_fetch_one
    from app.routers.teacher_courses import COURSES_DIR
    cid, (t1, _t2) = await _make_course(admin_client)
    rid, fn = await _upload(admin_client, cid, t1)
    disk = os.path.join(COURSES_DIR, cid, "resources", fn)
    assert os.path.isfile(disk)
    r = await admin_client.delete(
        f"/api/teacher/courses/{cid}/topics/{t1}?delete_resources=true")
    assert r.status_code == 200, r.text
    gone = await db_fetch_one("SELECT id FROM course_resources WHERE id = ?", (rid,))
    assert gone is None
    assert not os.path.exists(disk), f"leaked file on disk: {disk}"


@pytest.mark.asyncio
async def test_delete_resources_removes_quiz_file(admin_client):
    """Quiz rows also drop their quiz JSON from disk."""
    from app.async_db import db_fetch_one
    from app.routers.teacher_courses import COURSES_DIR
    cid, (t1, _t2) = await _make_course(admin_client)
    q = await admin_client.post(f"/api/teacher/courses/{cid}/quiz", json={
        "title": "Q", "topic_id": t1, "time_limit_minutes": 0,
        "pass_threshold": 60, "max_attempts": 0, "shuffle_mode": "none",
        "questions": [{"id": "q1", "type": "mcq", "question": "2+2?",
                       "options": ["3", "4"], "correct_answer": 1}]})
    assert q.status_code == 200, q.text
    rid = q.json()["id"]
    disk = os.path.join(COURSES_DIR, cid, f"quiz_{rid}.json")
    assert os.path.isfile(disk)
    r = await admin_client.delete(
        f"/api/teacher/courses/{cid}/topics/{t1}?delete_resources=true")
    assert r.status_code == 200, r.text
    gone = await db_fetch_one("SELECT id FROM course_resources WHERE id = ?", (rid,))
    assert gone is None
    assert not os.path.exists(disk), f"leaked quiz file on disk: {disk}"


async def _make_lib_topic(admin_client, subject, name):
    """Create a library topic (creating its subject first); return topic id."""
    import uuid as _uuid
    s = await admin_client.post("/teacher/subjects",
                                json={"name": subject, "symbol": subject[:4].upper()})
    assert s.status_code in (200, 201, 400), s.text  # 400 = already seeded
    r = await admin_client.post("/teacher/resource-topics",
                                json={"subject": subject, "name": name or f"T-{_uuid.uuid4().hex[:8]}"})
    assert r.status_code == 200, r.text
    return r.json()["id"]


async def _upload_lib(admin_client, subject, topic_id):
    """Upload one PDF into a library topic; return (resource_id, filename)."""
    from app.async_db import db_fetch_one
    up = await admin_client.post(
        f"/teacher/upload?title=LibDoc&type=textbook&subject={subject}&grade=General&topic_id={topic_id}",
        files={"file": ("lib.pdf", b"%PDF-1.4 fake", "application/pdf")})
    assert up.status_code == 200, up.text
    fn = up.json()["filename"]
    row = await db_fetch_one("SELECT id FROM resources WHERE filename = ?", (fn,))
    return row["id"], fn


@pytest.mark.asyncio
async def test_lib_delete_transfer_moves(admin_client):
    """Library transfer moves rows to the target topic."""
    from app.async_db import db_fetch_one
    t1 = await _make_lib_topic(admin_client, "LibSub", None)
    t2 = await _make_lib_topic(admin_client, "LibSub", None)
    rid, _fn = await _upload_lib(admin_client, "LibSub", t1)
    r = await admin_client.delete(f"/teacher/resource-topics/{t1}?transfer_to={t2}")
    assert r.status_code == 200, r.text
    row = await db_fetch_one("SELECT topic_id FROM resources WHERE id = ?", (rid,))
    assert row["topic_id"] == t2


@pytest.mark.asyncio
async def test_lib_delete_resources_removes_files(admin_client):
    """Library delete removes DB rows and the files from disk."""
    import app.database as _db
    from app.async_db import db_fetch_one
    t1 = await _make_lib_topic(admin_client, "LibSub2", None)
    rid, fn = await _upload_lib(admin_client, "LibSub2", t1)
    disk = os.path.join(_db.UPLOAD_DIR, fn)
    assert os.path.isfile(disk)
    r = await admin_client.delete(f"/teacher/resource-topics/{t1}?delete_resources=true")
    assert r.status_code == 200, r.text
    gone = await db_fetch_one("SELECT id FROM resources WHERE id = ?", (rid,))
    assert gone is None
    assert not os.path.exists(disk), f"leaked file on disk: {disk}"


@pytest.mark.asyncio
async def test_lib_delete_plain_ungroups(admin_client):
    """Plain library delete ungroups resources into General."""
    from app.async_db import db_fetch_one
    t1 = await _make_lib_topic(admin_client, "LibSub3", None)
    rid, _fn = await _upload_lib(admin_client, "LibSub3", t1)
    r = await admin_client.delete(f"/teacher/resource-topics/{t1}")
    assert r.status_code == 200, r.text
    row = await db_fetch_one("SELECT topic_id FROM resources WHERE id = ?", (rid,))
    assert row["topic_id"] == ""
