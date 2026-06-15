"""Pydantic models for the Lumina EduMesh Hub API."""
from pydantic import BaseModel, Field
from typing import List, Optional


class TimeSync(BaseModel):
    """Time synchronization response from the hub."""
    current_time: str = Field(..., description="Current server time in ISO 8601 format.", example="2026-06-07T12:00:00")


class ScholarReg(BaseModel):
    """Student registration request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique username for the scholar.", example="student42")
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the scholar.", example="Alice")
    password: Optional[str] = Field(default="lumina2026", min_length=4, max_length=128, description="Account password. Defaults to a known fallback.", example="lumina2026")


class AdminStudentCreate(BaseModel):
    """Admin-initiated student account creation payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique username for the student.", example="student_new")
    password: Optional[str] = Field(default="lumina2026", min_length=4, max_length=128, description="Account password. Defaults to a known fallback.", example="lumina2026")
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the student.", example="Bob")
    grade: Optional[str] = Field(default=None, max_length=50, description="Grade or class assignment.", example="Grade 10")


class StudentLoginRequest(BaseModel):
    """Student login request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Scholar username.", example="student42")
    password: str = Field(..., min_length=1, max_length=128, description="Scholar password.", example="mypassword")


class TokenRefreshRequest(BaseModel):
    """Session refresh using a refresh token."""
    refresh_token: str = Field(..., min_length=1, description="Refresh token issued at login.", example="LUMINA_REF-abc123")


class TokenRenewRequest(BaseModel):
    """Long-lived session renewal using a persistent key."""
    persistent_key: str = Field(..., min_length=1, description="Persistent key issued at login.", example="LUMINA_PER-abc123")


class StudentChangePasswordRequest(BaseModel):
    """Password change request for a student account."""
    scholar_id: Optional[str] = Field(default="", max_length=100, description="Scholar identifier. Leave empty for self-service.", example="42")
    old_password: str = Field(..., max_length=128, description="Current password for verification.", example="oldpass")
    new_password: str = Field(..., min_length=4, max_length=128, description="Desired new password.", example="newpass123")


class SubjectDeleteRequest(BaseModel):
    """Subject deletion request with optional transfer target."""
    id: Optional[str] = Field(default=None, max_length=100, description="Subject ID to delete.", example="subj_1")
    name: Optional[str] = Field(default=None, max_length=100, description="Subject name to delete.", example="Mathematics")
    transfer_to: Optional[str] = Field(default=None, max_length=100, description="Transfer resources to this subject.", example="Algebra")


class ChangePasswordRequest(BaseModel):
    """Password change request for a teacher or admin account."""
    old_password: str = Field(..., description="Current password for verification.", example="currentPass1")
    new_password: str = Field(..., description="Desired new password.", example="newPass123")


class ForceChangePasswordRequest(BaseModel):
    """Admin-forced password reset (no old password required)."""
    new_password: str = Field(..., description="New password to assign.", example="newAdminPass1")


class SubjectCreate(BaseModel):
    """Subject creation request payload."""
    name: str = Field(..., min_length=1, max_length=100, description="Subject name.", example="Mathematics")
    symbol: str = Field(..., max_length=50, description="Short symbol or icon label.", example="MATH")
    class_name: Optional[str] = Field(default="All Classes", max_length=100, description="Class or grade this subject applies to.", example="Grade 10")


class TeacherCreate(BaseModel):
    """Teacher account creation request payload."""
    username: str = Field(..., min_length=1, max_length=100, description="Unique teacher username.", example="teacher_john")
    password: str = Field(..., min_length=4, max_length=128, description="Account password.", example="TeacherPass1")
    name: Optional[str] = Field(default=None, max_length=100, description="Display name for the teacher.", example="John Doe")
    department: Optional[str] = Field(default="General", max_length=100, description="Department assignment.", example="Science")


class NameUpdate(BaseModel):
    """Teacher display name update request."""
    name: str = Field(..., min_length=1, max_length=100, description="New display name.", example="Dr. Smith")


class DepartmentUpdate(BaseModel):
    """Teacher department update request."""
    department: str = Field(..., min_length=1, max_length=100, description="New department name.", example="Mathematics")


class ProfileUpdate(BaseModel):
    """Student profile update request."""
    name: Optional[str] = Field(default=None, max_length=100, description="New display name.", example="Alice")
    grade: Optional[str] = Field(default=None, max_length=50, description="New grade or class.", example="Grade 10")


class IconUpload(BaseModel):
    """Subject icon upload payload (base64-encoded image)."""
    image_data: str = Field(..., description="Base64-encoded image data.", example="iVBORw0KGgo...")
    image_ext: str = Field(default="png", description="File extension for the image.", example="png")


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
    subjects: list[SubjectTimeItem] = Field(default_factory=list, description="List of per-subject time entries.")


class LogRetentionUpdate(BaseModel):
    """Log retention policy update request."""
    policy: str = Field(..., description="Retention policy value. Supported: 24h, 7d, 30d, 3m, 6m, never, none.", example="30d")


# ── Response Models ──────────────────────────────────────────────────────────

class StatusResponse(BaseModel):
    """Generic status response."""
    status: str = Field(..., description="Status indicator, typically 'ok' or 'pong'.", example="ok")


class UptimeResponse(StatusResponse):
    """Health check response with uptime."""
    uptime: float = Field(..., description="Server uptime in seconds.", example=3600.0)


class PingResponse(StatusResponse):
    """Ping liveness probe response."""


class TaskStatusResponse(BaseModel):
    """Background task status and result."""
    id: str = Field(..., description="Task UUID.", example="abc-123")
    type: str = Field(..., description="Task type name.", example="thumbnail_generation")
    status: str = Field(..., description="Task status: pending, running, completed, or failed.", example="completed")
    result: Optional[dict] = Field(default=None, description="Task result data if completed.")
    error: Optional[str] = Field(default=None, description="Error message if failed.")


class TokenResponse(BaseModel):
    """Session token response with associated credentials."""
    token: str = Field(..., description="Session token.", example="abc123")
    refresh_token: str = Field(..., description="One-time refresh token.", example="LUMINA_REF-abc")
    persistent_key: str = Field(..., description="One-time persistent key.", example="LUMINA_PER-abc")
    encryption_key: str = Field(..., description="AES-256-GCM encryption key for encrypted routes.", example="hexkey...")


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
    encryption_key: str = Field(..., description="AES-256-GCM encryption key.", example="hexkey...")


class ScholarRegisterResponse(BaseModel):
    """Student registration response."""
    id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-abc")
    token: str = Field(..., description="Session token.", example="abc123")
    refresh_token: str = Field(..., description="One-time refresh token.", example="LUMINA_REF-abc")
    persistent_key: str = Field(..., description="One-time persistent key.", example="LUMINA_PER-abc")
    encryption_key: str = Field(..., description="AES-256-GCM encryption key.", example="hexkey...")


class StudentLoginResponse(BaseModel):
    """Student login response with profile info."""
    status: str = Field(..., description="Status indicator.", example="ok")
    scholar_id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-abc")
    token: str = Field(..., description="Session token.", example="abc123")
    refresh_token: str = Field(..., description="One-time refresh token.", example="LUMINA_REF-abc")
    persistent_key: str = Field(..., description="One-time persistent key.", example="LUMINA_PER-abc")
    encryption_key: str = Field(..., description="AES-256-GCM encryption key.", example="hexkey...")
    name: str = Field(..., description="Student display name.", example="Alice")
    grade: str = Field(..., description="Student grade or class.", example="Grade 10")
    reset_required: bool = Field(..., description="Whether a password reset is required.", example=False)


class WhoamiResponse(BaseModel):
    """Current authenticated user identity."""
    username: str = Field(..., description="Authenticated username.", example="admin")
    role: str = Field(..., description="User role: admin, teacher, or student.", example="admin")


class UserCreateResponse(BaseModel):
    """User creation operation result."""
    success: bool = Field(..., description="Whether the operation succeeded.", example=True)
    message: str = Field(..., description="Human-readable result message.", example="Account created successfully")


class StudentSummary(BaseModel):
    """Summary of a single student for listing."""
    id: str = Field(..., description="Scholar ID.", example="LUMINA_01-abc")
    username: str = Field(..., description="Student username.", example="student42")
    name: Optional[str] = Field(default=None, description="Display name.", example="Alice")
    grade: Optional[str] = Field(default=None, description="Grade or class.", example="Grade 10")
    total_minutes: int = Field(default=0, description="Total weekly study minutes.", example=120)
    streak_days: int = Field(default=0, description="Consecutive study days.", example=5)
    resources_saved: int = Field(default=0, description="Number of saved/downloaded resources.", example=3)
    profile_icon: Optional[str] = Field(default=None, description="Profile icon filename.", example="icon_1.png")
    last_active: Optional[str] = Field(default=None, description="Last activity timestamp.", example="2026-06-12T10:00:00")


class SubjectResponse(BaseModel):
    """Subject definition."""
    id: int = Field(..., description="Subject ID.", example=1)
    name: str = Field(..., description="Subject name.", example="Mathematics")
    symbol: str = Field(..., description="Subject icon symbol.", example="MATH")
    class_name: str = Field(..., description="Associated class or grade.", example="Grade 10")


class ResourceResponse(BaseModel):
    """Educational resource metadata."""
    id: int = Field(..., description="Resource ID.", example=1)
    title: str = Field(..., description="Resource title.", example="Chapter 1")
    subject: str = Field(..., description="Subject name.", example="Mathematics")
    grade: int = Field(..., description="Grade level.", example=10)
    language: str = Field(..., description="ISO 639-1 language code.", example="en")
    resource_type: str = Field(..., description="Resource type label.", example="textbook")
    filename: str = Field(..., description="Server-side filename.", example="abc123.pdf")
    original_name: str = Field(..., description="Original upload filename.", example="chapter1.pdf")
    description: Optional[str] = Field(default=None, description="Resource description.", example="A textbook chapter")
    uploaded_at: str = Field(..., description="Upload timestamp.", example="2026-06-01T12:00:00")
    file_size: Optional[int] = Field(default=None, description="File size in bytes.", example=1048576)


class SyncResponse(BaseModel):
    """Student sync operation result."""
    status: str = Field(..., description="Operation status.", example="ok")
    message: str = Field(..., description="Sync result message.", example="Synced successfully")


class AnalyticsResponse(BaseModel):
    """Student analytics data."""
    student_id: str = Field(..., description="Scholar ID.", example="LUMINA_01-abc")
    username: str = Field(..., description="Student username.", example="student42")
    name: Optional[str] = Field(default=None, description="Display name.", example="Alice")
    total_minutes: int = Field(..., description="Total weekly study minutes.", example=120)
    streak_days: int = Field(..., description="Consecutive study days.", example=5)
    resources_saved: int = Field(..., description="Number of saved/downloaded resources.", example=3)
    subject_breakdown: list = Field(default_factory=list, description="Per-subject study time breakdown.")
    timeline: list = Field(default_factory=list, description="Activity timeline entries.")


class SubjectTimeEntry(BaseModel):
    """Single subject study time entry."""
    date: str = Field(..., description="Date of activity.", example="2026-06-12")
    minutes: int = Field(..., description="Study minutes on that date.", example=30)
    subject: str = Field(..., description="Subject name.", example="Mathematics")


class ProfileUpdateResponse(BaseModel):
    """Profile update result."""
    success: bool = Field(..., description="Whether the update succeeded.", example=True)


class PasswordChangeResponse(BaseModel):
    """Password change operation result."""
    success: bool = Field(..., description="Whether the change succeeded.", example=True)


class LogEntry(BaseModel):
    """Single admin audit log entry."""
    id: int = Field(..., description="Log entry ID.", example=1)
    action: str = Field(..., description="Action description.", example="Created admin account 'john'")
    username: str = Field(..., description="Acting user.", example="admin")
    timestamp: str = Field(..., description="ISO 8601 timestamp.", example="2026-06-12T10:00:00")


class LogSettingsResponse(BaseModel):
    """Admin log settings and retention configuration."""
    retention_policy: str = Field(..., description="Current retention policy.", example="30d")
    total_logs: int = Field(..., description="Total log entries.", example=150)


class StatsResponse(BaseModel):
    """Hub statistics response."""
    total_students: int = Field(..., description="Total registered students.", example=42)
    total_teachers: int = Field(..., description="Total registered teachers.", example=3)
    total_resources: int = Field(..., description="Total resources in catalog.", example=100)
    total_subjects: int = Field(..., description="Total subjects configured.", example=8)
    active_today: int = Field(..., description="Students active in the last 24 hours.", example=15)
    storage_used_gb: float = Field(..., description="Storage used in GB.", example=4.5)
    storage_total_gb: float = Field(..., description="Total storage capacity in GB.", example=100.0)
    uptime_seconds: float = Field(..., description="Server uptime in seconds.", example=86400.0)


class TimeSyncResponse(BaseModel):
    """Time synchronization response."""
    current_time: str = Field(..., description="Current server time in ISO 8601 format.", example="2026-06-12T12:00:00")


class StreamResponse(BaseModel):
    """Media stream metadata."""
    pass


class ScholarSummary(BaseModel):
    """Summary of a single scholar."""
    id: str = Field(..., description="Scholar ID.", example="LUMINA_01-abc")
    username: str = Field(..., description="Scholar username.", example="student42")
    name: Optional[str] = Field(default=None, description="Display name.", example="Alice")
    grade: Optional[str] = Field(default=None, description="Grade or class.", example="Grade 10")
    last_active: Optional[str] = Field(default=None, description="Last activity timestamp.", example="2026-06-12T10:00:00")


class DeleteResponse(BaseModel):
    """Deletion operation result."""
    success: bool = Field(..., description="Whether the deletion succeeded.", example=True)
    message: str = Field(..., description="Human-readable result message.", example="Resource deleted")


# ── Additional Response Models ───────────────────────────────────────────────

class RestoreResponse(BaseModel):
    """Download history restore response."""
    download_history: list = Field(default_factory=list, description="List of downloaded resource IDs.")


class StudentAnalyticsResponse(BaseModel):
    """Student analytics from the student's own perspective."""
    study_minutes_this_week: int = Field(..., description="Total study minutes this week.", example=120)
    streak_days: int = Field(..., description="Consecutive study days.", example=5)
    resources_saved: int = Field(..., description="Number of saved resources.", example=3)
    subjects: list = Field(default_factory=list, description="Per-subject study minute breakdown.")


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
    weekly_data: dict = Field(default_factory=dict, description="Day-to-minute mapping for past 7 days.")


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
    name: str = Field(..., description="Grade name.", example="Grade 10")


class GradeCreateResponse(BaseModel):
    """Grade creation response."""
    status: str = Field(..., description="Operation status.", example="success")
    name: str = Field(..., description="Created grade name.", example="Grade 10")


class CatalogResourceResponse(BaseModel):
    """Resource catalog entry."""
    id: int = Field(..., description="Resource ID.", example=1)
    title: str = Field(..., description="Resource title.", example="Chapter 1")
    pdfUrl: str = Field(..., description="File download URL.", example="/files/abc.pdf")
    type: str = Field(..., description="Resource type.", example="textbook")
    subject: str = Field(..., description="Subject.", example="Mathematics")
    grade: str = Field(..., description="Grade level.", example="10")
    mtime: float = Field(..., description="Last modified timestamp.", example=1234567890.0)


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
    imported: list = Field(default_factory=list, description="List of imported article filenames.")


class DeleteResourceResponse(BaseModel):
    """Resource deletion result."""
    status: str = Field(..., description="Operation status.", example="success")
    action: str = Field(..., description="Delete action taken.", example="hard_deleted")
    download_count: Optional[int] = Field(default=None, description="Active download count if soft-deprecated.")


class AdminStatusResponse(BaseModel):
    """Default admin enabled status."""
    enabled: bool = Field(..., description="Whether the default admin account is enabled.", example=True)


class AdminSummary(BaseModel):
    """Admin user summary."""
    username: str = Field(..., description="Admin username.", example="admin2")
    name: str = Field(..., description="Display name.", example="Admin Two")
    department: str = Field(..., description="Department.", example="System")
    reset_required: int = Field(default=0, description="Whether password reset is required.", example=0)


class AdminCreateResponse(BaseModel):
    """Admin/teacher/student account creation response."""
    status: str = Field(..., description="Operation status.", example="success")
    username: str = Field(..., description="Created username.", example="newuser")
    name: str = Field(..., description="Display name.", example="New User")
    scholar_id: str = Field(..., description="Assigned scholar ID.", example="LUMINA_01-abc")


class AuditLogResponse(BaseModel):
    """Admin audit log response."""
    log: list = Field(default_factory=list, description="List of log line strings.")


class SettingsResponse(BaseModel):
    """Admin settings response."""
    log_retention: str = Field(..., description="Log retention policy.", example="30d")


class HubStatsResponse(BaseModel):
    """Hub statistics response (actual /stats shape)."""
    scholars: int = Field(..., description="Total registered scholars.", example=42)
    resources: int = Field(..., description="Total resources.", example=100)
    subjects: int = Field(..., description="Total subjects.", example=8)
    storage: str = Field(..., description="Storage usage string.", example="4.5 GB / 100.0 GB")
    storage_percent: float = Field(..., description="Storage usage percentage.", example=4.5)
    battery_percent: int = Field(..., description="Battery percentage.", example=85)
    uptime: str = Field(..., description="Uptime string.", example="2h 15m")
    disk_usage: str = Field(..., description="Disk usage string.", example="4.5 GB / 100.0 GB")


class StudentListResponse(BaseModel):
    """Wrapped student list response."""
    students: list = Field(default_factory=list, description="List of student summaries.")


class ZimArticleResponse(BaseModel):
    """ZIM article metadata."""
    article_id: str = Field(..., description="Article unique ID.", example="ABC123")
    title: str = Field(..., description="Article title.", example="Photosynthesis")


class ZimPageResponse(BaseModel):
    """ZIM article HTML content response."""
    id: str = Field(..., description="Article ID.", example="ABC123")
    html: str = Field(..., description="Raw HTML content of the article.", example="<html>...")



