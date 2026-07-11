"""Student course interaction — catalog, enroll, progress, quizzes, assets."""
import os
import json
import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import FileResponse
from app.database import UPLOAD_DIR, log_admin_action
from app.async_db import db_conn, db_exec, db_fetch, db_fetch_one
from app.dependencies import verify_student
from app.models import CourseResponse, ProgressSync, EnrollResponse, QuizAttemptSubmit, QuizAttemptResponse, StatusResponse

router = APIRouter()
COURSES_DIR = os.path.join(UPLOAD_DIR, "..", "courses")


@router.get("/api/courses/similar-courses",
            summary="Get all similar course links",
            description="Returns all rows from the similar_courses table for client-side recommendation graph.",
            tags=["Courses"])
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


@router.get("/api/courses",
            summary="List published courses",
            description="Returns paginated course catalog with optional filters for subject, grade, language, and search.",
            tags=["Courses"])
async def list_courses(
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


@router.get("/api/courses/{course_id}",
            summary="Get course detail with enrollment status",
            description="Returns full course metadata, resource list, similar courses, and whether the student is enrolled.",
            tags=["Courses"])
async def get_course_detail(course_id: str, student_id: str = Depends(verify_student)):
    """Get course detail including resources, similar courses, and enrollment status.

    Args:
        course_id: UUID of the course.

    Returns:
        Course detail with resources, similar_courses, is_enrolled, and progress.
    Raises:
        HTTPException 404: If course not found.
    """
    row = await db_fetch_one("SELECT id, title, description, subject, grade, language, cover_image, published, teacher_username, enrollment_count, created_at, updated_at FROM courses WHERE id = ?", (course_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Course not found.")

    resources = await db_fetch(
        "SELECT id, course_id, resource_type, title, original_name, filename, file_size, position FROM course_resources WHERE course_id = ? ORDER BY position",
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
        raise HTTPException(status_code=404, detail="Course not found or not published.")

    existing = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if existing:
        raise HTTPException(status_code=409, detail="Already enrolled in this course.")

    await db_exec(
        "INSERT INTO course_progress (student_id, course_id, current_position, completed_count, enrolled_at) VALUES (?, ?, 0, 0, datetime('now'))",
        (student_id, course_id)
    )
    await db_exec("UPDATE courses SET enrollment_count = enrollment_count + 1 WHERE id = ?", (course_id,))
    await log_admin_action(student_id, f"enrolled in course {course_id} '{course['title']}'")

    return EnrollResponse(status="ok", course_id=course_id, message="Successfully enrolled.")


@router.post("/api/courses/{course_id}/unenroll", response_model=EnrollResponse,
             summary="Unenroll from a course",
             description="Removes the student's enrollment from a course and decrements the enrollment count.",
             tags=["Courses"],
             responses={404: {"description": "Not enrolled"}})
async def unenroll_course(course_id: str, student_id: str = Depends(verify_student)):
    """Unenroll the current student from a course.

    Args:
        course_id: UUID of the course.

    Returns:
        EnrollResponse with status and message.
    Raises:
        HTTPException 404: If the student is not enrolled.
    """
    existing = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not existing:
        raise HTTPException(status_code=404, detail="Not enrolled in this course.")

    await db_exec("DELETE FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    await db_exec("UPDATE courses SET enrollment_count = MAX(0, enrollment_count - 1) WHERE id = ?", (course_id,))

    return EnrollResponse(status="ok", course_id=course_id, message="Successfully unenrolled.")


@router.get("/api/courses/{course_id}/progress",
            summary="Get course progress",
            description="Returns the current student's progress for a course, or 404 if not enrolled.",
            tags=["Courses"],
            responses={404: {"description": "Not enrolled"}})
async def get_progress(course_id: str, student_id: str = Depends(verify_student)):
    """Get the student's progress in a course.

    Args:
        course_id: UUID of the course.

    Returns:
        Progress dict with current_position, completed_count, total_resources, completed, last_synced, enrolled_at.
    Raises:
        HTTPException 404: If the student is not enrolled.
    """
    row = await db_fetch_one(
        "SELECT current_position, completed_count, total_resources, completed, last_synced, enrolled_at FROM course_progress WHERE student_id = ? AND course_id = ?",
        (student_id, course_id)
    )
    if not row:
        raise HTTPException(status_code=404, detail="Not enrolled in this course.")

    return {
        "current_position": row["current_position"],
        "completed_count": row["completed_count"],
        "total_resources": row["total_resources"],
        "completed": row["completed"],
        "last_synced": row["last_synced"],
        "enrolled_at": row["enrolled_at"],
    }


@router.put("/api/courses/{course_id}/progress",
            summary="Sync course progress",
            description="Upserts the student's progress for a course. Creates a row if none exists, updates if it does.",
            tags=["Courses"])
async def sync_progress(course_id: str, data: ProgressSync, student_id: str = Depends(verify_student)):
    """Sync the student's course progress (UPSERT).

    Args:
        course_id: UUID of the course.
        data: ProgressSync payload with current_position and completed_count.

    Returns:
        Updated progress dict.
    """
    # Verify course exists
    course = await db_fetch_one("SELECT id FROM courses WHERE id = ?", (course_id,))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found.")

    await db_exec(
        """INSERT INTO course_progress (student_id, course_id, current_position, completed_count, last_synced, enrolled_at)
           VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
           ON CONFLICT(student_id, course_id) DO UPDATE SET
             current_position = excluded.current_position,
             completed_count = excluded.completed_count,
             last_synced = excluded.last_synced""",
        (student_id, course_id, data.current_position, data.completed_count)
    )

    row = await db_fetch_one(
        "SELECT current_position, completed_count, total_resources, completed, last_synced, enrolled_at FROM course_progress WHERE student_id = ? AND course_id = ?",
        (student_id, course_id)
    )

    return {
        "current_position": row["current_position"],
        "completed_count": row["completed_count"],
        "total_resources": row["total_resources"],
        "completed": row["completed"],
        "last_synced": row["last_synced"],
        "enrolled_at": row["enrolled_at"],
    }


@router.get("/api/courses/{course_id}/resource/{resource_id}",
            summary="Get resource download URL",
            description="Returns the download URL and metadata for a course resource. Requires enrollment.",
            tags=["Courses"],
            responses={403: {"description": "Not enrolled"}, 404: {"description": "Resource not found"}})
async def get_resource_url(course_id: str, resource_id: str, student_id: str = Depends(verify_student)):
    """Get the download URL for a course resource.

    Args:
        course_id: UUID of the course.
        resource_id: UUID of the course resource.

    Returns:
        Dict with url, filename, and file_size.
    Raises:
        HTTPException 403: If the student is not enrolled.
        HTTPException 404: If the resource does not exist.
    """
    enrolled = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not enrolled:
        raise HTTPException(status_code=403, detail="Enrollment required to access course resources.")

    row = await db_fetch_one(
        "SELECT filename, original_name, file_size FROM course_resources WHERE id = ? AND course_id = ?",
        (resource_id, course_id)
    )
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found.")

    return {
        "url": f"/files/courses/{course_id}/resources/{row['filename']}",
        "filename": row["original_name"] or row["filename"],
        "file_size": row["file_size"] or 0,
    }


@router.get("/api/courses/{course_id}/quiz/{resource_id}",
            summary="Get quiz JSON",
            description="Returns the quiz JSON file for a course resource. Requires enrollment.",
            tags=["Courses"],
            responses={403: {"description": "Not enrolled"}, 404: {"description": "Quiz not found"}})
async def get_quiz(course_id: str, resource_id: str, student_id: str = Depends(verify_student)):
    """Get the quiz definition JSON for a course resource.

    Args:
        course_id: UUID of the course.
        resource_id: UUID of the course resource.

    Returns:
        Quiz JSON content with quiz_version field added.
    Raises:
        HTTPException 403: If the student is not enrolled.
        HTTPException 404: If the quiz file does not exist.
    """
    enrolled = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not enrolled:
        raise HTTPException(status_code=403, detail="Enrollment required to access quizzes.")

    quiz_path = os.path.join(COURSES_DIR, course_id, f"quiz_{resource_id}.json")

    def _read_quiz():
        if not os.path.exists(quiz_path):
            return None
        with open(quiz_path, "r", encoding="utf-8") as f:
            return json.load(f)

    import asyncio
    quiz_data = await asyncio.to_thread(_read_quiz)
    if quiz_data is None:
        raise HTTPException(status_code=404, detail="Quiz not found.")

    if "quiz_version" not in quiz_data:
        quiz_data["quiz_version"] = 1

    return quiz_data


@router.post("/api/courses/{course_id}/quiz/{resource_id}/submit", response_model=QuizAttemptResponse,
             summary="Submit a quiz attempt",
             description="Submits a quiz attempt with idempotency support. If the attempt_id already exists, returns the existing record.",
             tags=["Courses"],
             responses={403: {"description": "Not enrolled"}, 404: {"description": "Course or quiz not found"}})
async def submit_quiz_attempt(course_id: str, resource_id: str, data: QuizAttemptSubmit, student_id: str = Depends(verify_student)):
    """Submit a quiz attempt. Idempotent — duplicate attempt_id returns existing record.

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
    # Idempotency check
    existing = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.attempt_id,))
    if existing:
        return dict(existing)

    enrolled = await db_fetch_one("SELECT 1 FROM course_progress WHERE student_id = ? AND course_id = ?", (student_id, course_id))
    if not enrolled:
        raise HTTPException(status_code=403, detail="Enrollment required to submit quizzes.")

    course = await db_fetch_one("SELECT id FROM courses WHERE id = ? AND published = 1", (course_id,))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found or not published.")

    await db_exec(
        """INSERT INTO quiz_attempts (id, student_id, course_id, resource_id, attempt_number, score, passed, answers_json, started_at, submitted_at, time_taken_seconds, quiz_version, threshold_at_submission)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (data.attempt_id, student_id, course_id, resource_id, data.attempt_number,
         data.score, data.passed, data.answers_json, data.started_at,
         data.submitted_at, data.time_taken_seconds, data.quiz_version, data.threshold_at_submission)
    )

    row = await db_fetch_one("SELECT * FROM quiz_attempts WHERE id = ?", (data.attempt_id,))
    return dict(row)


@router.get("/api/courses/{course_id}/quiz/{resource_id}/attempts", response_model=list[QuizAttemptResponse],
            summary="Get quiz attempt history",
            description="Returns all quiz attempts for the current student, course, and resource, ordered by attempt number descending.",
            tags=["Courses"])
async def get_quiz_attempts(course_id: str, resource_id: str, student_id: str = Depends(verify_student)):
    """Get quiz attempt history for the student.

    Args:
        course_id: UUID of the course.
        resource_id: UUID of the course resource.

    Returns:
        List of quiz attempt records ordered by attempt_number DESC.
    """
    rows = await db_fetch(
        """SELECT id, student_id, course_id, resource_id, attempt_number, score, passed,
                  answers_json, started_at, submitted_at, time_taken_seconds, quiz_version, threshold_at_submission
           FROM quiz_attempts
           WHERE student_id = ? AND course_id = ? AND resource_id = ?
           ORDER BY attempt_number DESC""",
        (student_id, course_id, resource_id)
    )
    return [dict(r) for r in rows]


@router.get("/api/courses/{course_id}/asset/{path:path}",
            summary="Serve course asset file",
            description="Serves static assets (images, PDFs, etc.) from the course's assets directory. Does not require enrollment — only that the course is published.",
            tags=["Courses"],
            responses={404: {"description": "Course or asset not found"}})
async def serve_asset(course_id: str, path: str, student_id: str = Depends(verify_student)):
    """Serve a course asset file from the assets subdirectory.

    Args:
        course_id: UUID of the course.
        path: Relative asset path.

    Returns:
        FileResponse with the asset file.
    Raises:
        HTTPException 404: If the course is not published or the asset does not exist.
    """
    course = await db_fetch_one("SELECT id FROM courses WHERE id = ? AND published = 1", (course_id,))
    if not course:
        raise HTTPException(status_code=404, detail="Course not found or not published.")

    asset_path = os.path.normpath(os.path.join(COURSES_DIR, course_id, "assets", path))
    expected_prefix = os.path.normpath(os.path.join(COURSES_DIR, course_id, "assets"))
    if not asset_path.startswith(expected_prefix):
        raise HTTPException(status_code=404, detail="Invalid asset path.")

    import asyncio

    def _check_file():
        if os.path.isfile(asset_path):
            return True
        return False

    exists = await asyncio.to_thread(_check_file)
    if not exists:
        raise HTTPException(status_code=404, detail="Asset not found.")

    return FileResponse(asset_path)
