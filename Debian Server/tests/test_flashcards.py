"""Tests for the flashcard feature: teacher deck CRUD and student submissions.

Covers: deck creation/cards, student submit, teacher approve/reject workflow,
role enforcement (student cannot approve), deck ownership, and validation.
"""
import json
import uuid

from app.async_db import db_exec
from app.dependencies import hash_password


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


async def _make_student(name):
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
    token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    await db_exec(
        "INSERT INTO users (username, hashed_password, name, role) VALUES (?, ?, ?, 'teacher')",
        (name, hash_password("TestPass123"), name))
    await db_exec(
        "INSERT INTO sessions (token, username, role, used, expiry) VALUES (?, ?, 'teacher', 0, datetime('now', '+1 day'))",
        (token, name))
    return name, token


CARDS = [{"front": "2+2?", "back": "4"}]


async def test_create_deck_and_replace_cards(client, admin_client):
    resp = await admin_client.post("/api/teacher/flashcards/decks",
                                   json={"title": "Maths basics", "topic_id": ""})
    assert resp.status_code == 200, resp.text
    deck_id = resp.json()["id"]

    resp = await admin_client.put(f"/api/teacher/flashcards/decks/{deck_id}/cards",
                                  json={"cards": CARDS})
    assert resp.status_code == 200
    assert resp.json()["card_count"] == 1

    resp = await admin_client.get("/api/teacher/flashcards/decks")
    assert resp.status_code == 200
    decks = resp.json()
    assert any(d["id"] == deck_id and d["card_count"] == 1 for d in decks)


async def test_submit_and_approve_flow(client, admin_client):
    _, student_token = await _make_student("s1")
    resp = await client.post("/api/flashcards/submit",
                             json={"title": "My deck", "cards": CARDS},
                             headers=_auth(student_token))
    assert resp.status_code == 200, resp.text
    sub_id = resp.json()["id"]
    assert resp.json()["status"] == "pending"

    # Student cannot approve (teacher-only).
    resp = await client.post(f"/api/teacher/flashcards/submissions/{sub_id}/approve",
                             json={}, headers=_auth(student_token))
    assert resp.status_code == 403

    # Teacher approves into a new published deck.
    resp = await admin_client.post(f"/api/teacher/flashcards/submissions/{sub_id}/approve",
                                   json={"topic_id": ""})
    assert resp.status_code == 200, resp.text
    deck_id = resp.json()["deck_id"]

    # Student now sees the published deck with cards.
    resp = await client.get("/api/flashcards/decks", headers=_auth(student_token))
    assert resp.status_code == 200
    assert any(d["id"] == deck_id and len(d["cards"]) == 1 for d in resp.json())

    # Second approval is rejected (409).
    resp = await admin_client.post(f"/api/teacher/flashcards/submissions/{sub_id}/approve",
                                   json={})
    assert resp.status_code == 409


async def test_reject_stores_reason(client, admin_client):
    _, student = await _student(client, "r")
    resp = await client.post("/api/flashcards/submit",
                             json={"title": "Bad deck", "cards": CARDS},
                             headers=_auth(student))
    sub_id = resp.json()["id"]

    resp = await admin_client.post(f"/api/teacher/flashcards/submissions/{sub_id}/reject",
                                   json={"reason": "Too short"})
    assert resp.status_code == 200

    resp = await client.get("/api/flashcards/my-submissions", headers=_auth(student))
    assert resp.status_code == 200
    subs = resp.json()
    assert len(subs) == 1 and subs[0]["status"] == "rejected" and subs[0]["reason"] == "Too short"


async def test_deck_ownership(client, admin_client):
    resp = await admin_client.post("/api/teacher/flashcards/decks",
                                   json={"title": "A's deck", "topic_id": ""})
    deck_id = resp.json()["id"]
    _, other = await _make_teacher("other.teacher")

    resp = await client.put(f"/api/teacher/flashcards/decks/{deck_id}",
                            json={"title": "Hijacked"}, headers=_auth(other))
    assert resp.status_code == 403
    resp = await client.delete(f"/api/teacher/flashcards/decks/{deck_id}",
                               headers=_auth(other))
    assert resp.status_code == 403


async def test_validation(client, admin_client):
    resp = await admin_client.post("/api/teacher/flashcards/decks",
                                   json={"title": "  ", "topic_id": ""})
    assert resp.status_code == 400

    resp = await admin_client.post("/api/teacher/flashcards/decks",
                                   json={"title": "x" * 130, "topic_id": ""})
    assert resp.status_code == 400

    ok = await admin_client.post("/api/teacher/flashcards/decks",
                                 json={"title": "Full", "topic_id": ""})
    deck_id = ok.json()["id"]
    resp = await admin_client.put(f"/api/teacher/flashcards/decks/{deck_id}/cards",
                                  json={"cards": [{"front": "f", "back": ""}]})
    assert resp.status_code == 400
    resp = await admin_client.put(f"/api/teacher/flashcards/decks/{deck_id}/cards",
                                  json={"cards": []})
    assert resp.status_code == 400


async def test_student_submit_validation(client, admin_client):
    _, student = await _student(client, "v")
    resp = await client.post("/api/flashcards/submit",
                             json={"title": "", "cards": CARDS}, headers=_auth(student))
    assert resp.status_code == 400
    resp = await client.post("/api/flashcards/submit",
                             json={"title": "D", "cards": [{"front": "a", "back": ""}]},
                             headers=_auth(student))
    assert resp.status_code == 400


async def _student(client, name):
    return await _make_student(name)