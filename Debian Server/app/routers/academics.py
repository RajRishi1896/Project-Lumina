"""Subject, grade, and resource topic management routes."""
import os
import re
import sqlite3
import logging
import asyncio
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from app.async_db import db_exec, db_fetch, db_fetch_one, db_run
from app.database import UPLOAD_DIR, gen_uid
from app.dependencies import verify_teacher, verify_user, verify_admin
from app.models import SubjectCreate, SubjectResponse, SubjectCreateResponse, StatusResponse, GradeInfo
from app.audit import audit, Action

router = APIRouter()


@router.get("/student/subjects", response_model=list[SubjectResponse],
            summary="List all subjects for students",
            description="Returns all subjects with id, name, symbol, and class_name. Accessible to any authenticated user.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def student_get_subjects(user: str = Depends(verify_user)):
    """List all subjects for student browsing.

    Returns:
        List of dicts with id, name, symbol, and class_name.
    """
    rows = await db_fetch("SELECT id, name, symbol, class_name FROM subjects ORDER BY class_name ASC, name ASC")
    return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": r[3] or "All Classes"} for r in rows]


@router.get("/subjects", response_model=list[SubjectResponse],
            summary="List all subjects",
            description="Returns all subjects with id, name, symbol, and class_name. Excludes 'General' which is a reserved virtual subject.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def get_subjects(teacher_user: str = Depends(verify_teacher)):
    """List all subjects ordered by class and name.

    Excludes 'General' -- a reserved subject that cannot be managed
    but is still available as an upload option and visible to students.

    Returns:
        List of dicts with id, name, symbol, and class_name.
    """
    rows = await db_fetch("SELECT id, name, symbol, class_name FROM subjects WHERE name != 'General' ORDER BY class_name ASC, name ASC")
    return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": r[3] or "All Classes"} for r in rows]


@router.post("/teacher/subjects", response_model=SubjectCreateResponse,
             summary="Create a subject",
             description="Creates a new subject with name, symbol, and optional class_name.",
             tags=["Subjects"],
             responses={400: {"description": "Failed to create subject"}, 401: {"description": "Unauthorized"}})
async def create_subject(subject: SubjectCreate, teacher_user: str = Depends(verify_teacher),
                         request: Request = None):
    """Create a new subject.

    Args:
        subject: Subject creation payload.

    Returns:
        Dict with status, id, name, symbol, and class_name.
    """
    try:
        class_val = subject.class_name or "All Classes"
        subj_id = gen_uid("SUBJ")
        await db_exec("INSERT INTO subjects (id, name, symbol, class_name) VALUES (?, ?, ?, ?)",
                      (subj_id, subject.name, subject.symbol, class_val))
        await audit(action=Action.CREATE_SUBJECT, username=teacher_user, resource_type="subject",
                    resource_id=subj_id, resource_name=subject.name)
        return {"status": "success", "id": subj_id, "name": subject.name, "symbol": subject.symbol, "class_name": class_val}
    except Exception as e:
        logging.error(f"create_subject: {e}")
        raise HTTPException(status_code=400, detail="Failed to create subject")  # i18n: user-facing error message


@router.put("/teacher/subjects/{subject_id}", response_model=StatusResponse,
            summary="Edit a subject", tags=["Subjects"],
            description="Admin-only: update a subject's name, symbol, or class_name. A rename propagates to all resources, resource topics, and courses.",
            responses={400: {"description": "No fields given or duplicate name"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}, 404: {"description": "Subject not found"}})
async def update_subject(subject_id: str, data: dict, admin_user: str = Depends(verify_admin),
                         request: Request = None):
    """Update a subject's name, symbol, or class_name.

    Admin-only: a rename propagates to all resources, resource_topics,
    and courses across every teacher. Renames are propagated to all
    resources and resource_topics referencing the old name. Duplicate
    name check is enforced.

    Raises:
        HTTPException: 400 on duplicate name, 404 if subject not found.
    """
    allowed = {"name", "symbol", "class_name"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")  # i18n: user-facing error message
    def _update_subject(conn):
        """Apply the rename/update inside one transaction; returns the old subject name."""
        row = conn.execute("SELECT id, name FROM subjects WHERE id = ?", (subject_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Subject not found.")  # i18n: user-facing error message
        old_name = row[1]
        if "name" in fields:
            dup = conn.execute("SELECT id FROM subjects WHERE name = ? AND id != ?", (fields["name"], subject_id)).fetchone()
            if dup:
                raise HTTPException(status_code=400, detail="A subject with that name already exists.")  # i18n: user-facing error message
        set_parts = []
        params = []
        if "name" in fields:
            set_parts.append("name = ?")
            params.append(fields["name"])
        if "symbol" in fields:
            set_parts.append("symbol = ?")
            params.append(fields["symbol"])
        if "class_name" in fields:
            set_parts.append("class_name = ?")
            params.append(fields["class_name"])
        if set_parts:
            params.append(subject_id)
            conn.execute(f"UPDATE subjects SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
        if "name" in fields and fields["name"] != old_name:
            conn.execute("UPDATE resources SET subject = ?, subject_id = ? WHERE subject_id = ?", (fields["name"], subject_id, subject_id))
            conn.execute("UPDATE resource_topics SET subject = ? WHERE subject = ?", (fields["name"], old_name))
            conn.execute("UPDATE courses SET subject = ?, subject_id = ? WHERE subject_id = ?", (fields["name"], subject_id, subject_id))
        conn.commit()
        return old_name
    old_name = await db_run(_update_subject)
    await audit(action=Action.UPDATE_SUBJECT, username=admin_user, resource_type="subject",
                resource_id=subject_id, resource_name=fields.get("name", old_name), changes=fields)
    return {"status": "ok"}


@router.delete("/teacher/subjects/{subject_id}", response_model=StatusResponse,
               summary="Delete a subject",
               description="Deletes a subject by id, optionally transferring resources to another subject. Admin-only -- subject deletion removes resources and courses for every teacher.",
               tags=["Subjects"],
               responses={400: {"description": "Invalid request or target subject missing"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}, 404: {"description": "Subject not found"}})
async def delete_subject(subject_id: str, transfer_to: str = Query(None), admin_user: str = Depends(verify_admin),
                         request: Request = None):
    """Delete a subject, optionally transferring its resources first.

    Admin-only: without ``transfer_to`` this deletes physical files and
    DB rows for resources and courses belonging to every teacher.

    If ``transfer_to`` is provided, all resources with the old subject are
    reassigned.  Otherwise their files are removed from disk and DB rows
    deleted before the subject is removed.

    Raises:
        HTTPException: 400 if target subject missing, 404 if not found.
    """
    try:
        def _delete_subject(conn):
            """Transfer or hard-delete subject resources/courses, then drop the subject."""
            row = conn.execute("SELECT name FROM subjects WHERE id = ?", (subject_id,)).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Subject not found.")  # i18n: user-facing error message
            subject_name = row[0]

            if transfer_to:
                if conn.execute("SELECT COUNT(*) FROM subjects WHERE name = ?", (transfer_to,)).fetchone()[0] == 0:
                    raise HTTPException(status_code=400, detail="Target subject does not exist.")  # i18n: user-facing error message
                target_row = conn.execute("SELECT id FROM subjects WHERE name = ?", (transfer_to,)).fetchone()
                target_id = target_row[0] if target_row else ""
                conn.execute("UPDATE resources SET subject = ?, subject_id = ? WHERE subject_id = ?", (transfer_to, target_id, subject_id))
                conn.execute("UPDATE resource_topics SET subject = ? WHERE subject = ?", (transfer_to, subject_name))
                conn.execute("UPDATE courses SET subject = ?, subject_id = ? WHERE subject_id = ?", (transfer_to, target_id, subject_id))
            else:
                files = [r[0] for r in conn.execute("SELECT filename FROM resources WHERE subject = ?", (subject_name,)).fetchall()]
                for fname in files:
                    fp = os.path.join(UPLOAD_DIR, fname) if fname else None
                    if fp and os.path.exists(fp):
                        try:
                            os.remove(fp)
                        except Exception as e:
                            logging.warning(f"Could not remove physical file {fp}: {e}")
                conn.execute("DELETE FROM student_bookmarks WHERE resource_id IN (SELECT id FROM resources WHERE subject_id = ?)", (subject_id,))
                conn.execute("DELETE FROM resources WHERE subject_id = ?", (subject_id,))
                conn.execute("DELETE FROM resource_topics WHERE subject = ?", (subject_name,))
                conn.execute("DELETE FROM courses WHERE subject_id = ?", (subject_id,))

            conn.execute("DELETE FROM subjects WHERE id = ?", (subject_id,))
            conn.commit()
            return subject_name

        subject_name = await db_run(_delete_subject)
        await audit(action=Action.DELETE_SUBJECT, username=admin_user, resource_type="subject",
                    resource_id=subject_id, resource_name=subject_name,
                    context={"transferred_to": transfer_to})
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"delete_subject: {e}", exc_info=True)
        raise HTTPException(status_code=400, detail=f"Failed to delete subject: {e}")  # i18n: user-facing error message


@router.get("/grades", response_model=list[GradeInfo],
            summary="List all grades",
            description="Returns all grade levels ordered by name.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def get_grades(teacher_user: str = Depends(verify_teacher)):
    """List all grade levels.

    Excludes 'General' (grade 0) which is a reserved virtual grade
    representing 'all grades'.

    Returns:
        List of dicts with name for each grade.
    """
    rows = await db_fetch("SELECT id, name FROM grades WHERE name != 'General' ORDER BY name ASC")
    return [{"id": r[0], "name": r[1]} for r in rows]


@router.get("/student/grades", response_model=list[GradeInfo],
            summary="List available grades for students",
            description="Returns all grade levels ordered by name. Accessible to any authenticated user including students.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def student_get_grades(user: str = Depends(verify_user)):
    """List all grade levels for student profile setup.

    Includes 'General' (grade 0) as an option for students who don't
    belong to a specific grade — they see all resources regardless of grade.

    Returns:
        List of dicts with id and name for each grade.
    """
    rows = await db_fetch("SELECT id, name FROM grades ORDER BY name ASC")
    result = [{"id": r[0], "name": r[1]} for r in rows]
    has_general = any(r["name"] == "General" for r in result)
    if not has_general:
        result.insert(0, {"id": "GRD-00000000", "name": "General"})
    return result


@router.post("/grades", response_model=dict,
             summary="Create a grade",
             description="Creates a new grade level with a unique name (max 50 characters).",
             tags=["Subjects"],
             responses={400: {"description": "Missing name, too long, or duplicate"}, 401: {"description": "Unauthorized"}})
async def create_grade(data: dict, teacher_user: str = Depends(verify_teacher),
                       request: Request = None):
    """Create a new grade level.

    Args:
        data: Dict with a name field.

    Returns:
        Dict with status and the created name.
    Raises:
        HTTPException 400: If name is missing, too long, or already exists.
    """
    name = data.get("name", "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Grade name is required.")  # i18n: user-facing error message
    if len(name) > 50:
        raise HTTPException(status_code=400, detail="Grade name too long (max 50 characters).")  # i18n: user-facing error message
    try:
        await db_exec("INSERT INTO grades (id, name) VALUES (?, ?)", (gen_uid("GRD"), name))
        await audit(action=Action.CREATE_GRADE, username=teacher_user, resource_type="grade",
                    resource_id=name, resource_name=name)
        return {"status": "success", "name": name}
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Grade already exists.")  # i18n: user-facing error message


@router.put("/grades/{grade_name}", response_model=StatusResponse,
            summary="Rename a grade", tags=["Subjects"],
            description="Admin-only: rename a grade level, propagating the change to resources and courses.",
            responses={400: {"description": "Missing new_name or duplicate name"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}, 404: {"description": "Grade not found"}})
async def update_grade(grade_name: str, data: dict, admin_user: str = Depends(verify_admin),
                       request: Request = None):
    """Rename a grade level.

    Admin-only: a rename updates grade references on resources and courses
    for every teacher. Extracts numeric grade from old and new names to
    update resource references.  Enforces uniqueness.

    Raises:
        HTTPException: 400 if new name exists, 404 if grade not found.
    """
    new_name = (data.get("new_name") or "").strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="new_name is required.")  # i18n: user-facing error message
    def _rename_grade(conn):
        """Rename the grade row and update numeric grade references in one transaction."""
        if not conn.execute("SELECT id FROM grades WHERE name = ?", (grade_name,)).fetchone():
            raise HTTPException(status_code=404, detail="Grade not found.")  # i18n: user-facing error message
        if conn.execute("SELECT id FROM grades WHERE name = ? AND name != ?", (new_name, grade_name)).fetchone():
            raise HTTPException(status_code=400, detail="A grade with that name already exists.")  # i18n: user-facing error message
        old_num = re.search(r'\d+', grade_name)
        new_num = re.search(r'\d+', new_name)
        if old_num and new_num:
            old_int = int(old_num.group())
            new_int = int(new_num.group())
            conn.execute("UPDATE resources SET grade = ? WHERE grade = ?", (new_int, old_int))
            conn.execute("UPDATE courses SET grade = ? WHERE grade = ?", (new_int, old_int))
        else:
            conn.execute("UPDATE resources SET grade = ? WHERE grade = ?", (new_name, grade_name))
            conn.execute("UPDATE courses SET grade = ? WHERE grade = ?", (new_name, grade_name))
        conn.execute("UPDATE grades SET name = ? WHERE name = ?", (new_name, grade_name))
        conn.commit()
    await db_run(_rename_grade)
    await audit(action=Action.UPDATE_GRADE, username=admin_user, resource_type="grade",
                resource_id=grade_name, resource_name=new_name,
                changes={"name": {"old": grade_name, "new": new_name}})
    return {"status": "ok"}


@router.delete("/grades/{name}", response_model=StatusResponse,
               summary="Delete a grade",
               description="Deletes a grade level, optionally transferring resources to another grade first. Admin-only -- grade deletion removes assets for every teacher.",
               tags=["Subjects"],
               responses={400: {"description": "Target grade not found"}, 401: {"description": "Unauthorized"}, 403: {"description": "Forbidden"}})
async def delete_grade(name: str, transfer_to: str = None, admin_user: str = Depends(verify_admin),
                       request: Request = None):
    """Delete a grade level.

    Admin-only: without ``transfer_to`` this deletes files and DB rows for
    resources and courses belonging to every teacher.

    Args:
        name: The grade name to delete.
        transfer_to: Optional grade to transfer resources to before deletion.

    Returns:
        Status dict indicating success.
    Raises:
        HTTPException 400: If target grade does not exist.
    """
    def _delete_grade(conn):
        """Transfer or hard-delete grade resources/courses, then drop the grade."""
        if transfer_to:
            if conn.execute("SELECT COUNT(*) FROM grades WHERE name = ?", (transfer_to,)).fetchone()[0] == 0:
                raise HTTPException(status_code=400, detail="Target grade does not exist.")  # i18n: user-facing error message
            target_num = re.search(r'\d+', transfer_to)
            src_num = re.search(r'\d+', name)
            if target_num and src_num:
                conn.execute("UPDATE resources SET grade = ? WHERE grade = ?", (int(target_num.group()), int(src_num.group())))
                conn.execute("UPDATE courses SET grade = ? WHERE grade = ?", (target_num.group(), src_num.group()))
            else:
                conn.execute("UPDATE resources SET grade = ? WHERE grade = ?", (transfer_to, name))
                conn.execute("UPDATE courses SET grade = ? WHERE grade = ?", (transfer_to, name))
        else:
            src_num = re.search(r'\d+', name)
            if src_num:
                grade_int = int(src_num.group())
                files = conn.execute("SELECT filename FROM resources WHERE grade = ?", (grade_int,)).fetchall()
                for (fname,) in files:
                    fp = os.path.join(UPLOAD_DIR, fname) if fname else None
                    if fp and os.path.exists(fp):
                        os.remove(fp)
                conn.execute("DELETE FROM student_bookmarks WHERE resource_id IN (SELECT id FROM resources WHERE grade = ?)", (grade_int,))
                conn.execute("DELETE FROM resources WHERE grade = ?", (grade_int,))
            else:
                files = conn.execute("SELECT filename FROM resources WHERE grade = ?", (name,)).fetchall()
                for (fname,) in files:
                    fp = os.path.join(UPLOAD_DIR, fname) if fname else None
                    if fp and os.path.exists(fp):
                        os.remove(fp)
                conn.execute("DELETE FROM student_bookmarks WHERE resource_id IN (SELECT id FROM resources WHERE grade = ?)", (name,))
                conn.execute("DELETE FROM resources WHERE grade = ?", (name,))
            conn.execute("DELETE FROM courses WHERE grade = ?", (src_num.group() if src_num else name,))
        if conn.execute("SELECT COUNT(*) FROM grades WHERE name = ?", (name,)).fetchone()[0] == 0:
            raise HTTPException(status_code=404, detail="Grade not found.")  # i18n: user-facing error message
        conn.execute("DELETE FROM grades WHERE name = ?", (name,))
        conn.commit()
    await db_run(_delete_grade)
    await audit(action=Action.DELETE_GRADE, username=admin_user, resource_type="grade",
                resource_id=name, resource_name=name,
                context={"transferred_to": transfer_to})
    return {"status": "success"}


@router.get("/student/resource-topics", response_model=list[dict],
            summary="List resource topics for students",
            description="Returns resource topics (id, subject, name, position), optionally filtered by subject.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def student_list_resource_topics(user: str = Depends(verify_user),
                                       subject: str = Query(None, description="Subject name (omit for all)")):
    """List resource topics accessible to students.

    Returns topics ordered by position within each subject.
    """
    if subject:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics WHERE subject = ? ORDER BY position ASC",
            (subject,))
    else:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics ORDER BY subject ASC, position ASC")
    return [dict(r) for r in rows]


@router.get("/student/resources-by-topic", response_model=list[dict],
            summary="List resources by topic for students",
            description="Returns approved resources (id, title, type, subject, grade, language, pdfUrl, topic_id, topic_name) filtered by subject and optionally topic.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}, 422: {"description": "Missing subject"}})
async def student_resources_by_topic(user: str = Depends(verify_user),
                                     subject: str = Query(..., description="Subject name"),
                                     topic_id: str = Query("", description="Topic ID (omit for all in subject)"),
                                     grade: Optional[str] = Query(None, description="Grade filter")):
    """List resources for a subject, optionally filtered by topic.

    Returns approved resources ordered by title.
    """
    conditions = ["r.status = 'approved'", "r.subject = ?", "r.resource_type != 'kiwix'"]
    params: list = [subject]
    if topic_id:
        conditions.append("r.topic_id = ?")
        params.append(topic_id)
    if grade:
        conditions.append("(r.grade = ? OR r.grade = 'General')")
        params.append(grade)
    where = " AND ".join(conditions)
    rows = await db_fetch(
        f"""SELECT r.id, r.title, r.resource_type, r.subject, r.grade, r.language,
            r.filename, r.topic_id, COALESCE(rt.name, '') AS topic_name
            FROM resources r
            LEFT JOIN resource_topics rt ON rt.id = r.topic_id
            WHERE {where}
            ORDER BY r.title ASC""",
        tuple(params))
    result = []
    for r in rows:
        result.append({
            "id": r[0], "title": r[1], "type": r[2], "subject": r[3],
            "grade": str(r[4]) if r[4] is not None else "", "language": r[5],
            "pdfUrl": f"/files/{r[6]}" if r[6] else "",
            "topic_id": r[7] or "", "topic_name": r[8],
        })
    return result


# ─── Resource Topics (chapters within subjects) ────────────────────────────

@router.get("/teacher/resource-topics", response_model=list[dict],
            summary="List resource topics",
            description="Returns resource topics (id, subject, name, position). Omit subject to list all.",
            tags=["Subjects"],
            responses={401: {"description": "Unauthorized"}})
async def list_resource_topics(subject: str = Query(None, description="Subject name (omit for all)"),
                               teacher_user: str = Depends(verify_teacher)):
    """List resource topics, optionally filtered by subject.

    Returns topics ordered by position within each subject.
    """
    if subject:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics WHERE subject = ? ORDER BY position ASC",
            (subject,))
    else:
        rows = await db_fetch(
            "SELECT id, subject, name, position FROM resource_topics ORDER BY subject ASC, position ASC")
    return [dict(r) for r in rows]


@router.post("/teacher/resource-topics", response_model=dict,
             summary="Create a resource topic (chapter)",
             description="Creates a new resource topic within a subject, assigning the next position automatically.",
             tags=["Subjects"],
             responses={201: {"description": "Topic created"}, 400: {"description": "Missing fields or topic already exists"}})
async def create_resource_topic(data: dict, teacher_user: str = Depends(verify_teacher),
                                request: Request = None):
    """Create a new resource topic (chapter) within a subject.

    Assigns the next position index automatically. Enforces unique
    (subject, name) constraint.

    Raises:
        HTTPException: 400 if missing fields or duplicate.
    """
    subject = (data.get("subject") or "").strip()
    name = (data.get("name") or "").strip()
    if not subject or not name:
        raise HTTPException(status_code=400, detail="Subject and name are required.")  # i18n: user-facing error message
    last = await db_fetch(
        "SELECT COALESCE(MAX(position), -1) AS mp FROM resource_topics WHERE subject = ?",
        (subject,))
    mp = last[0]["mp"] if last and last[0]["mp"] is not None else -1
    topic_id = gen_uid("RTOP")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    try:
        await db_exec(
            "INSERT INTO resource_topics (id, subject, name, position) VALUES (?, ?, ?, ?)",
            (topic_id, subject, name, mp + 1))
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail=f"Topic '{name}' already exists for subject '{subject}'.")  # i18n: user-facing error message
    await audit(action=Action.CREATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_id=topic_id, resource_name=name, context={"subject": subject})
    return {"status": "ok", "id": topic_id, "subject": subject, "name": name}


@router.put("/teacher/resource-topics/{topic_id}", response_model=StatusResponse,
            summary="Edit a resource topic", tags=["Subjects"],
            description="Updates a resource topic's name or subject, enforcing a unique (subject, name) pair.",
            responses={400: {"description": "No fields given or duplicate name"}, 401: {"description": "Unauthorized"}, 404: {"description": "Topic not found"}})
async def update_resource_topic(topic_id: str, data: dict, teacher_user: str = Depends(verify_teacher),
                                request: Request = None):
    """Update a resource topic's name or subject.

    Checks for duplicate (subject, name) combinations before applying.

    Raises:
        HTTPException: 400 on duplicate, 404 if topic not found.
    """
    allowed = {"name", "subject"}
    fields = {k: v for k, v in data.items() if k in allowed and v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update.")  # i18n: user-facing error message
    row = await db_fetch("SELECT id, subject, name FROM resource_topics WHERE id = ?", (topic_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    old = row[0]
    new_subject = fields.get("subject", old["subject"])
    new_name = fields.get("name", old["name"])
    if "name" in fields or "subject" in fields:
        dup = await db_fetch(
            "SELECT id FROM resource_topics WHERE subject = ? AND name = ? AND id != ?",
            (new_subject, new_name, topic_id))
        if dup:
            raise HTTPException(status_code=400, detail=f"Topic '{new_name}' already exists for subject '{new_subject}'.")  # i18n: user-facing error message
    set_parts, params = [], []
    if "name" in fields:
        set_parts.append("name = ?")
        params.append(fields["name"])
    if "subject" in fields:
        set_parts.append("subject = ?")
        params.append(fields["subject"])
    if set_parts:
        params.append(topic_id)
        await db_exec(f"UPDATE resource_topics SET {', '.join(set_parts)} WHERE id = ?", tuple(params))
    await audit(action=Action.UPDATE_TOPIC, username=teacher_user, resource_type="topic",
                resource_id=topic_id, resource_name=new_name, changes=fields)
    return {"status": "ok"}


@router.delete("/teacher/resource-topics/{topic_id}", response_model=dict,
               summary="Delete a resource topic",
               description="Deletes a resource topic, optionally transferring or hard-deleting its resources.",
               tags=["Subjects"],
               responses={200: {"description": "Deleted"}, 401: {"description": "Unauthorized"}, 404: {"description": "Topic or transfer target not found"}})
async def delete_resource_topic(topic_id: str,
                                delete_resources: bool = Query(False, description="Also hard-delete all resources in this topic"),
                                transfer_to: Optional[str] = Query(None, description="Transfer resources to this topic before deleting"),
                                teacher_user: str = Depends(verify_teacher),
                                request: Request = None):
    """Delete a resource topic.

    If ``transfer_to`` is set, resources are moved to that topic.
    If ``delete_resources`` is true, all resources are hard-deleted.
    Otherwise resources are moved to the General/unassigned bucket.

    Raises:
        HTTPException: 404 if topic or transfer target not found.
    """
    row = await db_fetch("SELECT id FROM resource_topics WHERE id = ?", (topic_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Topic not found.")  # i18n: user-facing error message
    if transfer_to:
        target = await db_fetch("SELECT id, name FROM resource_topics WHERE id = ?", (transfer_to,))
        if not target:
            raise HTTPException(status_code=404, detail="Transfer target topic not found.")  # i18n: user-facing error message
        await db_exec("UPDATE resources SET topic_id = ? WHERE topic_id = ?", (transfer_to, topic_id))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"transferred_to": target[0]["name"]})
        return {"status": "ok", "message": f"Topic deleted. Resources transferred to '{target[0]['name']}'.",
                "transferred_to": target[0]["name"]}  # i18n: user-facing success message
    if delete_resources:
        resources = await db_fetch("SELECT id, filename FROM resources WHERE topic_id = ?", (topic_id,))
        if resources:
            # Collect file paths for batch removal
            filepaths = [os.path.join(UPLOAD_DIR, r["filename"]) for r in resources if r["filename"]]
            if filepaths:
                def _remove_files(paths):
                    """Delete a batch of resource files from disk, tolerating missing files."""
                    for fp in paths:
                        try:
                            if os.path.exists(fp):
                                os.remove(fp)
                        except Exception as e:
                            logging.warning(f"Could not remove file {fp}: {e}")
                await asyncio.to_thread(_remove_files, filepaths)

            # Batch DB deletions instead of N+1
            resource_ids = [r["id"] for r in resources]
            placeholders = ",".join("?" for _ in resource_ids)
            await db_exec(f"DELETE FROM student_bookmarks WHERE resource_id IN ({placeholders})", tuple(resource_ids))
            await db_exec(f"DELETE FROM scholar_downloads WHERE resource_id IN ({placeholders})", tuple(resource_ids))
            await db_exec(f"DELETE FROM resources WHERE id IN ({placeholders})", tuple(resource_ids))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id, context={"resources_deleted": len(resources)})
        return {"status": "ok", "message": f"Topic and {len(resources)} resource(s) deleted."}  # i18n: user-facing success message
    else:
        await db_exec("UPDATE resources SET topic_id = '' WHERE topic_id = ?", (topic_id,))
        await db_exec("DELETE FROM resource_topics WHERE id = ?", (topic_id,))
        await audit(action=Action.DELETE_TOPIC, username=teacher_user, resource_type="topic",
                    resource_id=topic_id)
        return {"status": "ok", "message": "Topic deleted. Resources moved to General."}  # i18n: user-facing success message
