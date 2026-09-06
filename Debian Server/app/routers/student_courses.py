"""Student course interaction: catalog, enroll, progress, quizzes, assets."""
import os
import json
import sqlite3
import asyncio
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from app.audit import audit, Action
from app.async_db import db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_student
from app.models import ProgressSync, EnrollResponse, QuizAttemptSubmit, QuizAttemptResponse, EnrolledCoursesResponse, EnrolledCourseItem
from app.quiz_grading import grade_quiz_detailed, load_quiz_file
from app.routers.teacher_courses import COURSES_DIR

router = APIRouter()

# Question fields safe to send to students. Everything else (notably
# correct_answer/correct_answers/explanation) is the answer key: grading
# happens server-side in submit_quiz_attempt, which reloads this file.
SAFE_QUESTION_FIELDS = frozenset({"id", "question", "type", "options", "image"})


def strip_answer_keys(questions: list) -> list:
    """Return copies of questions containing only student-safe fields.

    Args:
        questions: Quiz question dicts as stored on disk.

    Returns:
        New list of dicts with only SAFE_QUESTION_FIELDS kept, so the
        answer key never reaches the client.
    """
    return [{k: v for k, v in q.items() if k in SAFE_QUESTION_FIELDS} for q in questions]


@router.get("/api/courses/similar-courses", response_model=list[dict],
            summary="Get all similar course links",
            description="Returns all rows from the similar_courses table for client-side recommendation graph.",
            tags=["Courses"],
            responses={401: {"description": "Unauthorized"}})
async def get_similar_courses(student_id: str = Depends(verify_student)):
    """Return the full similar-courses graph.

    Returns:
        List of dicts with course_id and similar_course_id for all links.
    """
    rows = await db_fetch("SELECT course_id, similar_course_id, created_by, created_at FROM similar_courses")
    return [
        {"course_id": r["course_id"], "similar_course_id": r["similar_course_id"],
         "created_by": r["created_by"], "created_at": r["created_at"]}
        for r in rows
    ]


@router.get("/api/courses", response_model=dict,
            summary="List published courses",
            description="Returns paginated course catalog with optional filters for subject, grade, language, and search.",
            tags=["Courses"],
            responses={401: {"description": "Unauthorized"}})
async def list_courses(  # noqa: PLR0913
    subject: Optional[str] = Query(None, description="Filter by subject"),
    grade: Optional[int] = Query(None, description="Filter by grade"),
    language: Optional[str] = Query(None, description="Filter by language (ISO 639-1)"),
    search: Optional[str] = Query(None, description="Search by title substring"),
    page: int = Query(1, ge=1, description="Page number"),
    per_page: int = Query(20, ge=1, le=100, description="Items per page"),
    student_id: str = Depends(verify_student),
):
    """List published courses with optional filters and pagination.

    Returns:
        Dict with items, total, page, and per_page.
    """
    conditions = ["published = 1"]
    params = []

    if subject:
        conditions.append("subject = ?")
        params.append(subject)
    if grade is not None:
        conditions.append("grade = ?")
        params.append(grade)
    if language:
        conditions.append("language = ?")
        params.append(language)
    if search:
        conditions.append("title LIKE ?")
        params.append(f"%{search}%")

    where_clause = " WHERE " + " AND ".join(conditions)
    offset = (page - 1) * per_page

    count_row = await db_fetch_one(f"SELECT COUNT(*) FROM courses{where_clause}", tuple(params))
    total = count_row[0] if count_row else 0

    rows = await db_fetch(
        f"SELECT id, title, description, subject, grade, language, cover_image, published, teacher_username, enrollment_count, created_at, updated_at FROM courses{where_clause} ORDER BY created_at DESC LIMIT ? OFFSET ?",
        tuple(params) + (per_page, offset)
    )

    items = []
    for r in rows:
        items.append({
            "id": r["id"],
            "title": r["title"],
            "description": r["description"] or "",
            "subject": r["subject"] or "",
            "grade": r["grade"] or 0,
            "language": r["language"] or "en",
            "cover_image": r["cover_image"] or "",
            "published": r["published"],
            "teacher_username": r["teacher_username"] or "",
            "enrollment_count": r["enrollment_count"] or 0,
            "created_at": r["created_at"] or "",
            "updated_at": r["updated_at"] or "",
        })

    return {"items": items, "total": total, "page": page, "per_page": per_page}


@router.get("/api/courses/{course_id}", response_model=dict,
            summary="Get course detail with enrollment status",
            description="Returns full course metadata, resource list, similar courses, and whether the student is enrolled.",
            tags=["Courses"],
            responses={401: {"description": "Unauthorized"}, 404: {"description": "Course not found"}})
async def get_course_detail(course_id: str, student_id: str = Depends(verify_student)):
    """Get course detail including resources, similar courses, and enrollment status.

    Args:
        course_id: UUID of the course.

    Returns:
        Course detail with resources, similar_courses, is_enrolled, and progress.
    Raises:
        HTTPException 404: If course not found.
    """
    row = await db_fetch_one("SELECT id, title, description, subject, grade, language, cover_image, published, teacher_username, enrollment_count, created_at, updated_at FROM courses WHERE id = ? AND published = 1", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")  # i18n: user-facing error message

    resources = await db_fetch(
        "SELECT id, course_id, resource_type, title, original_name, filename, file_size, position, page_count, duration_seconds FROM course_resources WHERE course_id = ? ORDER BY position",
        (course_id,)
    )

    similar = await db_fetch(
        "SELECT sc.similar_course_id, c.title, c.subject, c.grade FROM similar_courses sc JOIN courses c ON c.id = sc.similar_course_id WHERE sc.course_id = ?",
        (course_id,)
    )

    progress_row = await db_fetch_one(
        "SELECT current_position, completed_count, total_resources, completed, last_synced, enrolled_at FROM course_progress WHERE student_id = ? AND course_id = ?",
        (student_id, course_id)
    )

    is_enrolled = progress_row is not None
    progress = None
    if progress_row:
        progress = {
            "current_position": progress_row["current_position"],
            "completed_count": progress_row["completed_count"],
            "total_resources": progress_row["total_resources"],
            "completed": progress_row["completed"],
            "last_synced": progress_row["last_synced"],
            "enrolled_at": progress_row["enrolled_at"],
        }

    return {
        "id": row["id"],
        "title": row["title"],
        "description": row["description"] or "",
        "subject": row["subject"] or "",
        "grade": row["grade"] or 0,
        "language": row["language"] or "en",
        "cover_image": row["cover_image"] or "",
        "published": row["published"],
        "teacher_username": row["teacher_username"] or "",
        "enrollment_count": row["enrollment_count"] or 0,
        "created_at": row["created_at"] or "",
        "updated_at": row["updated_at"] or "",
        "resources": [
            {
                "id": r["id"],
                "course_id": r["course_id"],
                "resource_type": r["resource_type"],
                "title": r["title"] or "",
                "original_name": r["original_name"] or "",
                "filename": r["filename"] or "",
                "file_size": r["file_size"] or 0,
                "position": r["position"],
                "page_count": r["page_count"] or 0,
                "duration_seconds": r["duration_seconds"] or 0,
            }
            for r in resources
        ],
        "similar_courses": [
            {
                "course_id": similar_course_id,
                "title": r["title"],
                "subject": r["subject"],
                "grade": r["grade"],
            }
            for r in similar
            for similar_course_id in [r["similar_course_id"]]
        ],
        "is_enrolled": is_enrolled,
        "progress": progress,
    }


@router.post("/api/courses/{course_id}/enroll", response_model=EnrollResponse,
             summary="Enroll in a course",
             description="Enrolls the authenticated student in a published course. Returns 409 if already enrolled.",
             tags=["Courses"],
             responses={404: {"description": "Course not found"}, 409: {"description": "Already enrolled"}})
async def enroll_course(course_id: str, student_id: str = Depends(verify_student)):
    """Enroll the current student in a course.

    Args:
        course_id: UUID of the course.

    Returns:
        EnrollResponse with status and message.
    Raises:
        HTTPException 404: If course does not exist or is not published.
        HTTPException 409: If the student is already enrolled.
    """
    course = await db_fetch_one("SELECT id, title FROM courses WHERE id = ? AND published = 1", (course_id,))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found or not published.")  # i18n: user-facing error message

    existing = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if existing:
        raise HTTPException(status_code=409, detail="Already enrolled in this course.")  # i18n: user-facing error message

    try:
        await db_exec(
            "INSERT INTO course_progress (student_id, course_id, current_position, completed_count, enrolled_at) VALUES (?, ?, 0, 0, datetime('now'))",
            (student_id, course_id)
        )
    except sqlite3.IntegrityError:
        # Concurrent enroll: the (student_id, course_id) PK was inserted between
        # the pre-check and this write; report as already enrolled, not 500.
        raise HTTPException(status_code=409, detail="Already enrolled in this course.")  # i18n: user-facing error message
    await db_exec("UPDATE courses SET enrollment_count = enrollment_count + 1 WHERE id = ?", (course_id,))
    await audit(action=Action.ENROLL_COURSE, username=student_id, resource_type="course",
                resource_id=course_id, resource_name=course['title'])

    return EnrollResponse(status="ok", course_id=course_id, message="Successfully enrolled.")  # i18n: user-facing success message


@router.put("/api/courses/{course_id}/progress", response_model=dict,
            summary="Sync course progress",
            description="Upserts the student's progress for a course. Creates a row if none exists, updates if it does.",
            tags=["Courses"],
            responses={401: {"description": "Unauthorized"}, 404: {"description": "Course not published or student not enrolled"}})
async def sync_progress(course_id: str, data: ProgressSync, student_id: str = Depends(verify_student)):
    """Sync the student's course progress (UPSERT).

    Args:
        course_id: UUID of the course.
        data: ProgressSync payload with current_position, completed_count,
            and completed (1 once the whole course is finished).

    Returns:
        Updated progress dict.
    """
    # Verify course exists and is published: unpublished courses are invisible to students
    course = await db_fetch_one("SELECT id FROM courses WHERE id = ? AND published = 1", (course_id,))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found or not published.")  # i18n: user-facing error message

    # Progress only ever updates an existing enrollment; never auto-enrolls.
    # Grab total_resources/enrolled_at here so the response can be built from
    # the payload without re-SELECTing the row we just updated.
    enrolled = await db_fetch_one("SELECT total_resources, enrolled_at FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not enrolled:
        raise HTTPException(status_code=404, detail="Not enrolled in this course.")  # i18n: user-facing error message

    await db_exec(
        "UPDATE course_progress SET current_position = ?, completed_count = ?, completed = ?, last_synced = datetime('now') WHERE student_id = ? AND course_id = ?",
        (data.current_position, data.completed_count, data.completed, student_id, course_id)
    )

    return {
        "current_position": data.current_position,
        "completed_count": data.completed_count,
        "total_resources": enrolled["total_resources"] or 0,
        "completed": data.completed,
        "last_synced": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
        "enrolled_at": enrolled["enrolled_at"],
    }


@router.get("/api/courses/{course_id}/quiz/{resource_id}", response_model=dict,
            summary="Get quiz JSON",
            description="Returns the quiz JSON file for a course resource. Requires enrollment.",
            tags=["Courses"],
            responses={401: {"description": "Unauthorized"}, 403: {"description": "Not enrolled"}, 404: {"description": "Quiz not found"}})
async def get_quiz(course_id: str, resource_id: str, student_id: str = Depends(verify_student)):
    """Get the quiz definition JSON for a course resource.

    Args:
        course_id: UUID of the course.
        resource_id: UUID of the course resource.

    Returns:
        Quiz JSON content with quiz_version field added and per-question
        answer fields stripped: grading is server-side only.
    Raises:
        HTTPException 403: If the student is not enrolled.
        HTTPException 404: If the quiz file does not exist.
    """
    enrolled = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not enrolled:
        raise HTTPException(status_code=403, detail="Enrollment required to access quizzes.")  # i18n: user-facing error message

    quiz_path = os.path.join(COURSES_DIR, course_id, f"quiz_{resource_id}.json")

    def _read_quiz():
        """Read the quiz JSON from disk, or None when missing."""
        if not os.path.exists(quiz_path):
            return None
        with open(quiz_path, "r", encoding="utf-8") as f:
            return json.load(f)

    quiz_data = await asyncio.to_thread(_read_quiz)
    if quiz_data is None:
        raise HTTPException(status_code=404, detail="Quiz not found.")  # i18n: user-facing error message

    quiz_inner = quiz_data.get("quiz", quiz_data)
    if "quiz_version" not in quiz_inner:
        quiz_inner["quiz_version"] = 1

    for i, q in enumerate(quiz_inner.get("questions", [])):
        if "id" not in q or not q["id"]:
            q["id"] = f"q-{i}"
        if "question" not in q and "text" in q:
            q["question"] = q.pop("text")
        if "image" not in q and "image_data" in q:
            q["image"] = q.pop("image_data")

    # The _answer_key is sent with the quiz for offline grading (client
    # cannot reach the server while offline). The Flutter UI never displays
    # answers before the student submits — answers are only revealed in the
    # results screen after _submitted = true.
    quiz_inner["_answer_key"] = {
        q.get("id", f"q-{i}"): {
            k: v for k, v in q.items()
            if k in ("correct_answer", "correct_answers")
        }
        for i, q in enumerate(quiz_inner.get("questions", []))
    }
    quiz_inner["questions"] = strip_answer_keys(quiz_inner.get("questions", []))

    return quiz_data


@router.post("/api/courses/{course_id}/quiz/{resource_id}/submit", response_model=QuizAttemptResponse,
             summary="Submit a quiz attempt",
             description="Submits a quiz attempt with idempotency support. If the attempt_id already exists, returns the existing record.",
             tags=["Courses"],
             responses={403: {"description": "Not enrolled"}, 404: {"description": "Course or quiz not found"}})
async def submit_quiz_attempt(course_id: str, resource_id: str, data: QuizAttemptSubmit, student_id: str = Depends(verify_student)):
    """Submit a quiz attempt. Idempotent: duplicate attempt_id returns existing record.

    Args:
        course_id: UUID of the course.
        resource_id: UUID of the course resource.
        data: QuizAttemptSubmit payload.

    Returns:
        The stored quiz attempt record.
    Raises:
        HTTPException 403: If the student is not enrolled.
        HTTPException 404: If course not found or not published.
    """
    # Idempotency check: an attempt belongs to its submitting student only
    existing = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.attempt_id,))
    if existing:
        if existing["student_id"] != student_id:
            # 404 so the existence of another student's attempt is not leaked
            raise HTTPException(status_code=404, detail="Attempt not found.")  # i18n: user-facing error message
        return dict(existing)

    enrolled = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not enrolled:
        raise HTTPException(status_code=403, detail="Enrollment required to submit quizzes.")  # i18n: user-facing error message

    course = await db_fetch_one("SELECT id FROM courses WHERE id = ? AND published = 1", (course_id,))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found or not published.")  # i18n: user-facing error message

    # Re-grade server-side: the client's score/passed are never trusted
    quiz_path = os.path.join(COURSES_DIR, course_id, f"quiz_{resource_id}.json")
    quiz = await asyncio.to_thread(load_quiz_file, quiz_path)
    if quiz is None:
        raise HTTPException(status_code=404, detail="Quiz not found.")  # i18n: user-facing error message
    score, passed, threshold, results = grade_quiz_detailed(quiz, data.answers_json)

    # Idempotent insert: ON CONFLICT do nothing so concurrent duplicate
    # attempts don't produce a 500; the SELECT below returns the existing row.
    await db_exec(
        """INSERT OR IGNORE INTO quiz_attempts (id, student_id, course_id, resource_id, attempt_number, score, passed, answers_json, started_at, submitted_at, time_taken_seconds, quiz_version, threshold_at_submission)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (data.attempt_id, student_id, course_id, resource_id, data.attempt_number,
         score, passed, data.answers_json, data.started_at,
         data.submitted_at, data.time_taken_seconds, data.quiz_version, threshold)
    )

    row = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.attempt_id,))
    response = dict(row)
    response["results"] = results
    # Return the answer key ONLY after grading — never before submission.
    quiz_inner = quiz.get("quiz", quiz)
    response["_answer_key"] = {
        q.get("id", f"q-{i}"): {
            k: v for k, v in q.items()
            if k in ("correct_answer", "correct_answers")
        }
        for i, q in enumerate(quiz_inner.get("questions", []))
    }
    return response


@router.get("/student/enrolled-courses", response_model=EnrolledCoursesResponse,
            summary="Get all enrolled courses with progress",
            description="Returns all courses the student is enrolled in, with course metadata and progress. Used for restoring enrollment after app data clear.",
            tags=["Courses"],
            responses={401: {"description": "Unauthorized"}})
async def get_enrolled_courses(student_id: str = Depends(verify_student)):
    """Return every course the student is enrolled in with its saved progress."""
    rows = await db_fetch("""
        SELECT c.id, c.title, c.description, c.subject, c.grade, c.language, c.cover_image,
               c.published, c.teacher_username, c.enrollment_count, c.created_at, c.updated_at,
               cp.current_position, cp.completed_count, cp.total_resources, cp.completed, cp.enrolled_at
        FROM course_progress cp
        JOIN courses c ON c.id = cp.course_id
        WHERE cp.student_id = ?
        ORDER BY cp.enrolled_at DESC
    """, (student_id,))
    courses = []
    for r in rows:
        courses.append(EnrolledCourseItem(
            course_id=r["id"], title=r["title"] or "", description=r["description"] or "",
            subject=r["subject"] or "", grade=r["grade"] or 0, language=r["language"] or "en",
            cover_image=r["cover_image"] or "", published=r["published"] or 0,
            teacher_username=r["teacher_username"] or "", enrollment_count=r["enrollment_count"] or 0,
            created_at=r["created_at"] or "", updated_at=r["updated_at"] or "",
            current_position=r["current_position"] or 0, completed_count=r["completed_count"] or 0,
            total_resources=r["total_resources"] or 0, completed=r["completed"] or 0,
            enrolled_at=r["enrolled_at"] or "",
        ))
    return {"courses": courses}
