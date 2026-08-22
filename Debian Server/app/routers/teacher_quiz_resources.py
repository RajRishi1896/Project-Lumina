"""Standalone quiz resources: upload, serve, submit."""
import os
import uuid
import json
import asyncio
from fastapi import APIRouter, Depends, HTTPException
from app.dependencies import verify_teacher, verify_student, verify_user, can_manage_resource
from app.async_db import db_exec, db_fetch_one
from app.database import UPLOAD_DIR
from app.models import QuizBestScoreUpdate
from app.quiz_grading import grade_quiz_detailed, load_quiz_file
from app.routers.student_courses import strip_answer_keys

router = APIRouter()


@router.post("/api/teacher/quiz-resource",
             summary="Create a standalone quiz resource", tags=["Teacher"],
             description="Creates a standalone quiz resource not bound to a course, saving quiz JSON to uploads and registering a resources row.",
             response_model=dict,
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
        """Write the quiz JSON to disk in a worker thread and return its size."""
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
    from app.routers.resources import invalidate_catalog_cache
    invalidate_catalog_cache()
    return dict(row)


@router.put("/api/teacher/quiz-resource/{resource_id}",
            summary="Update a standalone quiz resource", tags=["Teacher"],
            description="Updates questions and metadata for an existing standalone quiz resource.",
            response_model=dict,
            responses={200: {"description": "Quiz updated"}, 400: {"description": "Invalid data"}, 403: {"description": "Not the owner"}, 404: {"description": "Quiz resource not found"}})
async def update_quiz_resource(resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Update quiz questions and metadata for an existing standalone quiz resource."""
    resource = await db_fetch_one("SELECT id, title, uploaded_by FROM resources WHERE id = ? AND resource_type = 'quiz'", (resource_id,))
    if not resource:
        raise HTTPException(status_code=404, detail="Quiz resource not found.")
    if not await can_manage_resource(teacher_user, resource["uploaded_by"]):
        raise HTTPException(status_code=403, detail="You can only edit your own quizzes.")  # i18n: user-facing error message

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
        """Write the updated quiz JSON to disk in a worker thread and return its size."""
        path = os.path.join(UPLOAD_DIR, f"{resource_id}.quiz")
        with open(path, "w") as f:
            json.dump({"quiz": quiz}, f, indent=2)
        return os.path.getsize(path)

    file_size = await asyncio.to_thread(_save)
    await db_exec("UPDATE resources SET title = ?, file_size = ? WHERE id = ?", (title, file_size, resource_id))
    from app.routers.resources import invalidate_catalog_cache
    invalidate_catalog_cache()
    return {"status": "ok"}


@router.get("/api/quiz-resource/{resource_id}",
            summary="Get standalone quiz JSON", tags=["Quizzes"],
            description="Returns the quiz definition JSON for a standalone resource. Legacy flat-format quizzes are wrapped for consistent client parsing.",
            response_model=dict,
            responses={200: {"description": "Quiz JSON"}, 404: {"description": "Quiz resource not found"}})
async def get_quiz_resource(resource_id: str, user: str = Depends(verify_user)):
    """Get the quiz definition JSON for a standalone resource.

    Gated with ``verify_user`` (not teacher-only): the Flutter student app
    fetches standalone quizzes through this exact route
    (``quiz_player_page.dart``), and grading happens server-side on submit.
    Uses the resource's stored filename (``.quiz`` for new quizzes,
    ``.json`` for legacy quizzes).  Legacy flat format (no ``"quiz"``
    wrapper) is automatically wrapped for consistent client parsing.
    """
    resource = await db_fetch_one("SELECT filename FROM resources WHERE id = ? AND resource_type = 'quiz'", (resource_id,))
    if not resource:
        raise HTTPException(status_code=404, detail="Quiz resource not found.")

    quiz_path = os.path.join(UPLOAD_DIR, resource["filename"])

    def _read():
        """Read the quiz JSON file in a worker thread, returning None when missing."""
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

    # Security: the answer key must never reach the client; grading is
    # re-done server-side on submit from this same on-disk file.
    quiz_inner["questions"] = strip_answer_keys(quiz_inner.get("questions", []))

    return quiz_data


@router.post("/api/quiz-resource/{resource_id}/submit",
             summary="Submit a standalone quiz attempt", tags=["Quizzes"],
             description="Submits a quiz attempt. The score is re-graded server-side; the client's score is never trusted.",
             response_model=dict,
             responses={200: {"description": "Graded attempt"}, 404: {"description": "Quiz resource not found"}})
async def submit_quiz_attempt(resource_id: str, data: dict, student_id: str = Depends(verify_student)):
    """Submit a quiz attempt for a standalone resource.
    Stores in quiz_attempts table.
    """
    existing = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.get("attempt_id", ""),))
    if existing:
        if existing["student_id"] != student_id:
            # 404 so the existence of another student's attempt is not leaked
            raise HTTPException(status_code=404, detail="Attempt not found.")  # i18n: user-facing error message
        return dict(existing)

    resource = await db_fetch_one("SELECT id, title, filename, resource_type, status FROM resources WHERE id = ?", (resource_id,))
    if not resource or resource["resource_type"] != "quiz" or resource["status"] != "approved":
        raise HTTPException(status_code=404, detail="Resource not found.")  # i18n: user-facing error message

    # Re-grade server-side: the client's score/passed are never trusted
    quiz_path = os.path.join(UPLOAD_DIR, resource["filename"] or "")
    quiz = await asyncio.to_thread(load_quiz_file, quiz_path)
    if quiz is None:
        raise HTTPException(status_code=404, detail="Quiz not found.")  # i18n: user-facing error message
    score, passed, threshold, results = grade_quiz_detailed(quiz, data.get("answers_json", ""))

    await db_exec(
        """INSERT INTO quiz_attempts (id, student_id, course_id, resource_id, attempt_number, score, passed, answers_json, started_at, submitted_at, time_taken_seconds, quiz_version, threshold_at_submission)
           VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (data.get("attempt_id", ""), student_id, resource_id,
         data.get("attempt_number", 1), score,
         passed, data.get("answers_json", ""),
         data.get("started_at", ""), data.get("submitted_at", ""),
         data.get("time_taken_seconds", 0), data.get("quiz_version", 1),
         threshold)
    )

    row = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.get("attempt_id", ""),))
    response = dict(row)
    response["results"] = results
    return response


@router.get("/api/quiz-resource/{resource_id}/best-score",
            summary="Get best score for a standalone quiz", tags=["Quizzes"],
            description="Returns the student's best score, best attempt id, and attempt count for a standalone quiz.",
            response_model=dict,
            responses={200: {"description": "Best score data"}})
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
             summary="Update best score for a standalone quiz", tags=["Quizzes"],
             description="Updates the student's best score, but only if the new score is higher. "
                         "The referenced attempt must exist, belong to this student, and match this "
                         "quiz; the accepted score never exceeds the server-graded attempt score.",
             response_model=dict,
             responses={200: {"description": "Best score updated"},
                        403: {"description": "Attempt belongs to another student or quiz"},
                        404: {"description": "Attempt not found"},
                        422: {"description": "Invalid payload (score must be a number in 0.0-1.0)"}})
async def update_quiz_resource_best_score(resource_id: str, data: QuizBestScoreUpdate, student_id: str = Depends(verify_student)):
    """Update the student's best score if the new score is higher.

    The client-reported score is never trusted outright: it is clamped to
    the server-graded score of the referenced attempt, which must exist,
    belong to this student, and match this standalone quiz (course_id '').

    Raises:
        HTTPException 404: If no attempt with this attempt_id exists.
        HTTPException 403: If the attempt belongs to another student or a
            different course/quiz than this endpoint is scoring.
    """
    attempt = await db_fetch_one(
        "SELECT student_id, course_id, resource_id, score FROM quiz_attempts WHERE id = ?",
        (data.attempt_id,))
    if attempt is None:
        raise HTTPException(status_code=404, detail="Attempt not found.")  # i18n: user-facing error message
    if (attempt["student_id"] != student_id or attempt["course_id"] != ""
            or attempt["resource_id"] != resource_id):
        raise HTTPException(status_code=403, detail="Attempt does not belong to this student.")  # i18n: user-facing error message

    new_score = min(data.score, attempt["score"] if attempt["score"] is not None else 0.0)
    existing = await db_fetch_one(
        "SELECT best_score FROM quiz_best_scores WHERE scholar_id = ? AND course_id = '' AND resource_id = ?",
        (student_id, resource_id))
    if existing and (existing["best_score"] or 0) >= new_score:
        return {"status": "ok"}
    await db_exec(
        """INSERT INTO quiz_best_scores (scholar_id, course_id, resource_id, best_score, best_attempt_id, updated_at)
           VALUES (?, '', ?, ?, ?, datetime('now'))
           ON CONFLICT(scholar_id, course_id, resource_id) DO UPDATE SET best_score = ?, best_attempt_id = ?, updated_at = datetime('now')""",
        (student_id, resource_id, new_score, data.attempt_id, new_score, data.attempt_id))
    return {"status": "ok"}