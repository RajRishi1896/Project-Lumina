"""Standalone quiz resources -- upload, serve, submit."""
import os
import uuid
import json
import asyncio
from fastapi import APIRouter, Depends, HTTPException
from app.dependencies import verify_teacher, verify_student
from app.async_db import db_exec, db_fetch_one
from app.database import UPLOAD_DIR

router = APIRouter()


@router.post("/api/teacher/quiz-resource",
             summary="Create a standalone quiz resource", tags=["Teacher"],
             responses={201: {"description": "Quiz resource created"}, 400: {"description": "Invalid data"}})
async def create_quiz_resource(data: dict, teacher_user: str = Depends(verify_teacher)):
    """Create a standalone quiz resource (not bound to a course).
    Validates quiz structure, saves JSON to uploads/{id}.quiz,
    creates a resources row with resource_type='quiz'.
    """
    questions = data.get("questions")
    if not isinstance(questions, list) or len(questions) == 0:
        raise HTTPException(status_code=400, detail="Quiz must have at least one question.")
    for i, q in enumerate(questions):
        if not all(k in q for k in ("id", "type", "question")):
            raise HTTPException(status_code=400, detail=f"Question at index {i} is missing one of: id, type, question.")

    resource_id = str(uuid.uuid4())
    title = data.get("title", "Quiz")
    filename = f"{resource_id}.quiz"

    quiz = {
        "title": title,
        "questions": questions,
        "time_limit_minutes": data.get("time_limit_minutes", 0),
        "pass_threshold": data.get("pass_threshold", 60),
        "max_attempts": data.get("max_attempts", 0),
        "shuffle_mode": data.get("shuffle_mode", "none"),
        "quiz_version": 1,
    }

    def _save():
        path = os.path.join(UPLOAD_DIR, filename)
        with open(path, "w") as f:
            json.dump({"quiz": quiz}, f, indent=2)
        return os.path.getsize(path)

    file_size = await asyncio.to_thread(_save)
    subject = data.get("subject", "General")
    grade = data.get("grade", "General")
    language = data.get("language", "en")

    topic_id = data.get("topic_id", "")
    await db_exec(
        """INSERT INTO resources (id, title, subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, uploaded_at, status, file_size, topic_id)
           VALUES (?, ?, ?, ?, ?, 'quiz', ?, ?, 'Teacher-Created', 'Internal Only', ?, datetime('now'), 'approved', ?, ?)""",
        (resource_id, title, subject, grade, language, filename, title + ".json", teacher_user, file_size, topic_id)
    )

    row = await db_fetch_one("SELECT * FROM resources WHERE id = ?", (resource_id,))
    return dict(row)


@router.put("/api/teacher/quiz-resource/{resource_id}",
            summary="Update a standalone quiz resource", tags=["Teacher"])
async def update_quiz_resource(resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Update quiz questions and metadata for an existing standalone quiz resource."""
    resource = await db_fetch_one("SELECT id FROM resources WHERE id = ? AND resource_type = 'quiz'", (resource_id,))
    if not resource:
        raise HTTPException(status_code=404, detail="Quiz resource not found.")

    questions = data.get("questions")
    if not isinstance(questions, list) or len(questions) == 0:
        raise HTTPException(status_code=400, detail="Quiz must have at least one question.")
    for i, q in enumerate(questions):
        if not all(k in q for k in ("id", "type", "question")):
            raise HTTPException(status_code=400, detail=f"Question at index {i} is missing one of: id, type, question.")

    title = data.get("title", "Quiz")
    quiz = {
        "title": title,
        "questions": questions,
        "time_limit_minutes": data.get("time_limit_minutes", 0),
        "pass_threshold": data.get("pass_threshold", 60),
        "max_attempts": data.get("max_attempts", 0),
        "shuffle_mode": data.get("shuffle_mode", "none"),
        "quiz_version": 1,
    }

    def _save():
        path = os.path.join(UPLOAD_DIR, f"{resource_id}.quiz")
        with open(path, "w") as f:
            json.dump({"quiz": quiz}, f, indent=2)
        return os.path.getsize(path)

    file_size = await asyncio.to_thread(_save)
    if title != data.get("title"):
        await db_exec("UPDATE resources SET title = ?, file_size = ? WHERE id = ?", (title, file_size, resource_id))
    else:
        await db_exec("UPDATE resources SET file_size = ? WHERE id = ?", (file_size, resource_id))

    return {"status": "ok"}


@router.get("/api/quiz-resource/{resource_id}",
            summary="Get standalone quiz JSON", tags=["Quizzes"])
async def get_quiz_resource(resource_id: str):
    """Get the quiz definition JSON for a standalone resource.

    Uses the resource's stored filename (``.quiz`` for new quizzes,
    ``.json`` for legacy quizzes).  Legacy flat format (no ``"quiz"``
    wrapper) is automatically wrapped for consistent client parsing.
    """
    resource = await db_fetch_one("SELECT filename FROM resources WHERE id = ? AND resource_type = 'quiz'", (resource_id,))
    if not resource:
        raise HTTPException(status_code=404, detail="Quiz resource not found.")

    quiz_path = os.path.join(UPLOAD_DIR, resource["filename"])

    def _read():
        if not os.path.exists(quiz_path):
            return None
        with open(quiz_path, "r", encoding="utf-8") as f:
            return json.load(f)

    quiz_data = await asyncio.to_thread(_read)
    if quiz_data is None:
        raise HTTPException(status_code=404, detail="Quiz file not found.")

    # Normalize legacy flat format (no "quiz" wrapper) to match new format
    if "quiz" not in quiz_data:
        quiz_data = {"quiz": quiz_data}

    quiz_inner = quiz_data.get("quiz", quiz_data)
    if "quiz_version" not in quiz_inner:
        quiz_inner["quiz_version"] = 1

    # Normalize questions: web frontend sends {text} instead of {question}, no {id}
    for i, q in enumerate(quiz_inner.get("questions", [])):
        if "id" not in q or not q["id"]:
            q["id"] = f"q-{i}"
        if "question" not in q and "text" in q:
            q["question"] = q.pop("text")
        if "image" not in q and "image_data" in q:
            q["image"] = q.pop("image_data")

    return quiz_data


@router.post("/api/quiz-resource/{resource_id}/submit",
             summary="Submit a standalone quiz attempt", tags=["Quizzes"])
async def submit_quiz_attempt(resource_id: str, data: dict, student_id: str = Depends(verify_student)):
    """Submit a quiz attempt for a standalone resource.
    Stores in quiz_attempts table.
    """
    existing = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.get("attempt_id", ""),))
    if existing:
        return dict(existing)

    resource = await db_fetch_one("SELECT id, title FROM resources WHERE id = ?", (resource_id,))
    if not resource:
        raise HTTPException(status_code=404, detail="Resource not found.")

    await db_exec(
        """INSERT INTO quiz_attempts (id, student_id, course_id, resource_id, attempt_number, score, passed, answers_json, started_at, submitted_at, time_taken_seconds, quiz_version, threshold_at_submission)
           VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (data.get("attempt_id", ""), student_id, resource_id,
         data.get("attempt_number", 1), data.get("score", 0.0),
         data.get("passed", 0), data.get("answers_json", ""),
         data.get("started_at", ""), data.get("submitted_at", ""),
         data.get("time_taken_seconds", 0), data.get("quiz_version", 1),
         data.get("threshold_at_submission", 0.0))
    )

    row = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.get("attempt_id", ""),))
    return dict(row)


@router.get("/api/quiz-resource/{resource_id}/best-score",
            summary="Get best score for a standalone quiz", tags=["Quizzes"])
async def get_quiz_resource_best_score(resource_id: str, student_id: str = Depends(verify_student)):
    """Get the student's best score and attempt count for a standalone quiz."""
    best = await db_fetch_one(
        "SELECT best_score, best_attempt_id FROM quiz_best_scores WHERE scholar_id = ? AND course_id = '' AND resource_id = ?",
        (student_id, resource_id))
    count_row = await db_fetch_one(
        "SELECT COUNT(*) FROM quiz_attempts WHERE student_id = ? AND course_id = '' AND resource_id = ?",
        (student_id, resource_id))
    return {
        "best_score": best["best_score"] if best else 0.0,
        "best_attempt_id": best["best_attempt_id"] if best else "",
        "attempts_count": count_row[0] if count_row else 0,
    }


@router.post("/api/quiz-resource/{resource_id}/best-score",
             summary="Update best score for a standalone quiz", tags=["Quizzes"])
async def update_quiz_resource_best_score(resource_id: str, data: dict, student_id: str = Depends(verify_student)):
    """Update the student's best score if the new score is higher."""
    existing = await db_fetch_one(
        "SELECT best_score FROM quiz_best_scores WHERE scholar_id = ? AND course_id = '' AND resource_id = ?",
        (student_id, resource_id))
    new_score = data.get("score", 0.0)
    if existing and (existing["best_score"] or 0) >= new_score:
        return {"status": "ok"}
    await db_exec(
        """INSERT INTO quiz_best_scores (scholar_id, course_id, resource_id, best_score, best_attempt_id, updated_at)
           VALUES (?, '', ?, ?, ?, datetime('now'))
           ON CONFLICT(scholar_id, course_id, resource_id) DO UPDATE SET best_score = ?, best_attempt_id = ?, updated_at = datetime('now')""",
        (student_id, resource_id, new_score, data.get("attempt_id", ""), new_score, data.get("attempt_id", "")))
    return {"status": "ok"}