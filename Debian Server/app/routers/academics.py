"""Subject and grade management routes."""
import os
import re
import shutil
import sqlite3
import logging
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from app.async_db import db_exec, db_fetch, db_run
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

    Excludes 'General', a reserved subject that cannot be managed
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
               description="Deletes a subject by id, optionally transferring resources to another subject. Admin-only: subject deletion removes resources and courses for every teacher.",
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
                # Remove orphaned course directories for this subject
                course_ids = [r[0] for r in conn.execute("SELECT id FROM courses WHERE subject_id = ?", (subject_id,)).fetchall()]
                for cid in course_ids:
                    course_dir = os.path.join(UPLOAD_DIR, "courses", cid)
                    if os.path.isdir(course_dir):
                        shutil.rmtree(course_dir, ignore_errors=True)
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
        raise HTTPException(status_code=400, detail="Failed to delete subject.")  # i18n: user-facing error message


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
    belong to a specific grade. They see all resources regardless of grade.

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
               description="Deletes a grade level, optionally transferring resources to another grade first. Admin-only: grade deletion removes assets for every teacher.",
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
                # Remove orphaned course directories for this grade
                course_ids = [r[0] for r in conn.execute("SELECT id FROM courses WHERE grade = ?", (grade_int,)).fetchall()]
                for cid in course_ids:
                    course_dir = os.path.join(UPLOAD_DIR, "courses", cid)
                    if os.path.isdir(course_dir):
                        shutil.rmtree(course_dir, ignore_errors=True)
            else:
                files = conn.execute("SELECT filename FROM resources WHERE grade = ?", (name,)).fetchall()
                for (fname,) in files:
                    fp = os.path.join(UPLOAD_DIR, fname) if fname else None
                    if fp and os.path.exists(fp):
                        os.remove(fp)
                conn.execute("DELETE FROM student_bookmarks WHERE resource_id IN (SELECT id FROM resources WHERE grade = ?)", (name,))
                conn.execute("DELETE FROM resources WHERE grade = ?", (name,))
                course_ids = [r[0] for r in conn.execute("SELECT id FROM courses WHERE grade = ?", (name,)).fetchall()]
                for cid in course_ids:
                    course_dir = os.path.join(UPLOAD_DIR, "courses", cid)
                    if os.path.isdir(course_dir):
                        shutil.rmtree(course_dir, ignore_errors=True)
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

