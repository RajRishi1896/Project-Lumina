"""Teacher and student flashcard routes.

Teacher: deck CRUD plus the review workflow for student submissions.
Student: submit decks for approval, list published decks, list own submissions.
"""
import json
import uuid
from fastapi import APIRouter, Depends, HTTPException, Query
from app.async_db import db_conn, db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_teacher, verify_student

router = APIRouter()

MAX_TITLE = 120
MAX_CARD_TEXT = 200
MAX_CARDS = 100


def _validate_title(title: str) -> str:
    """Normalize and validate a deck or submission title.

    Raises:
        HTTPException: 400 if empty or longer than MAX_TITLE characters.
    """
    title = (title or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Title is required.")  # i18n: user-facing error message
    if len(title) > MAX_TITLE:
        raise HTTPException(status_code=400, detail=f"Title too long (max {MAX_TITLE} characters).")  # i18n: user-facing error message
    return title


def _validate_cards(cards) -> list[dict]:
    """Validate a card list and return it as clean {front, back} dicts.

    Requires 1..MAX_CARDS cards, each with non-empty front/back of at most
    MAX_CARD_TEXT characters.

    Raises:
        HTTPException: 400 on any violation.
    """
    if not isinstance(cards, list) or not cards:
        raise HTTPException(status_code=400, detail="At least one card is required.")  # i18n: user-facing error message
    if len(cards) > MAX_CARDS:
        raise HTTPException(status_code=400, detail=f"Too many cards (max {MAX_CARDS}).")  # i18n: user-facing error message
    cleaned = []
    for i, c in enumerate(cards):
        front = (c.get("front") or "").strip()
        back = (c.get("back") or "").strip()
        if not front or not back:
            raise HTTPException(status_code=400, detail=f"Card {i + 1} needs both front and back text.")  # i18n: user-facing error message
        if len(front) > MAX_CARD_TEXT or len(back) > MAX_CARD_TEXT:
            raise HTTPException(status_code=400, detail=f"Card {i + 1} text too long (max {MAX_CARD_TEXT} characters).")  # i18n: user-facing error message
        cleaned.append({"front": front, "back": back})
    return cleaned


@router.post("/api/teacher/flashcards/decks",
             summary="Create a flashcard deck",
             description="Creates a published deck owned by the calling teacher. topic_id is optional but must exist in resource_topics when given.",
             tags=["Flashcards"],
             responses={201: {"description": "Deck created"}, 400: {"description": "Invalid title or topic"}})
async def create_deck(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Create a new flashcard deck.

    Args:
        data: Dict with title and optional topic_id.
        teacher_user: Authenticated teacher username.

    Returns:
        Dict with the new deck id.
    """
    title = _validate_title(data.get("title"))
    topic_id = (data.get("topic_id") or "").strip()
    found = await db_fetch_one("SELECT id FROM resource_topics WHERE id = ?", (topic_id,))
    if topic_id and not found:
        raise HTTPException(status_code=400, detail="Topic does not exist.")  # i18n: user-facing error message
    deck_id = uuid.uuid4().hex
    await db_exec(
        "INSERT INTO flashcard_decks (id, title, topic_id, created_by, published) VALUES (?, ?, ?, ?, 1)",
        (deck_id, title, topic_id or None, teacher_user))
    return {"id": deck_id}


@router.get("/api/teacher/flashcards/decks",
            summary="List the teacher's flashcard decks",
            description="Returns all decks created by the calling teacher, each with its cards and card count, newest first.",
            tags=["Flashcards"])
async def list_decks(teacher_user: str = Depends(verify_teacher)):
    """List decks owned by the calling teacher.

    Returns:
        List of decks with title, topic_id, created_at, card_count, and cards.
    """
    rows = await db_fetch(
        "SELECT d.id, d.title, d.topic_id, d.created_at, c.front, c.back, c.position "
        "FROM flashcard_decks d LEFT JOIN flashcards c ON c.deck_id = d.id "
        "WHERE d.created_by = ? ORDER BY d.created_at DESC, c.position ASC",
        (teacher_user,))
    decks: dict[str, dict] = {}
    for r in rows:
        d = decks.setdefault(r["id"], {
            "id": r["id"], "title": r["title"], "topic_id": r["topic_id"] or "",
            "created_at": r["created_at"], "cards": [], "card_count": 0,
        })
        if r["front"] is not None:
            d["cards"].append({"front": r["front"], "back": r["back"]})
            d["card_count"] += 1
    return list(decks.values())


async def _own_deck(deck_id: str, teacher_user: str):
    """Fetch a deck row, raising 404 if missing or not owned by the teacher.

    Returns:
        The deck row as a dict.
    """
    deck = await db_fetch_one("SELECT * FROM flashcard_decks WHERE id = ?", (deck_id,))
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found.")  # i18n: user-facing error message
    if deck["created_by"] != teacher_user:
        raise HTTPException(status_code=403, detail="You can only edit your own decks.")  # i18n: user-facing error message
    return deck


@router.put("/api/teacher/flashcards/decks/{deck_id}",
            summary="Rename a flashcard deck",
            description="Updates the title and optional topic of a deck owned by the calling teacher.",
            tags=["Flashcards"])
async def update_deck(deck_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Rename a deck and optionally reassign its topic.

    Raises:
        HTTPException: 404 if missing, 403 if owned by another teacher.
    """
    await _own_deck(deck_id, teacher_user)
    title = _validate_title(data.get("title"))
    topic_id = (data.get("topic_id") or "").strip()
    if topic_id:
        found = await db_fetch_one("SELECT id FROM resource_topics WHERE id = ?", (topic_id,))
        if not found:
            raise HTTPException(status_code=400, detail="Topic does not exist.")  # i18n: user-facing error message
    await db_exec("UPDATE flashcard_decks SET title = ?, topic_id = ? WHERE id = ?",
                  (title, topic_id or None, deck_id))
    return {"status": "ok"}


@router.delete("/api/teacher/flashcards/decks/{deck_id}",
               summary="Delete a flashcard deck",
               description="Deletes a deck and all its cards. Only the owning teacher can delete it.",
               tags=["Flashcards"])
async def delete_deck(deck_id: str, teacher_user: str = Depends(verify_teacher)):
    """Delete a deck and its cards in one transaction.

    Raises:
        HTTPException: 404 if missing, 403 if owned by another teacher.
    """
    await _own_deck(deck_id, teacher_user)
    async with db_conn() as conn:
        conn.execute("DELETE FROM flashcards WHERE deck_id = ?", (deck_id,))
        conn.execute("DELETE FROM flashcard_decks WHERE id = ?", (deck_id,))
        conn.commit()
    return {"status": "ok"}


@router.put("/api/teacher/flashcards/decks/{deck_id}/cards",
            summary="Replace all cards in a deck",
            description="Replaces the full card list of a deck owned by the calling teacher. Cards are validated (1..100, non-empty front/back, max 200 characters each).",
            tags=["Flashcards"])
async def replace_cards(deck_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Replace all cards of a deck.

    Raises:
        HTTPException: 404 if missing, 403 if owned by another teacher, 400 on invalid cards.
    """
    await _own_deck(deck_id, teacher_user)
    cards = _validate_cards(data.get("cards"))
    async with db_conn() as conn:
        conn.execute("DELETE FROM flashcards WHERE deck_id = ?", (deck_id,))
        conn.executemany(
            "INSERT INTO flashcards (id, deck_id, front, back, position) VALUES (?, ?, ?, ?, ?)",
            [(uuid.uuid4().hex, deck_id, c["front"], c["back"], i) for i, c in enumerate(cards)])
        conn.commit()
    return {"status": "ok", "card_count": len(cards)}


@router.get("/api/teacher/flashcards/submissions",
            summary="List student flashcard submissions",
            description="Returns student submissions joined with student names, optionally filtered by status (pending/approved/rejected).",
            tags=["Flashcards"])
async def list_submissions(status: str = Query(None, description="Filter by status: pending, approved, rejected"),
                           teacher_user: str = Depends(verify_teacher)):
    """List student submissions for teacher review.

    Returns:
        List of submissions with student_name, title, card_count, status, and reason.
    """
    sql = ("SELECT s.id, s.student_id, s.title, s.cards_json, s.status, s.created_at, "
           "s.reviewed_by, s.reviewed_at, s.reason, COALESCE(sch.name, '') AS student_name "
           "FROM flashcard_submissions s LEFT JOIN scholars sch ON sch.id = s.student_id")
    params: tuple = ()
    if status:
        sql += " WHERE s.status = ?"
        params = (status,)
    sql += " ORDER BY s.created_at DESC"
    rows = await db_fetch(sql, params)
    result = []
    for r in rows:
        try:
            cards = json.loads(r["cards_json"])
            card_count = len(cards) if isinstance(cards, list) else 0
        except (json.JSONDecodeError, TypeError):
            card_count = 0
        item = dict(r)
        item.pop("cards_json", None)
        item["card_count"] = card_count
        result.append(item)
    return result


async def _get_submission(submission_id: str):
    """Fetch a submission row, raising 404 if missing.

    Returns:
        The submission row as a dict.
    """
    sub = await db_fetch_one("SELECT * FROM flashcard_submissions WHERE id = ?", (submission_id,))
    if not sub:
        raise HTTPException(status_code=404, detail="Submission not found.")  # i18n: user-facing error message
    return sub


@router.post("/api/teacher/flashcards/submissions/{submission_id}/approve",
             summary="Approve a student submission into a published deck",
             description="Creates a published deck owned by the approving teacher with the submission's cards, and marks the submission approved. Returns the new deck id.",
             tags=["Flashcards"],
             responses={200: {"description": "Approved, deck created"}, 409: {"description": "Submission already reviewed"}})
async def approve_submission(submission_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Approve a pending submission.

    Raises:
        HTTPException: 404 if missing, 409 if already reviewed.
    """
    sub = await _get_submission(submission_id)
    if sub["status"] != "pending":
        raise HTTPException(status_code=409, detail="Submission has already been reviewed.")  # i18n: user-facing error message
    try:
        cards = _validate_cards(json.loads(sub["cards_json"]))
    except (json.JSONDecodeError, TypeError):
        raise HTTPException(status_code=400, detail="Submission cards are invalid.")  # i18n: user-facing error message
    topic_id = (data.get("topic_id") or "").strip()
    if topic_id:
        found = await db_fetch_one("SELECT id FROM resource_topics WHERE id = ?", (topic_id,))
        if not found:
            raise HTTPException(status_code=400, detail="Topic does not exist.")  # i18n: user-facing error message
    deck_id = uuid.uuid4().hex
    async with db_conn() as conn:
        conn.execute(
            "INSERT INTO flashcard_decks (id, title, topic_id, created_by, published) VALUES (?, ?, ?, ?, 1)",
            (deck_id, sub["title"], topic_id or None, teacher_user))
        conn.executemany(
            "INSERT INTO flashcards (id, deck_id, front, back, position) VALUES (?, ?, ?, ?, ?)",
            [(uuid.uuid4().hex, deck_id, c["front"], c["back"], i) for i, c in enumerate(cards)])
        conn.execute(
            "UPDATE flashcard_submissions SET status = 'approved', reviewed_by = ?, reviewed_at = datetime('now') WHERE id = ?",
            (teacher_user, submission_id))
        conn.commit()
    return {"deck_id": deck_id}


@router.post("/api/teacher/flashcards/submissions/{submission_id}/reject",
             summary="Reject a student submission",
             description="Marks a pending submission as rejected with an optional reason. Returns 409 if the submission was already reviewed.",
             tags=["Flashcards"])
async def reject_submission(submission_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Reject a pending submission.

    Raises:
        HTTPException: 404 if missing, 409 if already reviewed.
    """
    sub = await _get_submission(submission_id)
    if sub["status"] != "pending":
        raise HTTPException(status_code=409, detail="Submission has already been reviewed.")  # i18n: user-facing error message
    reason = (data.get("reason") or "").strip()[:500]
    await db_exec(
        "UPDATE flashcard_submissions SET status = 'rejected', reviewed_by = ?, reviewed_at = datetime('now'), reason = ? WHERE id = ?",
        (teacher_user, reason or None, submission_id))
    return {"status": "ok"}


@router.post("/api/flashcards/submit",
             summary="Submit a flashcard deck for teacher approval",
             description="Creates a pending submission from a student's card list. Decks are not published until a teacher approves them.",
             tags=["Flashcards"],
             responses={201: {"description": "Submission created"}, 400: {"description": "Invalid title or cards"}})
async def submit_deck(data: dict, student_id: str = Depends(verify_student)):
    """Submit a deck for approval.

    Args:
        data: Dict with title and cards list.
        student_id: Scholar id from the session.

    Returns:
        Dict with the submission id.
    """
    title = _validate_title(data.get("title"))
    cards = _validate_cards(data.get("cards"))
    submission_id = uuid.uuid4().hex
    await db_exec(
        "INSERT INTO flashcard_submissions (id, student_id, title, cards_json, status) VALUES (?, ?, ?, ?, 'pending')",
        (submission_id, student_id, title, json.dumps(cards)))
    return {"id": submission_id, "status": "pending"}


@router.get("/api/flashcards/decks",
            summary="List published flashcard decks",
            description="Returns published decks with their full cards, optionally filtered by topic_id. Used by the app to sync deck content.",
            tags=["Flashcards"])
async def published_decks(topic_id: str = Query(None, description="Filter by resource topic id"),
                          student_id: str = Depends(verify_student)):
    """List published decks with full cards.

    Returns:
        List of decks with title, topic_id, created_at, and cards.
    """
    sql = ("SELECT d.id, d.title, d.topic_id, d.created_at, c.front, c.back, c.position "
           "FROM flashcard_decks d LEFT JOIN flashcards c ON c.deck_id = d.id "
           "WHERE d.published = 1")
    params: tuple = ()
    if topic_id:
        sql += " AND d.topic_id = ?"
        params = (topic_id,)
    sql += " ORDER BY d.created_at DESC, c.position ASC"
    rows = await db_fetch(sql, params)
    decks: dict[str, dict] = {}
    for r in rows:
        d = decks.setdefault(r["id"], {
            "id": r["id"], "title": r["title"], "topic_id": r["topic_id"] or "",
            "created_at": r["created_at"], "cards": [],
        })
        if r["front"] is not None:
            d["cards"].append({"front": r["front"], "back": r["back"]})
    return list(decks.values())


@router.get("/api/flashcards/my-submissions",
            summary="List a student's own submissions",
            description="Returns the calling student's submissions with status and review reason, newest first.",
            tags=["Flashcards"])
async def my_submissions(student_id: str = Depends(verify_student)):
    """List the student's own submissions.

    Returns:
        List of submissions with title, status, and reason.
    """
    rows = await db_fetch(
        "SELECT id, title, status, reason, created_at FROM flashcard_submissions "
        "WHERE student_id = ? ORDER BY created_at DESC",
        (student_id,))
    return [dict(r) for r in rows]
