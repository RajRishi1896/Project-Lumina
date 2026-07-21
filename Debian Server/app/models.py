"""Pydantic models for the Lumina EduMesh Hub API."""
from pydantic import BaseModel, ConfigDict, Field
from typing import Optional


class TimeSync(BaseModel):
    """Time synchronization response from the hub."""
    current_time: str = Field(..., description="Current server time in ISO 8601 format.", example="2026-06-07T12:00:00")


class ScholarReg(BaseModel):
    """Student registration request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique username for the scholar.", example="student42")
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the scholar.", example="Alice")
    password: Optional[str] = Field(default="lumina2026", min_length=8, max_length=128, description="Account password. Defaults to a known fallback.", example="lumina2026")


class AdminStudentCreate(BaseModel):
    """Admin-initiated student account creation payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique username for the student.", example="student_new")
    password: Optional[str] = Field(default="lumina2026", min_length=8, max_length=128, description="Account password. Defaults to a known fallback.", example="lumina2026")
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the student.", example="Bob")
    grade: Optional[str] = Field(default=None, max_length=50, description="Grade or class assignment.", example="Grade 10")


class StudentLoginRequest(BaseModel):
    """Student login request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Scholar username.", example="student42")
    password: str = Field(..., min_length=1, max_length=128, description="Scholar password.", example="mypassword")



class StudentChangePasswordRequest(BaseModel):
    """Password change request for a student account."""
    scholar_id: Optional[str] = Field(default="", max_length=100, description="Scholar identifier. Leave empty for self-service.", example="42")
    old_password: str = Field(..., max_length=128, description="Current password for verification.", example="oldpass")
    new_password: str = Field(..., min_length=8, max_length=128, description="Desired new password.", example="newpass123")


class SubjectCreate(BaseModel):
    """Subject creation request payload."""
    name: str = Field(..., min_length=1, max_length=100, description="Subject name.", example="Mathematics")
    symbol: str = Field(..., max_length=50, description="Short symbol or icon label.", example="MATH")
    class_name: Optional[str] = Field(default="All Classes", max_length=100, description="Class or grade this subject applies to.", example="Grade 10")


class TeacherCreate(BaseModel):
    """Teacher account creation request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique teacher username.", example="teacher_john")
    password: str = Field(..., min_length=8, max_length=128, description="Account password.", example="TeacherPass1")
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the teacher.", example="John Doe")
    department: Optional[str] = Field(default="General", max_length=100, description="Department assignment.", example="Science")


class NameUpdate(BaseModel):
    """Teacher display name update request."""
    name: str = Field(..., min_length=1, max_length=100, description="New display name.", example="Dr. Smith")

class DepartmentUpdate(BaseModel):
    """Teacher department update request."""
    department: str = Field(..., min_length=1, max_length=100, description="New department name.", example="Mathematics")

class StudyTimeSync(BaseModel):
    """Aggregate study time sync from the student app."""
    total_seconds: int = Field(..., ge=0, le=604800, description="Total study seconds in the current week.", example=3600)
    streak_days: int = Field(default=0, ge=0, le=365, description="Consecutive study days.", example=5)


class SubjectTimeItem(BaseModel):
    """Per-subject study time entry."""
    name: str = Field(..., min_length=1, max_length=100, description="Subject name.", example="Mathematics")
    minutes: int = Field(..., ge=0, le=10080, description="Study minutes spent on this subject.", example=45)


class SubjectTimeSync(BaseModel):
    """Bulk per-subject study time sync payload."""
    subjects: list[SubjectTimeItem] = Field(default_factory=list, description="List of per-subject time entries.", example=[{"name": "Mathematics", "minutes": 45}])


# ── Response Models ──────────────────────────────────────────────────────────

class StatusResponse(BaseModel):
    """Generic status response."""
    status: str = Field(..., description="Status indicator, typically 'ok' or 'pong'.", example="ok")



class TokenResponse(BaseModel):
    """Session token response with associated credentials."""
    token: str = Field(..., description="Session token.", example="abc123")
    refresh_token: str = Field(..., description="One-time refresh token.", example="LUMINA_REF-abc")
    persistent_key: str = Field(..., description="One-time persistent key.", example="LUMINA_PER-abc")


class LoginTokenResponse(BaseModel):
    """Teacher/admin login response with user metadata."""
    access_token: str = Field(..., description="Bearer access token.", example="abc123")
    token_type: str = Field(default="bearer", description="Token type.", example="bearer")
    username: str = Field(..., description="Authenticated username.", example="admin")
    name: str = Field(..., description="Display name.", example="Admin")
    department: str = Field(..., description="User department.", example="General")
    scholar_id: str = Field(..., description="Scholar ID for the user.", example="LUMINA_01-Tabc")
    role: str = Field(..., description="User role: admin or teacher.", example="admin")
    reset_required: int = Field(..., description="Whether a password reset is required.", example=0)


class ScholarRegisterResponse(BaseModel):
    """Student registration response."""
    id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-abc")
    token: str = Field(..., description="Session token.", example="abc123")
    refresh_token: str = Field(..., description="One-time refresh token.", example="LUMINA_REF-abc")
    persistent_key: str = Field(..., description="One-time persistent key.", example="LUMINA_PER-abc")


class StudentLoginResponse(BaseModel):
    """Student login response with profile info."""
    status: str = Field(..., description="Status indicator.", example="ok")
    scholar_id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-abc")
    token: str = Field(..., description="Session token.", example="abc123")
    refresh_token: str = Field(..., description="One-time refresh token.", example="LUMINA_REF-abc")
    persistent_key: str = Field(..., description="One-time persistent key.", example="LUMINA_PER-abc")
    name: str = Field(..., description="Student display name.", example="Alice")
    grade: str = Field(..., description="Student grade or class.", example="Grade 10")
    reset_required: bool = Field(..., description="Whether a password reset is required.", example=False)


class WhoamiResponse(BaseModel):
    """Current authenticated user identity."""
    username: str = Field(..., description="Authenticated username.", example="admin")
    role: str = Field(..., description="User role: admin, teacher, or student.", example="admin")


class SubjectResponse(BaseModel):
    """Subject definition."""
    id: str = Field(..., description="Subject ID.", example="SUBJ-90286c83")
    name: str = Field(..., description="Subject name.", example="Mathematics")
    symbol: str = Field(..., description="Subject icon symbol.", example="MATH")
    class_name: str = Field(..., description="Associated class or grade.", example="Grade 10")


# ── Additional Response Models ───────────────────────────────────────────────

class RestoreResponse(BaseModel):
    """Download history restore response."""
    download_history: list[str] = Field(default_factory=list, description="List of downloaded resource IDs.", example=["RES-a1b2c3d4", "RES-e5f6g7h8"])


class StudentAnalyticsResponse(BaseModel):
    """Student analytics from the student's own perspective."""
    study_minutes_this_week: int = Field(..., description="Total study minutes this week.", example=120)
    streak_days: int = Field(..., description="Consecutive study days.", example=5)
    resources_saved: int = Field(..., description="Number of saved resources.", example=3)
    subjects: list = Field(default_factory=list, description="Per-subject study minute breakdown.", example=[{"name": "Mathematics", "minutes": 120}])


class IconUploadResponse(BaseModel):
    """Profile icon upload result."""
    status: str = Field(..., description="Operation status.", example="ok")
    filename: str = Field(..., description="Saved icon filename.", example="abc_icon.png")


class StudentProfileResponse(BaseModel):
    """Student profile information."""
    name: str = Field(..., description="Display name.", example="Alice")
    grade: str = Field(..., description="Grade or class.", example="Grade 10")
    scholar_id: str = Field(..., description="Scholar ID.", example="LUMINA_01-abc")


class WeeklyBreakdownResponse(BaseModel):
    """Weekly study breakdown for a student."""
    today_minutes: int = Field(..., description="Study minutes today.", example=30)
    weekly_data: dict = Field(default_factory=dict, description="Day-to-minute mapping for past 7 days.", example={"Mon": 30, "Tue": 45, "Wed": 0})


class ScholarListItem(BaseModel):
    """Minimal scholar info for teacher listing."""
    id: str = Field(..., description="Scholar ID.", example="LUMINA_01-abc")
    name: str = Field(..., description="Display name.", example="Alice")
    reset_required: int = Field(..., description="Whether password reset is required.", example=0)


class TeacherSummary(BaseModel):
    """Teacher profile summary."""
    username: str = Field(..., description="Teacher username.", example="teacher_john")
    name: str = Field(..., description="Display name.", example="John Doe")
    department: str = Field(..., description="Department.", example="Science")
    scholar_id: Optional[str] = Field(default=None, description="Scholar ID.", example="LUMINA_01-Tabc")
    reset_required: int = Field(default=0, description="Whether password reset is required.", example=0)


class TeacherProfileResponse(BaseModel):
    """Authenticated teacher/admin profile."""
    username: str = Field(..., description="Username.", example="admin")
    name: Optional[str] = Field(default=None, description="Display name.", example="Admin")
    department: Optional[str] = Field(default=None, description="Department.", example="General")
    scholar_id: Optional[str] = Field(default=None, description="Scholar ID.", example="LUMINA_01-Tabc")
    reset_required: int = Field(default=0, description="Whether password reset is required.", example=0)


class TeacherCreateResponse(BaseModel):
    """Teacher account creation response."""
    status: str = Field(..., description="Operation status.", example="success")
    username: str = Field(..., description="Created username.", example="teacher_john")
    name: str = Field(..., description="Display name.", example="John Doe")
    department: str = Field(..., description="Department.", example="Science")
    scholar_id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-Tabc")


class SubjectCreateResponse(BaseModel):
    """Subject creation response."""
    status: str = Field(..., description="Operation status.", example="success")
    id: str = Field(..., description="Assigned subject ID.", example="SUBJ-abc123")
    name: str = Field(..., description="Subject name.", example="Mathematics")
    symbol: str = Field(..., description="Subject symbol.", example="MATH")
    class_name: str = Field(..., description="Associated class.", example="Grade 10")


class GradeInfo(BaseModel):
    """Grade level info."""
    id: str = Field(..., description="Grade ID.", example="GRD-a1b2c3d4")
    name: str = Field(..., description="Grade name.", example="Grade 10")


class CatalogResourceResponse(BaseModel):
    """Resource catalog entry."""
    id: str = Field(..., description="Resource ID.", example="GRD-00000000-SUBJ-00000000-a1b2c3d4")
    title: str = Field(..., description="Resource title.", example="Chapter 1")
    pdfUrl: str = Field(..., description="File download URL.", example="/files/abc.pdf")
    type: str = Field(..., description="Resource type.", example="textbook")
    subject: str = Field(..., description="Subject.", example="Mathematics")
    grade: str = Field(..., description="Grade level.", example="10")
    mtime: float = Field(..., description="Last modified timestamp.", example=1234567890.0)
    downloads: int = Field(default=0, description="Number of unique student downloads.", example=12)
    topic_name: str = Field(default="", description="Topic name if assigned.", example="Chapter 1")


class FileEntryResponse(BaseModel):
    """Uploaded file info."""
    name: str = Field(..., description="File name.", example="chapter1.pdf")
    size: int = Field(..., description="File size in bytes.", example=1048576)


class LimitsResponse(BaseModel):
    """Upload limits."""
    zim_upload_max_size: int = Field(..., description="Max ZIM upload size in bytes.", example=524288000)


class UploadResponse(BaseModel):
    """Resource upload response."""
    status: str = Field(..., description="Operation status.", example="success")
    filename: str = Field(..., description="Server-assigned filename.", example="abc.pdf")
    original_name: str = Field(..., description="Original upload filename.", example="chapter1.pdf")


class ZimUploadResponse(BaseModel):
    """ZIM archive upload response."""
    status: str = Field(..., description="Operation status.", example="success")
    imported: list = Field(default_factory=list, description="List of imported article filenames.", example=["article_1.html", "article_2.html"])


class DeleteResourceResponse(BaseModel):
    """Resource deletion result."""
    status: str = Field(..., description="Operation status.", example="success")
    action: str = Field(..., description="Delete action taken.", example="hard_deleted")
    download_count: Optional[int] = Field(default=None, description="Active download count if soft-deprecated.")


class AdminSummary(BaseModel):
    """Admin user summary."""
    username: str = Field(..., description="Admin username.", example="admin2")
    name: str = Field(..., description="Display name.", example="Admin Two")
    department: str = Field(..., description="Department.", example="System")
    scholar_id: str = Field(default="", description="UUID-based scholar ID.", example="LUMINA_01-Tabc123")
    reset_required: int = Field(default=0, description="Whether password reset is required.", example=0)


class AdminCreateResponse(BaseModel):
    """Admin/teacher/student account creation response."""
    status: str = Field(..., description="Operation status.", example="success")
    username: str = Field(..., description="Created username.", example="newuser")
    name: str = Field(..., description="Display name.", example="New User")
    scholar_id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-abc")


class AuditLogResponse(BaseModel):
    """Admin audit log response."""
    log: list = Field(default_factory=list, description="List of log line strings.", example=["[2026-06-15 10:00:00] admin: resource 42 approved"])


class SettingsResponse(BaseModel):
    """Admin settings response."""
    log_retention: str = Field(..., description="Log retention policy.", example="30d")


class HubStatsResponse(BaseModel):
    """Hub statistics response (actual /stats shape)."""
    scholars: int = Field(..., description="Total registered scholars.", example=42)
    resources: int = Field(..., description="Total resources.", example=100)
    subjects: int = Field(..., description="Total subjects.", example=8)
    published_courses: int = Field(default=0, description="Published courses.", example=5)
    draft_courses: int = Field(default=0, description="Draft courses.", example=3)
    storage: str = Field(..., description="Storage usage string.", example="4.5 GB / 100.0 GB")
    storage_percent: float = Field(..., description="Storage usage percentage.", example=4.5)
    battery_percent: int = Field(..., description="Battery percentage.", example=85)
    uptime: str = Field(..., description="Uptime string.", example="2h 15m")
    disk_usage: str = Field(..., description="Disk usage string.", example="4.5 GB / 100.0 GB")


class StudentListResponse(BaseModel):
    """Wrapped student list response."""
    students: list = Field(default_factory=list, description="List of student summaries.", example=[{"name": "Alice", "grade": "Grade 10"}])


class ZimArchiveResponse(BaseModel):
    """Response for a ZIM archive listing."""
    id: str = Field(..., description="Archive UUID.", example="abc123")
    filename: str = Field(..., description="Server filename.", example="wikipedia_en_2024-11.zim")
    title: str = Field(..., description="Archive title.", example="Wikipedia EN")
    article_count: int = Field(..., description="Number of articles in the archive.", example=65000)
    language: str = Field(..., description="ISO 639-1 language code.", example="en")
    uploaded_at: str = Field(..., description="Upload timestamp (ISO 8601).", example="2026-07-01T12:00:00")
    file_size: int = Field(..., description="File size in bytes.", example=524288000)


class ZimArticleResponse(BaseModel):
    """ZIM article metadata."""
    article_id: str = Field(..., description="Article unique ID.", example="ABC123")
    title: str = Field(..., description="Article title.", example="Photosynthesis")
    archive_id: str = Field(default="", description="ID of the archive this article belongs to.", example="abc123")
    has_thumbnail: bool = Field(default=False, description="Whether a thumbnail exists on disk.", example=False)


class ZimPageResponse(BaseModel):
    """ZIM article HTML content response."""
    id: str = Field(..., description="Article ID.", example="ABC123")
    html: str = Field(..., description="Raw HTML content of the article.", example="<html>...")


# ── LMS Course Models ─────────────────────────────────────────────────────────

class CourseCreate(BaseModel):
    """Payload for creating a new course."""
    model_config = ConfigDict(extra='ignore')
    title: str = Field(..., description="Course title", max_length=120)
    description: str = Field("", description="Short summary")
    subject: str = Field("General", description="From approved subject taxonomy")
    grade: int = Field(0, description="Grade level 0-13", ge=0, le=13)
    language: str = Field("en", description="ISO 639-1 code")


class CourseResponse(BaseModel):
    """Course metadata returned to clients."""
    id: str = Field(..., description="Unique course identifier.", example="CRS-abc123")
    title: str = Field(..., description="Course title.", example="Introduction to Algebra")
    description: str = Field("", description="Short course summary.", example="Basic algebra concepts")
    subject: str = Field("", description="Subject category.", example="Mathematics")
    grade: int = Field(0, description="Grade level (0=General, 1-13).", example=9)
    language: str = Field("en", description="ISO 639-1 language code.", example="en")
    cover_image: str = Field("", description="Cover image filename.", example="cover.png")
    published: int = Field(0, description="Publish status (0=draft, 1=published, -1=archived).", example=1)
    teacher_username: str = Field("", description="Username of the creating teacher.", example="teacher_john")
    enrollment_count: int = Field(0, description="Number of enrolled students.", example=15)
    created_at: str = Field("", description="Creation timestamp (ISO 8601).", example="2026-07-01T12:00:00")
    updated_at: str = Field("", description="Last update timestamp (ISO 8601).", example="2026-07-15T10:30:00")


class ProgressSync(BaseModel):
    """Student progress sync payload."""
    current_position: int = Field(0, ge=0, description="Index of the last viewed resource.", example=3)
    completed_count: int = Field(0, ge=0, description="Number of resources completed.", example=2)


class EnrollResponse(BaseModel):
    """Enrollment operation response."""
    status: str = Field("ok", description="Operation status.", example="ok")
    course_id: str = Field("", description="Enrolled course identifier.", example="CRS-abc123")
    message: str = Field("", description="Human-readable message.", example="Enrolled successfully")


class QuizAttemptSubmit(BaseModel):
    """Quiz attempt submission payload."""
    attempt_id: str = Field(..., description="Client-generated UUID for idempotency.", example="abc-123")
    attempt_number: int = Field(1, ge=1, description="Sequential attempt number for this student/resource.", example=1)
    score: float = Field(0.0, ge=0.0, le=1.0, description="Score as a fraction (0.0 to 1.0).", example=0.85)
    passed: int = Field(0, description="Whether the attempt passed (1=yes, 0=no).", example=1)
    answers_json: str = Field("", description="Serialized JSON of the student's answers.", example='[{"id":"q1","selected":"a"}]')
    started_at: str = Field("", description="ISO 8601 timestamp when the quiz was started.", example="2026-07-15T10:00:00")
    submitted_at: str = Field("", description="ISO 8601 timestamp when the quiz was submitted.", example="2026-07-15T10:15:00")
    time_taken_seconds: int = Field(0, description="Total time taken in seconds.", example=900)
    quiz_version: int = Field(1, description="Quiz version at time of attempt.", example=1)
    threshold_at_submission: float = Field(0.0, description="Pass threshold at time of submission.", example=0.6)


class QuizAttemptResponse(BaseModel):
    """A stored quiz attempt record."""
    id: str = Field(..., description="Attempt identifier.", example="abc-123")
    student_id: str = Field(..., description="Student scholar ID.", example="LUMINA_01-abc")
    course_id: str = Field(..., description="Course identifier.", example="CRS-abc123")
    resource_id: str = Field(..., description="Quiz resource identifier.", example="quiz-abc123")
    attempt_number: int = Field(..., description="Sequential attempt number.", example=1)
    score: float = Field(0.0, description="Score as a fraction (0.0 to 1.0).", example=0.85)
    passed: int = Field(0, description="Whether the attempt passed.", example=1)
    answers_json: str = Field("", description="Serialized student answers.", example='[{"id":"q1","selected":"a"}]')
    started_at: str = Field("", description="Quiz start timestamp.", example="2026-07-15T10:00:00")
    submitted_at: str = Field("", description="Quiz submission timestamp.", example="2026-07-15T10:15:00")
    time_taken_seconds: int = Field(0, description="Time taken in seconds.", example=900)
    quiz_version: int = Field(1, description="Quiz version at time of attempt.", example=1)
    threshold_at_submission: float = Field(0.0, description="Pass threshold at submission time.", example=0.6)


class SimilarLinkCreate(BaseModel):
    """Payload to link a course as similar."""
    similar_course_id: str = Field(..., description="UUID of the course to link as similar")



