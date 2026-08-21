"""Regression tests for quiz integrity fixes (audit batch).

Covers: server-side re-grading (client score/passed ignored), attempt
ownership on idempotent resubmission, enrollment gating on progress sync,
published-only course visibility, resource-type/status validation for
standalone quiz submits, title updates persisting, answer keys stripped
from every quiz-serving route, quiz answer-key JSON blocked on the /files
mount, and best-score upserts bounded by server-graded attempts.
"""
import json
import os
import shutil
import uuid

import pytest

from app.async_db import db_exec, db_fetch_one
from app.database import UPLOAD_DIR
from app.dependencies import hash_password
from app.routers.teacher_courses import COURSES_DIR

TWO_Q = [
    {"id": "q1", "type": "mcq", "question": "1+1?", "options": ["2", "3"], "correct_answer": 0},
    {"id": "q2", "type": "mcq", "question": "2+2?", "options": ["4", "5"], "correct_answer": 0},
]


def _answers_json(*pairs):
    """Flutter-style answers payload: display index -> {answer, question_id}."""
    answers = {}
    for i, (question_id, answer) in enumerate(pairs):
        answers[str(i)] = {"answer": answer, "question_id": question_id}
    return json.dumps({"answers": answers})


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


async def _seed_course(published=1):
    """Insert a course row; return its id."""
    cid = str(uuid.uuid4())
    await db_exec(
        "INSERT INTO courses (id, title, subject, grade, language, published, teacher_username) VALUES (?, ?, 'math', 'General', 'en', ?, 'admin')",
        (cid, "Test Course", published))
    return cid


async def _seed_course_quiz(cid, questions=TWO_Q, pass_threshold=60):
    """Seed a course-bound quiz resource and its JSON file; return resource id."""
    rid = str(uuid.uuid4())
    await db_exec(
        "INSERT INTO course_resources (id, course_id, resource_type, title, original_name, filename, file_size, position) VALUES (?, ?, 'quiz', 'Quiz', 'quiz.json', ?, 100, 0)",
        (rid, cid, f"quiz_{rid}.json"))
    quiz_dir = os.path.join(COURSES_DIR, cid)
    os.makedirs(quiz_dir, exist_ok=True)
    with open(os.path.join(quiz_dir, f"quiz_{rid}.json"), "w") as f:
        json.dump({"quiz": {"title": "Quiz", "questions": questions,
                            "pass_threshold": pass_threshold, "quiz_version": 1}}, f)
    return rid


async def _seed_standalone_quiz(resource_type="quiz", status="approved"):
    """Seed a standalone quiz resource and its JSON file; return resource id."""
    rid = str(uuid.uuid4())
    fname = f"{rid}.quiz"
    with open(os.path.join(UPLOAD_DIR, fname), "w") as f:
        json.dump({"quiz": {"title": "Quiz", "questions": TWO_Q,
                            "pass_threshold": 60, "quiz_version": 1}}, f)
    await db_exec(
        "INSERT INTO resources (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, uploaded_at, status, file_size) VALUES (?, 'Quiz', 'math', 'General', 'en', ?, ?, 'quiz.json', 'Teacher', 'Internal Only', 'admin', datetime('now'), ?, 100)",
        (rid, resource_type, fname, status))
    return rid


def _attempt_payload(attempt_id, answers_json, score=0.0, passed=0):
    """Build a Flutter-style attempt submission payload."""
    return {"attempt_id": attempt_id, "attempt_number": 1, "score": score, "passed": passed,
            "answers_json": answers_json, "started_at": "", "submitted_at": "",
            "time_taken_seconds": 10, "quiz_version": 1, "threshold_at_submission": 0.6}


@pytest.mark.asyncio
async def test_fabricated_score_is_regraded(client):
    """A client that self-reports score=100 is graded by the server instead."""
    _, token = await _make_student("stu_a")
    cid = await _seed_course()
    rid = await _seed_course_quiz(cid, pass_threshold=75)
    await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))

    # One correct, one wrong, but the client claims a perfect score.
    payload = _attempt_payload("att-fab", _answers_json(("q1", "2"), ("q2", "5")),
                               score=1.0, passed=1)
    resp = await client.post(f"/api/courses/{cid}/quiz/{rid}/submit", headers=_auth(token), json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["score"] == 0.5, "server must grade, not trust the client's 1.0"
    assert body["passed"] == 0, "0.5 is below the 0.75 threshold; must not pass"
    assert body["threshold_at_submission"] == 0.75


@pytest.mark.asyncio
async def test_submit_returns_per_question_results(client):
    """The submit response carries per-question grading for the review screen.

    The served quiz strips the answer key (the client cannot grade locally),
    so the key must arrive only AFTER the attempt is stored.
    """
    _, token = await _make_student("stu_results")
    cid = await _seed_course()
    rid = await _seed_course_quiz(cid, pass_threshold=75)
    await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))

    payload = _attempt_payload("att-results", _answers_json(("q1", "2"), ("q2", "5")))
    resp = await client.post(f"/api/courses/{cid}/quiz/{rid}/submit", headers=_auth(token), json=payload)
    assert resp.status_code == 200
    body = resp.json()
    results = body["results"]
    assert isinstance(results, list) and len(results) == 2
    assert results[0]["question_id"] == "q1"
    assert results[0]["correct"] is True
    assert results[0]["correct_answers"] == ["2"], "key resolves to option text"
    assert results[1]["question_id"] == "q2"
    assert results[1]["correct"] is False
    assert results[1]["correct_answers"] == ["4"]
    # The aggregate must agree with the per-question verdicts.
    assert body["score"] == 0.5


@pytest.mark.asyncio
async def test_standalone_submit_returns_results(client):
    """Standalone quiz submits return the same per-question results shape."""
    _, token = await _make_student("stu_sa_results")
    rid = await _seed_standalone_quiz()

    payload = _attempt_payload("att-sa-results", _answers_json(("q1", "3"), ("q2", "4")))
    resp = await client.post(f"/api/quiz-resource/{rid}/submit", headers=_auth(token), json=payload)
    assert resp.status_code == 200
    results = resp.json()["results"]
    assert len(results) == 2
    assert results[0]["correct"] is False
    assert results[0]["correct_answers"] == ["2"]
    assert results[1]["correct"] is True
    assert results[1]["correct_answers"] == ["4"]
    assert resp.json()["score"] == 0.5


@pytest.mark.asyncio
async def test_attempt_idempotency_scoped_to_owner(client):
    """Resubmitting another student's attempt_id must not return their data."""
    _, token1 = await _make_student("stu_b1")
    _, token2 = await _make_student("stu_b2")
    cid = await _seed_course()
    rid = await _seed_course_quiz(cid)
    for tok in (token1, token2):
        await client.post(f"/api/courses/{cid}/enroll", headers=_auth(tok))

    payload = _attempt_payload("att-owner", _answers_json(("q1", "2"), ("q2", "4")))
    ok = await client.post(f"/api/courses/{cid}/quiz/{rid}/submit", headers=_auth(token1), json=payload)
    assert ok.status_code == 200

    stolen = await client.post(f"/api/courses/{cid}/quiz/{rid}/submit", headers=_auth(token2), json=payload)
    assert stolen.status_code in (403, 404)
    assert "score" not in stolen.text, "attempt data must not leak"


@pytest.mark.asyncio
async def test_standalone_attempt_idempotency_scoped_to_owner(client):
    """Same ownership rule for standalone quiz submits."""
    _, token1 = await _make_student("stu_b3")
    _, token2 = await _make_student("stu_b4")
    rid = await _seed_standalone_quiz()

    payload = _attempt_payload("att-sa", _answers_json(("q1", "2"), ("q2", "4")))
    ok = await client.post(f"/api/quiz-resource/{rid}/submit", headers=_auth(token1), json=payload)
    assert ok.status_code == 200

    stolen = await client.post(f"/api/quiz-resource/{rid}/submit", headers=_auth(token2), json=payload)
    assert stolen.status_code in (403, 404)
    assert "score" not in stolen.text


@pytest.mark.asyncio
async def test_sync_progress_unpublished_course_404(client):
    """Progress sync on an unpublished course is rejected and creates no row."""
    sid, token = await _make_student("stu_c1")
    cid = await _seed_course(published=0)

    resp = await client.put(f"/api/courses/{cid}/progress", headers=_auth(token),
                            json={"current_position": 1, "completed_count": 1})
    assert resp.status_code == 404
    row = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (sid, cid))
    assert row is None, "no enrollment row may be created by progress sync"


@pytest.mark.asyncio
async def test_sync_progress_unenrolled_course_404(client):
    """Progress sync never auto-enrolls a student into a published course."""
    sid, token = await _make_student("stu_c2")
    cid = await _seed_course(published=1)

    resp = await client.put(f"/api/courses/{cid}/progress", headers=_auth(token),
                            json={"current_position": 1, "completed_count": 1})
    assert resp.status_code == 404
    row = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (sid, cid))
    assert row is None


@pytest.mark.asyncio
async def test_course_detail_unpublished_404(client):
    """Students must not see detail for unpublished courses."""
    _, token = await _make_student("stu_d")
    cid = await _seed_course(published=0)

    resp = await client.get(f"/api/courses/{cid}", headers=_auth(token))
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_standalone_submit_requires_approved_quiz(client):
    """Standalone submit accepts only approved quiz resources, and re-grades."""
    _, token = await _make_student("stu_e")
    rid = await _seed_standalone_quiz()

    # All-correct answers but the client claims a score of 0; server grades 1.0.
    payload = _attempt_payload("att-e1", _answers_json(("q1", "2"), ("q2", "4")), score=0.0, passed=0)
    resp = await client.post(f"/api/quiz-resource/{rid}/submit", headers=_auth(token), json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["score"] == 1.0
    assert body["passed"] == 1

    bad_type = await _seed_standalone_quiz(resource_type="textbook")
    resp = await client.post(f"/api/quiz-resource/{bad_type}/submit", headers=_auth(token),
                             json=_attempt_payload("att-e2", _answers_json(("q1", "2"), ("q2", "4"))))
    assert resp.status_code == 404

    pending = await _seed_standalone_quiz(status="pending")
    resp = await client.post(f"/api/quiz-resource/{pending}/submit", headers=_auth(token),
                             json=_attempt_payload("att-e3", _answers_json(("q1", "2"), ("q2", "4"))))
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_title_update_persists(admin_client):
    """PUT with a new title must actually persist it (tautology bug)."""
    resp = await admin_client.post("/api/teacher/quiz-resource", json={
        "title": "Old Title",
        "questions": [{"id": "q1", "type": "mcq", "question": "Q?", "options": ["A", "B"], "correct_answer": 0}],
    })
    assert resp.status_code == 200
    rid = resp.json()["id"]

    up = await admin_client.put(f"/api/teacher/quiz-resource/{rid}", json={
        "title": "New Title",
        "questions": [{"id": "q1", "type": "mcq", "question": "Q?", "options": ["A", "B"], "correct_answer": 0}],
    })
    assert up.status_code == 200

    row = await db_fetch_one("SELECT title FROM resources WHERE id = ?", (rid,))
    assert row["title"] == "New Title"


# ── Answer-key stripping on served quizzes ───────────────────────────

ANSWER_KEY_QUESTIONS = [
    {"id": "q1", "type": "mcq", "question": "1+1?", "options": ["2", "3"],
     "correct_answer": 0, "explanation": "Basic addition."},
    {"id": "q2", "type": "multi", "question": "Even numbers?", "options": ["1", "2"],
     "correct_answers": [1], "explanation": "2 is even."},
]


def _assert_no_answer_keys(questions):
    """Assert every served question carries no answer-key fields."""
    for q in questions:
        assert "correct_answer" not in q, f"correct_answer leaked: {q}"
        assert "correct_answers" not in q, f"correct_answers leaked: {q}"
        assert "explanation" not in q, f"explanation leaked: {q}"
        assert set(q.keys()) <= {"id", "question", "type", "options", "image"}, \
            f"Unexpected question field(s): {set(q.keys())}"


@pytest.mark.asyncio
async def test_course_quiz_served_without_answer_keys(client):
    """GET course quiz strips the answer key; grading stays server-side."""
    _, token = await _make_student("stu_f1")
    cid = await _seed_course()
    rid = await _seed_course_quiz(cid, questions=ANSWER_KEY_QUESTIONS)
    await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))

    resp = await client.get(f"/api/courses/{cid}/quiz/{rid}", headers=_auth(token))
    assert resp.status_code == 200
    quiz = resp.json()["quiz"]
    _assert_no_answer_keys(quiz["questions"])

    # Display fields survive the strip.
    assert quiz["questions"][0]["question"] == "1+1?"
    assert quiz["questions"][0]["options"] == ["2", "3"]
    assert quiz["questions"][0]["id"] == "q1"

    # The on-disk file still has the key: submitting is graded server-side.
    payload = _attempt_payload("att-strip1", _answers_json(("q1", "2"), ("q2", "1")))
    sub = await client.post(f"/api/courses/{cid}/quiz/{rid}/submit",
                            headers=_auth(token), json=payload)
    assert sub.status_code == 200
    assert sub.json()["score"] == 0.5


@pytest.mark.asyncio
async def test_standalone_quiz_served_without_answer_keys(client):
    """GET standalone quiz strips the answer key too."""
    rid = await _seed_standalone_quiz()
    _, token = await _make_student("stu_f2")

    resp = await client.get(f"/api/quiz-resource/{rid}", headers=_auth(token))
    assert resp.status_code == 200
    _assert_no_answer_keys(resp.json()["quiz"]["questions"])


@pytest.mark.asyncio
async def test_files_mount_blocks_quiz_answer_keys(client):
    """/files must 404 quiz answer-key JSON at any depth; other files serve."""
    cid = str(uuid.uuid4())
    rid = str(uuid.uuid4())

    # The /files mount serves ./uploads relative to the server CWD (not the
    # test temp UPLOAD_DIR), so seed the block test there and clean up.
    served_courses = os.path.join(os.path.abspath("uploads"), "courses", cid)
    os.makedirs(served_courses, exist_ok=True)
    try:
        with open(os.path.join(served_courses, f"quiz_{rid}.json"), "w") as f:
            json.dump({"quiz": {"questions": ANSWER_KEY_QUESTIONS}}, f)
        with open(os.path.join(served_courses, "plain.txt"), "w") as f:
            f.write("not a quiz")

        blocked = await client.get(f"/files/courses/{cid}/quiz_{rid}.json")
        assert blocked.status_code == 404, "answer-key JSON must not be downloadable"

        ok = await client.get(f"/files/courses/{cid}/plain.txt")
        assert ok.status_code == 200, "non-quiz uploads must keep serving"
    finally:
        shutil.rmtree(served_courses, ignore_errors=True)


# ── Best-score upserts bounded by server-graded attempts ────────────

@pytest.mark.asyncio
async def test_course_best_score_bounded_by_graded_attempt(client):
    """Best score requires an owned attempt and never exceeds its grade."""
    sid, token = await _make_student("stu_g1")
    _, token2 = await _make_student("stu_g2")
    cid = await _seed_course()
    rid = await _seed_course_quiz(cid)
    await client.post(f"/api/courses/{cid}/enroll", headers=_auth(token))

    # Server grades this attempt at 0.5 (one of two correct).
    payload = _attempt_payload("att-bs1", _answers_json(("q1", "2"), ("q2", "5")))
    sub = await client.post(f"/api/courses/{cid}/quiz/{rid}/submit",
                            headers=_auth(token), json=payload)
    assert sub.json()["score"] == 0.5

    base = f"/student/quiz-best-score/{cid}/{rid}"

    # Unknown attempt -> 404, no row written.
    missing = await client.post(base, headers=_auth(token),
                                json={"score": 1.0, "attempt_id": "att-ghost"})
    assert missing.status_code == 404

    # Another student's attempt -> 403.
    stolen = await client.post(base, headers=_auth(token2),
                               json={"score": 1.0, "attempt_id": "att-bs1"})
    assert stolen.status_code == 403

    # Same student, different quiz's attempt -> 403.
    cid2 = await _seed_course()
    rid2 = await _seed_course_quiz(cid2)
    await client.post(f"/api/courses/{cid2}/enroll", headers=_auth(token))
    p2 = _attempt_payload("att-bs2", _answers_json(("q1", "2"), ("q2", "4")))
    await client.post(f"/api/courses/{cid2}/quiz/{rid2}/submit",
                      headers=_auth(token), json=p2)
    mismatch = await client.post(base, headers=_auth(token),
                                 json={"score": 1.0, "attempt_id": "att-bs2"})
    assert mismatch.status_code == 403

    # Out-of-range score -> 422 (Pydantic bounds).
    bogus = await client.post(base, headers=_auth(token),
                              json={"score": 1.5, "attempt_id": "att-bs1"})
    assert bogus.status_code == 422

    # A score above the graded 0.5 is clamped to 0.5.
    ok = await client.post(base, headers=_auth(token),
                           json={"score": 1.0, "attempt_id": "att-bs1"})
    assert ok.status_code == 200
    row = await db_fetch_one(
        "SELECT best_score FROM quiz_best_scores WHERE scholar_id = ? AND course_id = ? AND resource_id = ?",
        (sid, cid, rid))
    assert row["best_score"] == 0.5, "recorded best score must not exceed the graded attempt"


@pytest.mark.asyncio
async def test_standalone_best_score_bounded_by_graded_attempt(client):
    """Standalone variant: 422 on bad payloads, ownership and clamping enforced."""
    sid, token = await _make_student("stu_h1")
    rid = await _seed_standalone_quiz()

    payload = _attempt_payload("att-sbs", _answers_json(("q1", "2"), ("q2", "5")))
    sub = await client.post(f"/api/quiz-resource/{rid}/submit",
                            headers=_auth(token), json=payload)
    assert sub.json()["score"] == 0.5

    base = f"/api/quiz-resource/{rid}/best-score"

    # Non-numeric score must 422, not 500.
    bad_type = await client.post(base, headers=_auth(token),
                                 json={"score": "high", "attempt_id": "att-sbs"})
    assert bad_type.status_code == 422

    missing = await client.post(base, headers=_auth(token),
                                json={"score": 0.4, "attempt_id": "att-ghost"})
    assert missing.status_code == 404

    ok = await client.post(base, headers=_auth(token),
                           json={"score": 1.0, "attempt_id": "att-sbs"})
    assert ok.status_code == 200
    row = await db_fetch_one(
        "SELECT best_score FROM quiz_best_scores WHERE scholar_id = ? AND course_id = '' AND resource_id = ?",
        (sid, rid))
    assert row["best_score"] == 0.5, "recorded best score must not exceed the graded attempt"
