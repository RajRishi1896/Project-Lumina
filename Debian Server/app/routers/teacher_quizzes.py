"""Teacher quiz management -- create and save quiz resources."""
import os
import uuid
import json
import asyncio
import logging
from fastapi import APIRouter, Depends, HTTPException
from app.audit import audit, Action
from app.async_db import db_exec, db_fetch_one
from app.dependencies import verify_teacher
from app.routers.teacher_courses import COURSES_DIR, _ensure_course_owner

router = APIRouter()


@router.post("/api/teacher/courses/{course_id}/quiz",
             summary="Create a quiz resource for a course", tags=["Teacher Courses"],
             responses={201: {"description": "Quiz resource created"}, 400: {"description": "Invalid data"}})
async def create_course_quiz(course_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Create a new quiz resource within a course.

    Validates that questions is a non-empty list with required fields (id, type,
    question). Saves the quiz as a JSON file and registers a course_resources
    row with type ``quiz``.

    Raises:
        HTTPException: 400 if questions are missing or invalid.
    """
    await _ensure_course_owner(course_id, teacher_user)
    questions = data.get("questions")
    if not isinstance(questions, list) or len(questions) == 0:
        raise HTTPException(status_code=400, detail="Quiz must have at least one question.")  # i18n: user-facing error message
    for i, q in enumerate(questions):
        if not all(k in q for k in ("id", "type", "question")):
            raise HTTPException(status_code=400, detail=f"Question at index {i} is missing one of: id, type, question.")  # i18n: user-facing error message

    resource_id = str(uuid.uuid4())
    title = data.get("title", "Quiz")
    quiz_dir = os.path.join(COURSES_DIR, course_id)
    os.makedirs(quiz_dir, exist_ok=True)
    quiz_path = os.path.join(quiz_dir, f"quiz_{resource_id}.json")

    def _save():
        quiz = {"questions": questions, "time_limit_minutes": data.get("time_limit_minutes", 0),
                "pass_threshold": data.get("pass_threshold", 60), "max_attempts": data.get("max_attempts", 0),
                "shuffle": data.get("shuffle", False), "quiz_version": 1}
        with open(quiz_path, "w") as f:
            json.dump({"quiz": quiz}, f, indent=2)
        return len(json.dumps(quiz).encode())

    file_size = await asyncio.to_thread(_save)
    last_pos = await db_fetch_one(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM course_resources WHERE course_id = ?", (course_id,))
    next_pos = (last_pos["mp"] if last_pos and last_pos["mp"] is not None else -1) + 1

    await db_exec(
        """INSERT INTO course_resources (id, course_id, resource_type, title, original_name, filename, file_size, position, topic_id)
           VALUES (?, ?, 'quiz', ?, ?, ?, ?, ?, ?)""",
        (resource_id, course_id, title, title + ".json", f"quiz_{resource_id}.json", file_size, next_pos, data.get("topic_id", ""))
    )
    await audit(action=Action.CREATE_QUIZ, username=teacher_user, resource_type="quiz",
                resource_id=resource_id, resource_name=title,
                context={"course_id": course_id, "question_count": len(questions)})
    row = await db_fetch_one("SELECT * FROM course_resources WHERE id = ?", (resource_id,))
    return dict(row)


@router.put("/api/teacher/courses/{course_id}/quiz/{resource_id}",
            summary="Save quiz JSON for a course resource", tags=["Teacher Courses"])
async def save_course_quiz(course_id: str, resource_id: str, data: dict, teacher_user: str = Depends(verify_teacher)):
    """Update an existing quiz's JSON content and bump its version number.

    Increments ``quiz_version`` in the saved JSON to allow clients to
    detect updates.

    Raises:
        HTTPException: 400 if quiz data invalid, 404 if resource not found.
    """
    await _ensure_course_owner(course_id, teacher_user)
    resource = await db_fetch_one(
        "SELECT id FROM course_resources WHERE id = ? AND course_id = ?", (resource_id, course_id))
    if not resource:
        raise HTTPException(status_code=404, detail="Resource not found in this course.")  # i18n: user-facing error message

    quiz = data.get("quiz")
    if not isinstance(quiz, dict):
        raise HTTPException(status_code=400, detail="Body must contain a 'quiz' object.")  # i18n: user-facing error message
    questions = quiz.get("questions")
    if not isinstance(questions, list) or len(questions) == 0:
        raise HTTPException(status_code=400, detail="Quiz must have at least one question.")  # i18n: user-facing error message
    for i, q in enumerate(questions):
        if not all(k in q for k in ("id", "type", "question")):
            raise HTTPException(status_code=400, detail=f"Question at index {i} is missing one of: id, type, question.")  # i18n: user-facing error message

    quiz_dir = os.path.join(COURSES_DIR, course_id)
    os.makedirs(quiz_dir, exist_ok=True)
    quiz_path = os.path.join(quiz_dir, f"quiz_{resource_id}.json")

    def _save():
        quiz_version = 1
        if os.path.isfile(quiz_path):
            try:
                with open(quiz_path, "r") as f:
                    existing = json.load(f)
                if isinstance(existing, dict) and "quiz_version" in existing.get("quiz", {}):
                    quiz_version = existing["quiz"]["quiz_version"] + 1
            except (json.JSONDecodeError, OSError):
                quiz_version = 1
        quiz["quiz_version"] = quiz_version
        with open(quiz_path, "w") as f:
            json.dump({"quiz": quiz}, f, indent=2)
        return quiz_version

    version = await asyncio.to_thread(_save)
    await audit(action=Action.UPDATE_QUIZ, username=teacher_user, resource_type="quiz",
                resource_id=resource_id,
                context={"course_id": course_id, "quiz_version": version})
    return {"status": "ok", "quiz_version": version}
