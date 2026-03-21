from datetime import datetime

from pydantic import BaseModel, Field

from app.models import UserRole


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    role: UserRole
    identifier: str = Field(min_length=4, max_length=16)
    password: str = Field(min_length=6, max_length=128)


class LoginRequest(BaseModel):
    identifier: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: str
    full_name: str
    role: UserRole
    student_id: str | None
    teacher_id: str | None


class SessionCreateRequest(BaseModel):
    subject: str = Field(min_length=2, max_length=120)


class SessionOut(BaseModel):
    id: str
    subject: str
    token: str
    teacher_user_id: str
    starts_at: datetime
    ends_at: datetime | None
    is_active: bool


class DetectionIn(BaseModel):
    session_id: str
    rssi: int
    proximity_ok: bool = True


class AttendanceFinalizeIn(BaseModel):
    session_id: str
    biometric_verified: bool = True


class AttendanceOut(BaseModel):
    session_id: str
    student_user_id: str
    presence_ratio: float
    is_present: bool
    biometric_verified: bool


class AttendanceOverrideIn(BaseModel):
    student_user_id: str
    is_present: bool
    reason: str = Field(min_length=3, max_length=255)


class AttendanceStudentSummary(BaseModel):
    student_user_id: str
    student_id: str | None
    student_name: str
    detection_count: int
    presence_ratio: float
    is_present: bool
    biometric_verified: bool
    overridden_by_teacher: bool
    override_reason: str | None


class SessionAttendanceSummary(BaseModel):
    session_id: str
    subject: str
    starts_at: datetime
    ends_at: datetime | None
    total_students: int
    present_students: int
    records: list[AttendanceStudentSummary]
