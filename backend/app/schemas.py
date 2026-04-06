from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.models import UserRole


# ── Auth ──────────────────────────────────────────────────────────────────────

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
    role: UserRole
    full_name: str
    user_id: str


class UserOut(BaseModel):
    id: str
    full_name: str
    role: UserRole
    student_id: Optional[str] = None
    teacher_id: Optional[str] = None
    admin_id: Optional[str] = None
    is_super_admin: bool = False


# ── Session (BLE) ─────────────────────────────────────────────────────────────

class SessionCreateRequest(BaseModel):
    subject: str = Field(min_length=2, max_length=120)
    assignment_id: Optional[int] = None


class SessionOut(BaseModel):
    id: str
    subject: str
    token: str
    teacher_user_id: str
    assignment_id: Optional[int] = None
    starts_at: datetime
    ends_at: Optional[datetime] = None
    is_active: bool
    finalization_open: bool
    attendance_locked: bool = False


# ── Detection ─────────────────────────────────────────────────────────────────

class DetectionIn(BaseModel):
    session_id: str
    rssi: int
    proximity_ok: bool = True


class BatchDetectionItem(BaseModel):
    session_id: str
    student_identifier: str
    rssi: int
    proximity_ok: bool = True


class BatchDetectionIn(BaseModel):
    detections: list[BatchDetectionItem]


# ── Attendance ────────────────────────────────────────────────────────────────

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
    student_id: Optional[str] = None
    student_name: str
    detection_count: int
    presence_ratio: float
    is_present: bool
    biometric_verified: bool
    overridden_by_teacher: bool
    override_reason: Optional[str] = None


class SessionAttendanceSummary(BaseModel):
    session_id: str
    subject: str
    starts_at: datetime
    ends_at: Optional[datetime] = None
    total_students: int
    present_students: int
    records: list[AttendanceStudentSummary]


# ── Admin: Semester ───────────────────────────────────────────────────────────

class SemesterIn(BaseModel):
    name: str
    start_date: str  # YYYY-MM-DD
    end_date: str
    is_active: bool = False


class SemesterOut(BaseModel):
    id: int
    name: str
    start_date: str
    end_date: str
    is_active: bool


# ── Admin: Branch / Division / Batch ─────────────────────────────────────────

class BranchIn(BaseModel):
    code: str
    name: str


class BranchOut(BaseModel):
    id: int
    code: str
    name: str


class DivisionIn(BaseModel):
    branch_id: int
    year: int
    div_number: int
    label: str


class DivisionOut(BaseModel):
    id: int
    branch_id: int
    year: int
    div_number: int
    label: str
    branch_code: str = ""


class BatchIn(BaseModel):
    division_id: int
    label: str


class BatchOut(BaseModel):
    id: int
    division_id: int
    label: str


# ── Admin: Subject ────────────────────────────────────────────────────────────

class SubjectIn(BaseModel):
    code: str
    name: str
    subject_type: str = "lecture"


class SubjectOut(BaseModel):
    id: int
    code: str
    name: str
    subject_type: str


# ── Admin: TeacherAssignment ──────────────────────────────────────────────────

class AssignmentIn(BaseModel):
    teacher_user_id: str
    subject_id: int
    division_id: int
    batch_id: Optional[int] = None


class AssignmentOut(BaseModel):
    id: int
    teacher_user_id: str
    teacher_name: str
    subject_id: int
    subject_name: str
    subject_code: str
    division_id: int
    division_label: str
    batch_id: Optional[int] = None
    batch_label: Optional[str] = None


# ── Admin: ScheduleSlot ───────────────────────────────────────────────────────

class ScheduleSlotIn(BaseModel):
    assignment_id: int
    semester_id: int
    day_of_week: int  # 0=Mon..5=Sat
    time_start: str
    time_end: str
    room: Optional[str] = None


class ScheduleSlotOut(BaseModel):
    id: int
    assignment_id: int
    semester_id: int
    day_of_week: int
    time_start: str
    time_end: str
    room: Optional[str] = None
    subject_name: str = ""
    subject_code: str = ""
    division_label: str = ""
    batch_label: Optional[str] = None
    teacher_name: str = ""


# ── Admin: create teacher/admin ───────────────────────────────────────────────

class CreateTeacherIn(BaseModel):
    full_name: str
    teacher_id: str
    password: str = Field(min_length=6)


class CreateAdminIn(BaseModel):
    full_name: str
    admin_id: str
    password: str = Field(min_length=6)
    is_super_admin: bool = False


# ── Student management ────────────────────────────────────────────────────────

class CreateStudentIn(BaseModel):
    full_name: str
    student_id: str
    password: str = Field(default="Pass@123", min_length=6)
    division_id: Optional[int] = None
    batch_id: Optional[int] = None


class DivisionStudentIn(BaseModel):
    student_user_id: str
    division_id: int
    batch_id: Optional[int] = None


# ── Attendance export range ───────────────────────────────────────────────────

class AttendanceRangeQuery(BaseModel):
    assignment_id: int
    from_date: str  # YYYY-MM-DD
    to_date: str
