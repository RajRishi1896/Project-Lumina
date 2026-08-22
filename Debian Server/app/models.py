"""Pydantic models for the Lumina EduMesh Hub API."""
from pydantic import BaseModel, ConfigDict, Field
from typing import Optional


class TimeSync(BaseModel):
    """Time synchronization response from the hub."""
    current_time: str = Field(..., description="Current server time in ISO 8601 format.", json_schema_extra={"example": "2026-06-07T12:00:00"})
class ScholarReg(BaseModel):
    """Student registration request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique username for the scholar.", json_schema_extra={"example": "student42"})
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the scholar. Defaults to username if empty.", json_schema_extra={"example": "Alice"})
    password: Optional[str] = Field(default="lumina2026", min_length=8, max_length=128, description="Account password. Defaults to a known fallback.", json_schema_extra={"example": "lumina2026"})
    grade: Optional[str] = Field(default=None, max_length=50, description="Grade assignment. Defaults to '0' (General) if not provided.", json_schema_extra={"example": "0"})
class AdminStudentCreate(BaseModel):
    """Admin-initiated student account creation payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique username for the student.", json_schema_extra={"example": "student_new"})
    password: Optional[str] = Field(default="lumina2026", min_length=8, max_length=128, description="Account password. Defaults to a known fallback.", json_schema_extra={"example": "lumina2026"})
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the student.", json_schema_extra={"example": "Bob"})
    grade: Optional[str] = Field(default=None, max_length=50, description="Grade or class assignment.", json_schema_extra={"example": "Grade 10"})
class StudentLoginRequest(BaseModel):
    """Student login request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Scholar username.", json_schema_extra={"example": "student42"})
    password: str = Field(..., min_length=1, max_length=128, description="Scholar password.", json_schema_extra={"example": "mypassword"})
class StudentChangePasswordRequest(BaseModel):
    """Password change request for a student account."""
    scholar_id: Optional[str] = Field(default="", max_length=100, description="Scholar identifier. Leave empty for self-service.", json_schema_extra={"example": "42"})
    old_password: Optional[str] = Field(default=None, max_length=128, description="Current password for verification. Not required when resetting after a forced reset.", json_schema_extra={"example": "oldpass"})
    new_password: str = Field(..., min_length=8, max_length=128, description="Desired new password.", json_schema_extra={"example": "newpass123"})
class SubjectCreate(BaseModel):
    """Subject creation request payload."""
    name: str = Field(..., min_length=1, max_length=100, description="Subject name.", json_schema_extra={"example": "Mathematics"})
    symbol: str = Field(..., max_length=50, description="Short symbol or icon label.", json_schema_extra={"example": "MATH"})
    class_name: Optional[str] = Field(default="All Classes", max_length=100, description="Class or grade this subject applies to.", json_schema_extra={"example": "Grade 10"})
class TeacherCreate(BaseModel):
    """Teacher account creation request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique teacher username.", json_schema_extra={"example": "teacher_john"})
    password: str = Field(..., min_length=8, max_length=128, description="Account password.", json_schema_extra={"example": "TeacherPass1"})
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the teacher.", json_schema_extra={"example": "John Doe"})
    department: Optional[str] = Field(default="General", max_length=100, description="Department assignment.", json_schema_extra={"example": "Science"})
class NameUpdate(BaseModel):
    """Teacher display name update request."""
    name: str = Field(..., min_length=1, max_length=100, description="New display name.", json_schema_extra={"example": "Dr. Smith"})
class DepartmentUpdate(BaseModel):
    """Teacher department update request."""
    department: str = Field(..., min_length=1, max_length=100, description="New department name.", json_schema_extra={"example": "Mathematics"})
class StudyTimeSync(BaseModel):
    """Aggregate study time sync from the student app."""
    total_seconds: int = Field(..., ge=0, le=604800, description="Total study seconds in the current week.", json_schema_extra={"example": 3600})
    streak_days: int = Field(default=0, ge=0, le=365, description="Consecutive study days.", json_schema_extra={"example": 5})
class SubjectTimeItem(BaseModel):
    """Per-subject study time entry."""
    name: str = Field(..., min_length=1, max_length=100, description="Subject name.", json_schema_extra={"example": "Mathematics"})
    minutes: int = Field(..., ge=0, le=10080, description="Study minutes spent on this subject.", json_schema_extra={"example": 45})
class SubjectTimeSync(BaseModel):
    """Bulk per-subject study time sync payload."""
    subjects: list[SubjectTimeItem] = Field(default_factory=list, description="List of per-subject time entries.", json_schema_extra={"example": [{"name": "Mathematics", "minutes": 45}]})
# ── Response Models ──────────────────────────────────────────────────────────

class StatusResponse(BaseModel):
    """Generic status response."""
    status: str = Field(..., description="Status indicator, typically 'ok' or 'pong'.", json_schema_extra={"example": "ok"})
class TokenResponse(BaseModel):
    """Session token response with associated credentials."""
    token: str = Field(..., description="Session token.", json_schema_extra={"example": "abc123"})
    refresh_token: str = Field(..., description="One-time refresh token.", json_schema_extra={"example": "LUMINA_REF-abc"})
    persistent_key: str = Field(..., description="One-time persistent key.", json_schema_extra={"example": "LUMINA_PER-abc"})
class LoginTokenResponse(BaseModel):
    """Teacher/admin login response with user metadata."""
    access_token: str = Field(..., description="Bearer access token.", json_schema_extra={"example": "abc123"})
    token_type: str = Field(default="bearer", description="Token type.", json_schema_extra={"example": "bearer"})
    username: str = Field(..., description="Authenticated username.", json_schema_extra={"example": "admin"})
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "Admin"})
    department: str = Field(..., description="User department.", json_schema_extra={"example": "General"})
    scholar_id: str = Field(..., description="Scholar ID for the user.", json_schema_extra={"example": "LUMINA_01-Tabc"})
    role: str = Field(..., description="User role: admin or teacher.", json_schema_extra={"example": "admin"})
    reset_required: int = Field(..., description="Whether a password reset is required.", json_schema_extra={"example": 0})
class ScholarRegisterResponse(BaseModel):
    """Student registration response."""
    id: str = Field(..., description="Assigned scholar ID.", json_schema_extra={"example": "LUMINA_01-abc"})
    token: str = Field(..., description="Session token.", json_schema_extra={"example": "abc123"})
    refresh_token: str = Field(..., description="One-time refresh token.", json_schema_extra={"example": "LUMINA_REF-abc"})
    persistent_key: str = Field(..., description="One-time persistent key.", json_schema_extra={"example": "LUMINA_PER-abc"})
class StudentLoginResponse(BaseModel):
    """Student login response with profile info."""
    status: str = Field(..., description="Status indicator.", json_schema_extra={"example": "ok"})
    scholar_id: str = Field(..., description="Assigned scholar ID.", json_schema_extra={"example": "LUMINA_01-abc"})
    token: str = Field(..., description="Session token.", json_schema_extra={"example": "abc123"})
    refresh_token: str = Field(..., description="One-time refresh token.", json_schema_extra={"example": "LUMINA_REF-abc"})
    persistent_key: str = Field(..., description="One-time persistent key.", json_schema_extra={"example": "LUMINA_PER-abc"})
    name: str = Field(..., description="Student display name.", json_schema_extra={"example": "Alice"})
    grade: str = Field(..., description="Student grade or class.", json_schema_extra={"example": "Grade 10"})
    reset_required: bool = Field(..., description="Whether a password reset is required.", json_schema_extra={"example": False})
class WhoamiResponse(BaseModel):
    """Current authenticated user identity."""
    username: str = Field(..., description="Authenticated username.", json_schema_extra={"example": "admin"})
    role: str = Field(..., description="User role: admin, teacher, or student.", json_schema_extra={"example": "admin"})
class SubjectResponse(BaseModel):
    """Subject definition."""
    id: str = Field(..., description="Subject ID.", json_schema_extra={"example": "SUBJ-90286c83"})
    name: str = Field(..., description="Subject name.", json_schema_extra={"example": "Mathematics"})
    symbol: str = Field(..., description="Subject icon symbol.", json_schema_extra={"example": "MATH"})
    class_name: str = Field(..., description="Associated class or grade.", json_schema_extra={"example": "Grade 10"})
# ── Additional Response Models ───────────────────────────────────────────────

class StudentAnalyticsResponse(BaseModel):
    """Student analytics from the student's own perspective."""
    study_minutes_this_week: int = Field(..., description="Total study minutes this week.", json_schema_extra={"example": 120})
    streak_days: int = Field(..., description="Consecutive study days.", json_schema_extra={"example": 5})
    resources_saved: int = Field(..., description="Number of saved resources.", json_schema_extra={"example": 3})
    subjects: list = Field(default_factory=list, description="Per-subject study minute breakdown.", json_schema_extra={"example": [{"name": "Mathematics", "minutes": 120}]})
    quiz_scores: list = Field(default_factory=list, description="Quiz best scores list.", json_schema_extra={"example": [{"title": "Math Quiz", "best_score": 0.85, "attempts_count": 3}]})
class IconUploadResponse(BaseModel):
    """Profile icon upload result."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "ok"})
    filename: str = Field(..., description="Saved icon filename.", json_schema_extra={"example": "abc_icon.png"})
class StudentProfileResponse(BaseModel):
    """Student profile information."""
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "Alice"})
    grade: str = Field(..., description="Grade or class.", json_schema_extra={"example": "Grade 10"})
    scholar_id: str = Field(..., description="Scholar ID.", json_schema_extra={"example": "LUMINA_01-abc"})
class ScholarListItem(BaseModel):
    """Minimal scholar info for teacher listing."""
    id: str = Field(..., description="Scholar ID.", json_schema_extra={"example": "LUMINA_01-abc"})
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "Alice"})
    username: str = Field("", description="Login username.", json_schema_extra={"example": "alice"})
    reset_required: int = Field(..., description="Whether password reset is required.", json_schema_extra={"example": 0})
class TeacherSummary(BaseModel):
    """Teacher profile summary."""
    username: str = Field(..., description="Teacher username.", json_schema_extra={"example": "teacher_john"})
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "John Doe"})
    department: str = Field(..., description="Department.", json_schema_extra={"example": "Science"})
    scholar_id: Optional[str] = Field(default=None, description="Scholar ID.", json_schema_extra={"example": "LUMINA_01-Tabc"})
    reset_required: int = Field(default=0, description="Whether password reset is required.", json_schema_extra={"example": 0})
class TeacherProfileResponse(BaseModel):
    """Authenticated teacher/admin profile."""
    username: str = Field(..., description="Username.", json_schema_extra={"example": "admin"})
    name: Optional[str] = Field(default=None, description="Display name.", json_schema_extra={"example": "Admin"})
    department: Optional[str] = Field(default=None, description="Department.", json_schema_extra={"example": "General"})
    scholar_id: Optional[str] = Field(default=None, description="Scholar ID.", json_schema_extra={"example": "LUMINA_01-Tabc"})
    reset_required: int = Field(default=0, description="Whether password reset is required.", json_schema_extra={"example": 0})
class TeacherCreateResponse(BaseModel):
    """Teacher account creation response."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "success"})
    username: str = Field(..., description="Created username.", json_schema_extra={"example": "teacher_john"})
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "John Doe"})
    department: str = Field(..., description="Department.", json_schema_extra={"example": "Science"})
    scholar_id: str = Field(..., description="Assigned scholar ID.", json_schema_extra={"example": "LUMINA_01-Tabc"})
class SubjectCreateResponse(BaseModel):
    """Subject creation response."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "success"})
    id: str = Field(..., description="Assigned subject ID.", json_schema_extra={"example": "SUBJ-abc123"})
    name: str = Field(..., description="Subject name.", json_schema_extra={"example": "Mathematics"})
    symbol: str = Field(..., description="Subject symbol.", json_schema_extra={"example": "MATH"})
    class_name: str = Field(..., description="Associated class.", json_schema_extra={"example": "Grade 10"})
class GradeInfo(BaseModel):
    """Grade level info."""
    id: str = Field(..., description="Grade ID.", json_schema_extra={"example": "GRD-a1b2c3d4"})
    name: str = Field(..., description="Grade name.", json_schema_extra={"example": "Grade 10"})
class CatalogResourceResponse(BaseModel):
    """Resource catalog entry."""
    id: str = Field(..., description="Resource ID.", json_schema_extra={"example": "GRD-00000000-SUBJ-00000000-a1b2c3d4"})
    title: str = Field(..., description="Resource title.", json_schema_extra={"example": "Chapter 1"})
    pdfUrl: str = Field(..., description="File download URL.", json_schema_extra={"example": "/files/abc.pdf"})
    type: str = Field(..., description="Resource type.", json_schema_extra={"example": "textbook"})
    subject: str = Field(..., description="Subject.", json_schema_extra={"example": "Mathematics"})
    grade: str = Field(..., description="Grade level.", json_schema_extra={"example": "10"})
    mtime: float = Field(..., description="Last modified timestamp.", json_schema_extra={"example": 1234567890.0})
    downloads: int = Field(default=0, description="Number of unique student downloads.", json_schema_extra={"example": 12})
    topic_name: str = Field(default="", description="Topic name if assigned.", json_schema_extra={"example": "Chapter 1"})
    page_count: int = Field(default=0, description="Number of pages for PDF resources (0 when unknown).", json_schema_extra={"example": 120})
    duration_seconds: int = Field(default=0, description="Duration in seconds for video resources (0 when unknown).", json_schema_extra={"example": 900})
    file_size: int = Field(default=0, description="File size in bytes (0 when unknown).", json_schema_extra={"example": 1048576})
class FileEntryResponse(BaseModel):
    """Uploaded file info."""
    name: str = Field(..., description="File name.", json_schema_extra={"example": "chapter1.pdf"})
    size: int = Field(..., description="File size in bytes.", json_schema_extra={"example": 1048576})
class LimitsResponse(BaseModel):
    """Upload limits."""
    zim_upload_max_size: int = Field(..., description="Max ZIM upload size in bytes.", json_schema_extra={"example": 524288000})
class UploadResponse(BaseModel):
    """Resource upload response."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "success"})
    filename: str = Field(..., description="Server-assigned filename.", json_schema_extra={"example": "abc.pdf"})
    original_name: str = Field(..., description="Original upload filename.", json_schema_extra={"example": "chapter1.pdf"})
class ZimUploadResponse(BaseModel):
    """ZIM archive upload response."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "success"})
    imported: list = Field(default_factory=list, description="List of imported article filenames.", json_schema_extra={"example": ["article_1.html", "article_2.html"]})
class DeleteResourceResponse(BaseModel):
    """Resource deletion result."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "success"})
    action: str = Field(..., description="Delete action taken.", json_schema_extra={"example": "hard_deleted"})
    download_count: Optional[int] = Field(default=None, description="Active download count if soft-deprecated.", json_schema_extra={"example": 3})
class AdminSummary(BaseModel):
    """Admin user summary."""
    username: str = Field(..., description="Admin username.", json_schema_extra={"example": "admin2"})
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "Admin Two"})
    department: str = Field(..., description="Department.", json_schema_extra={"example": "System"})
    scholar_id: str = Field(default="", description="UUID-based scholar ID.", json_schema_extra={"example": "LUMINA_01-Tabc123"})
    reset_required: int = Field(default=0, description="Whether password reset is required.", json_schema_extra={"example": 0})
class AdminCreateResponse(BaseModel):
    """Admin/teacher/student account creation response."""
    status: str = Field(..., description="Operation status.", json_schema_extra={"example": "success"})
    username: str = Field(..., description="Created username.", json_schema_extra={"example": "newuser"})
    name: str = Field(..., description="Display name.", json_schema_extra={"example": "New User"})
    scholar_id: str = Field(..., description="Assigned scholar ID.", json_schema_extra={"example": "LUMINA_01-abc"})
class AuditLogResponse(BaseModel):
    """Admin audit log response."""
    log: list = Field(default_factory=list, description="List of log line strings.", json_schema_extra={"example": ["[2026-06-15 10:00:00] admin: resource 42 approved"]})
class SettingsResponse(BaseModel):
    """Admin settings response."""
    log_retention: str = Field(..., description="Log retention policy.", json_schema_extra={"example": "30d"})
class HubStatsResponse(BaseModel):
    """Hub statistics response (actual /stats shape)."""
    scholars: int = Field(..., description="Total registered scholars.", json_schema_extra={"example": 42})
    resources: int = Field(..., description="Total resources.", json_schema_extra={"example": 100})
    subjects: int = Field(..., description="Total subjects.", json_schema_extra={"example": 8})
    published_courses: int = Field(default=0, description="Published courses.", json_schema_extra={"example": 5})
    draft_courses: int = Field(default=0, description="Draft courses.", json_schema_extra={"example": 3})
    storage: str = Field(..., description="Storage usage string.", json_schema_extra={"example": "4.5 GB / 100.0 GB"})
    storage_percent: float = Field(..., description="Storage usage percentage.", json_schema_extra={"example": 4.5})
    battery_percent: Optional[int] = Field(default=None, description="Battery percentage, or null when the hub has no battery.", json_schema_extra={"example": 85})
    battery_charging: bool = Field(default=False, description="Whether the battery is currently charging.", json_schema_extra={"example": True})
    uptime: str = Field(..., description="Uptime string.", json_schema_extra={"example": "2h 15m"})
    disk_usage: str = Field(..., description="Disk usage string.", json_schema_extra={"example": "4.5 GB / 100.0 GB"})
class StudentListResponse(BaseModel):
    """Wrapped student list response."""
    students: list = Field(default_factory=list, description="List of student summaries.", json_schema_extra={"example": [{"name": "Alice", "grade": "Grade 10"}]})
class ZimArchiveResponse(BaseModel):
    """Response for a ZIM archive listing."""
    id: str = Field(..., description="Archive UUID.", json_schema_extra={"example": "abc123"})
    filename: str = Field(..., description="Server filename.", json_schema_extra={"example": "wikipedia_en_2024-11.zim"})
    title: str = Field(..., description="Archive title.", json_schema_extra={"example": "Wikipedia EN"})
    article_count: int = Field(..., description="Number of articles in the archive.", json_schema_extra={"example": 65000})
    language: str = Field(..., description="ISO 639-1 language code.", json_schema_extra={"example": "en"})
    uploaded_at: str = Field(..., description="Upload timestamp (ISO 8601).", json_schema_extra={"example": "2026-07-01T12:00:00"})
    file_size: int = Field(..., description="File size in bytes.", json_schema_extra={"example": 524288000})
class ZimArticleResponse(BaseModel):
    """ZIM article metadata."""
    article_id: str = Field(..., description="Article unique ID.", json_schema_extra={"example": "ABC123"})
    title: str = Field(..., description="Article title.", json_schema_extra={"example": "Photosynthesis"})
    archive_id: str = Field(default="", description="ID of the archive this article belongs to.", json_schema_extra={"example": "abc123"})
    has_thumbnail: bool = Field(default=False, description="Whether a thumbnail exists on disk.", json_schema_extra={"example": False})
class ZimPageResponse(BaseModel):
    """ZIM article HTML content response."""
    id: str = Field(..., description="Article ID.", json_schema_extra={"example": "ABC123"})
    html: str = Field(..., description="Raw HTML content of the article.", json_schema_extra={"example": "<html>..."})
class ZimSearchResponse(BaseModel):
    """Paginated ZIM search or browse result with metadata."""
    articles: list[ZimArticleResponse] = Field(default_factory=list, description="Matching articles.", json_schema_extra={"example": [{"article_id": "ABC123", "title": "Photosynthesis"}]})
    total: int = Field(default=0, description="Approximate total matching articles.", json_schema_extra={"example": 1500})
    offset: int = Field(default=0, description="Current offset in the result set.", json_schema_extra={"example": 0})
    has_more: bool = Field(default=False, description="Whether more results are available.", json_schema_extra={"example": True})
# ── LMS Course Models ─────────────────────────────────────────────────────────

class CourseCreate(BaseModel):
    """Payload for creating a new course."""
    model_config = ConfigDict(extra='ignore')
    title: str = Field(..., description="Course title", max_length=120, json_schema_extra={"example": "Introduction to Algebra"})
    description: str = Field("", description="Short summary", json_schema_extra={"example": "Basic algebra concepts"})
    subject: str = Field("General", description="From approved subject taxonomy", json_schema_extra={"example": "Mathematics"})
    grade: int = Field(0, description="Grade level 0-13", ge=0, le=13, json_schema_extra={"example": 9})
    language: str = Field("en", description="ISO 639-1 code", json_schema_extra={"example": "en"})
class CourseQuizCreate(BaseModel):
    """Payload for creating or editing a course quiz."""
    model_config = ConfigDict(extra='ignore')
    title: str = Field("Quiz", description="Quiz title", max_length=120, json_schema_extra={"example": "Chapter 1 Quiz"})
    questions: list = Field(default_factory=list, description="List of question payloads", json_schema_extra={"example": [{"text": "What is 2+2?", "options": ["3", "4"], "answer": 1}]})
    topic_id: str = Field("", max_length=64, description="Topic this quiz belongs to, if any", json_schema_extra={"example": "TPC-abc123"})
    time_limit_minutes: int = Field(0, ge=0, le=1440, description="Time limit in minutes, 0 = none", json_schema_extra={"example": 30})
    pass_threshold: int = Field(60, ge=0, le=100, description="Passing percentage", json_schema_extra={"example": 60})
    max_attempts: int = Field(0, ge=0, le=50, description="Max attempts, 0 = unlimited", json_schema_extra={"example": 3})
    shuffle_mode: str = Field("", max_length=20, description="Question shuffle mode", json_schema_extra={"example": "none"})
class CourseResponse(BaseModel):
    """Course metadata returned to clients."""
    id: str = Field(..., description="Unique course identifier.", json_schema_extra={"example": "CRS-abc123"})
    title: str = Field(..., description="Course title.", json_schema_extra={"example": "Introduction to Algebra"})
    description: str = Field("", description="Short course summary.", json_schema_extra={"example": "Basic algebra concepts"})
    subject: str = Field("", description="Subject category.", json_schema_extra={"example": "Mathematics"})
    grade: int = Field(0, description="Grade level (0=General, 1-13).", json_schema_extra={"example": 9})
    language: str = Field("en", description="ISO 639-1 language code.", json_schema_extra={"example": "en"})
    cover_image: str = Field("", description="Cover image filename.", json_schema_extra={"example": "cover.png"})
    published: int = Field(0, description="Publish status (0=draft, 1=published, -1=archived).", json_schema_extra={"example": 1})
    teacher_username: str = Field("", description="Username of the creating teacher.", json_schema_extra={"example": "teacher_john"})
    enrollment_count: int = Field(0, description="Number of enrolled students.", json_schema_extra={"example": 15})
    created_at: str = Field("", description="Creation timestamp (ISO 8601).", json_schema_extra={"example": "2026-07-01T12:00:00"})
    updated_at: str = Field("", description="Last update timestamp (ISO 8601).", json_schema_extra={"example": "2026-07-15T10:30:00"})
class ProgressSync(BaseModel):
    """Student progress sync payload."""
    current_position: int = Field(0, ge=0, description="Index of the last viewed resource.", json_schema_extra={"example": 3})
    completed_count: int = Field(0, ge=0, description="Number of resources completed.", json_schema_extra={"example": 2})
    completed: int = Field(0, ge=0, le=1, description="Whether the student finished the whole course (1=yes, 0=no).", json_schema_extra={"example": 0})
class EnrollResponse(BaseModel):
    """Enrollment operation response."""
    status: str = Field("ok", description="Operation status.", json_schema_extra={"example": "ok"})
    course_id: str = Field("", description="Enrolled course identifier.", json_schema_extra={"example": "CRS-abc123"})
    message: str = Field("", description="Human-readable message.", json_schema_extra={"example": "Enrolled successfully"})
class QuizAttemptSubmit(BaseModel):
    """Quiz attempt submission payload."""
    attempt_id: str = Field(..., description="Client-generated UUID for idempotency.", json_schema_extra={"example": "abc-123"})
    attempt_number: int = Field(1, ge=1, description="Sequential attempt number for this student/resource.", json_schema_extra={"example": 1})
    score: float = Field(0.0, ge=0.0, le=1.0, description="Score as a fraction (0.0 to 1.0).", json_schema_extra={"example": 0.85})
    passed: int = Field(0, description="Whether the attempt passed (1=yes, 0=no).", json_schema_extra={"example": 1})
    answers_json: str = Field("", description="Serialized JSON of the student's answers.", json_schema_extra={"example": '[{"id":"q1","selected":"a"}]'})
    started_at: str = Field("", description="ISO 8601 timestamp when the quiz was started.", json_schema_extra={"example": "2026-07-15T10:00:00"})
    submitted_at: str = Field("", description="ISO 8601 timestamp when the quiz was submitted.", json_schema_extra={"example": "2026-07-15T10:15:00"})
    time_taken_seconds: int = Field(0, description="Total time taken in seconds.", json_schema_extra={"example": 900})
    quiz_version: int = Field(1, description="Quiz version at time of attempt.", json_schema_extra={"example": 1})
    threshold_at_submission: float = Field(0.0, description="Pass threshold at time of submission.", json_schema_extra={"example": 0.6})
class QuizAttemptResponse(BaseModel):
    """A stored quiz attempt record."""
    id: str = Field(..., description="Attempt identifier.", json_schema_extra={"example": "abc-123"})
    student_id: str = Field(..., description="Student scholar ID.", json_schema_extra={"example": "LUMINA_01-abc"})
    course_id: str = Field(..., description="Course identifier.", json_schema_extra={"example": "CRS-abc123"})
    resource_id: str = Field(..., description="Quiz resource identifier.", json_schema_extra={"example": "quiz-abc123"})
    attempt_number: int = Field(..., description="Sequential attempt number.", json_schema_extra={"example": 1})
    score: float = Field(0.0, description="Score as a fraction (0.0 to 1.0).", json_schema_extra={"example": 0.85})
    passed: int = Field(0, description="Whether the attempt passed.", json_schema_extra={"example": 1})
    answers_json: str = Field("", description="Serialized student answers.", json_schema_extra={"example": '[{"id":"q1","selected":"a"}]'})
    started_at: str = Field("", description="Quiz start timestamp.", json_schema_extra={"example": "2026-07-15T10:00:00"})
    submitted_at: str = Field("", description="Quiz submission timestamp.", json_schema_extra={"example": "2026-07-15T10:15:00"})
    time_taken_seconds: int = Field(0, description="Time taken in seconds.", json_schema_extra={"example": 900})
    quiz_version: int = Field(1, description="Quiz version at time of attempt.", json_schema_extra={"example": 1})
    threshold_at_submission: float = Field(0.0, description="Pass threshold at submission time.", json_schema_extra={"example": 0.6})
    results: Optional[list] = Field(None, description="Per-question grading for the client's review screen. Present only on submit responses: question_id, correct, correct_answers, explanation.", json_schema_extra={"example": [{"question_id": "q1", "correct": True, "correct_answers": ["2"], "explanation": ""}]})
class SimilarLinkCreate(BaseModel):
    """Payload to link a course as similar."""
    similar_course_id: str = Field(..., description="UUID of the course to link as similar", json_schema_extra={"example": "CRS-abc123"})
class BookmarkItem(BaseModel):
    """A single bookmark entry for sync."""
    resource_id: str = Field(..., description="Resource ID.", json_schema_extra={"example": "RES-abc123"})
    title: str = Field("", description="Resource title.", json_schema_extra={"example": "Chapter 1"})
    subject: str = Field("", description="Resource subject.", json_schema_extra={"example": "Mathematics"})
    grade: str = Field("", description="Resource grade.", json_schema_extra={"example": "Grade 10"})
    resource_type: str = Field("", description="Resource type.", json_schema_extra={"example": "textbook"})
class BookmarkSync(BaseModel):
    """Full bookmark sync payload that replaces all server bookmarks."""
    bookmarks: list[BookmarkItem] = Field(default_factory=list, description="All bookmarks the student has.", json_schema_extra={"example": [{"resource_id": "RES-abc123", "title": "Chapter 1"}]})
class EnrolledCourseItem(BaseModel):
    """An enrolled course with progress for restore."""
    course_id: str = Field(..., description="Unique course identifier.", json_schema_extra={"example": "CRS-abc123"})
    title: str = Field("", description="Course title.", json_schema_extra={"example": "Algebra Basics"})
    description: str = Field("", description="Short course description.", json_schema_extra={"example": "Linear equations and graphs."})
    subject: str = Field("", description="Subject the course belongs to.", json_schema_extra={"example": "math"})
    grade: int = Field(0, description="Target grade level.", json_schema_extra={"example": 9})
    language: str = Field("en", description="ISO 639-1 course language code.", json_schema_extra={"example": "en"})
    cover_image: str = Field("", description="Cover image URL or path.", json_schema_extra={"example": "/files/covers/a1b2.png"})
    published: int = Field(0, description="1 if the course is published.", json_schema_extra={"example": 1})
    teacher_username: str = Field("", description="Username of the course teacher.", json_schema_extra={"example": "teacher1"})
    enrollment_count: int = Field(0, description="Number of enrolled students.", json_schema_extra={"example": 12})
    created_at: str = Field("", description="Creation timestamp (UTC ISO 8601).", json_schema_extra={"example": "2026-08-01T10:00:00Z"})
    updated_at: str = Field("", description="Last update timestamp (UTC ISO 8601).", json_schema_extra={"example": "2026-08-10T10:00:00Z"})
    current_position: int = Field(0, description="Student's current resource index.", json_schema_extra={"example": 3})
    completed_count: int = Field(0, description="Resources completed by the student.", json_schema_extra={"example": 2})
    total_resources: int = Field(0, description="Total resources in the course.", json_schema_extra={"example": 10})
    completed: int = Field(0, description="1 if the student completed the course.", json_schema_extra={"example": 0})
    enrolled_at: str = Field("", description="Enrollment timestamp (UTC ISO 8601).", json_schema_extra={"example": "2026-08-02T10:00:00Z"})
class EnrolledCoursesResponse(BaseModel):
    """All courses the student is enrolled in."""
    courses: list[EnrolledCourseItem] = Field(default_factory=list, description="All courses the student is enrolled in.", json_schema_extra={"example": [{"course_id": "CRS-abc123", "title": "Algebra"}]})
class QuizBestScoreResponse(BaseModel):
    """Best quiz score for a student on a specific quiz."""
    best_score: float = Field(0.0, description="Best score as fraction 0-1.", json_schema_extra={"example": 0.85})
    best_attempt_id: str = Field("", description="ID of the best attempt.", json_schema_extra={"example": "abc-123"})
    attempts_count: int = Field(0, description="Total attempts made.", json_schema_extra={"example": 3})
class QuizBestScoreUpdate(BaseModel):
    """Update the best quiz score after submission."""
    score: float = Field(..., ge=0.0, le=1.0, description="Score as fraction 0-1.", json_schema_extra={"example": 0.85})
    attempt_id: str = Field(..., min_length=1, description="ID of this attempt.", json_schema_extra={"example": "abc-123"})