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



