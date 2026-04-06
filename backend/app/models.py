from datetime import datetime
from enum import Enum
from uuid import uuid4

from sqlalchemy import (
    Boolean, Date, DateTime, Enum as SqlEnum, Float, ForeignKey,
    Integer, String, Time, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UserRole(str, Enum):
    teacher = "teacher"
    student = "student"
    admin = "admin"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    student_id: Mapped[str | None] = mapped_column(String(16), unique=True, nullable=True)
    teacher_id: Mapped[str | None] = mapped_column(String(16), unique=True, nullable=True)
    admin_id: Mapped[str | None] = mapped_column(String(16), unique=True, nullable=True)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    role: Mapped[UserRole] = mapped_column(SqlEnum(UserRole), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    biometric_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    is_super_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Semester(Base):
    __tablename__ = "semesters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(60), nullable=False)  # e.g. "Sem II 2025-26"
    start_date: Mapped[datetime] = mapped_column(Date, nullable=False)
    end_date: Mapped[datetime] = mapped_column(Date, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)


class Subject(Base):
    __tablename__ = "subjects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(20), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    subject_type: Mapped[str] = mapped_column(String(10), nullable=False, default="lecture")  # lecture | lab


class Branch(Base):
    __tablename__ = "branches"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(10), unique=True, nullable=False)  # CE, CS, IT ...
    name: Mapped[str] = mapped_column(String(60), nullable=False)


class Division(Base):
    __tablename__ = "divisions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    branch_id: Mapped[int] = mapped_column(Integer, ForeignKey("branches.id"), nullable=False)
    year: Mapped[int] = mapped_column(Integer, nullable=False)  # 1,2,3,4
    div_number: Mapped[int] = mapped_column(Integer, nullable=False)  # 1,2
    label: Mapped[str] = mapped_column(String(20), nullable=False)  # e.g. "CE-FY-Div1"

    branch: Mapped["Branch"] = relationship()
    batches: Mapped[list["Batch"]] = relationship(back_populates="division")

    __table_args__ = (UniqueConstraint("branch_id", "year", "div_number"),)


class Batch(Base):
    __tablename__ = "batches"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    division_id: Mapped[int] = mapped_column(Integer, ForeignKey("divisions.id"), nullable=False)
    label: Mapped[str] = mapped_column(String(10), nullable=False)  # A1, B1, C1 ...

    division: Mapped["Division"] = relationship(back_populates="batches")

    __table_args__ = (UniqueConstraint("division_id", "label"),)


class TeacherAssignment(Base):
    """Links a teacher to a subject+division (and optionally a batch for labs)."""
    __tablename__ = "teacher_assignments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    teacher_user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    subject_id: Mapped[int] = mapped_column(Integer, ForeignKey("subjects.id"), nullable=False)
    division_id: Mapped[int] = mapped_column(Integer, ForeignKey("divisions.id"), nullable=False)
    batch_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("batches.id"), nullable=True)

    teacher: Mapped["User"] = relationship()
    subject: Mapped["Subject"] = relationship()
    division: Mapped["Division"] = relationship()
    batch: Mapped["Batch | None"] = relationship()

    __table_args__ = (UniqueConstraint("teacher_user_id", "subject_id", "division_id", "batch_id"),)


class ScheduleSlot(Base):
    __tablename__ = "schedule_slots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    assignment_id: Mapped[int] = mapped_column(Integer, ForeignKey("teacher_assignments.id"), nullable=False)
    semester_id: Mapped[int] = mapped_column(Integer, ForeignKey("semesters.id"), nullable=False)
    day_of_week: Mapped[int] = mapped_column(Integer, nullable=False)  # 0=Mon ... 5=Sat
    time_start: Mapped[str] = mapped_column(String(5), nullable=False)  # "09:10"
    time_end: Mapped[str] = mapped_column(String(5), nullable=False)    # "10:10"
    room: Mapped[str | None] = mapped_column(String(30), nullable=True)

    assignment: Mapped["TeacherAssignment"] = relationship()
    semester: Mapped["Semester"] = relationship()


class DivisionStudent(Base):
    """Enrolment: which division (and optionally batch) a student belongs to."""
    __tablename__ = "division_students"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    student_user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    division_id: Mapped[int] = mapped_column(Integer, ForeignKey("divisions.id"), nullable=False)
    batch_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("batches.id"), nullable=True)

    __table_args__ = (UniqueConstraint("student_user_id", "division_id"),)


# ── original models (kept, Session enriched) ──────────────────────────────────

class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    subject: Mapped[str] = mapped_column(String(120), nullable=False)
    teacher_user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    assignment_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("teacher_assignments.id"), nullable=True)
    token: Mapped[str] = mapped_column(String(64), nullable=False)
    starts_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    finalization_open: Mapped[bool] = mapped_column(Boolean, default=False)
    attendance_locked: Mapped[bool] = mapped_column(Boolean, default=False)

    detections: Mapped[list["Detection"]] = relationship(back_populates="session")
    assignment: Mapped["TeacherAssignment | None"] = relationship()


class Detection(Base):
    __tablename__ = "detections"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[str] = mapped_column(String(36), ForeignKey("sessions.id"), nullable=False)
    student_user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    rssi: Mapped[int] = mapped_column(Integer, nullable=False)
    proximity_ok: Mapped[bool] = mapped_column(Boolean, default=True)
    detected_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    session: Mapped[Session] = relationship(back_populates="detections")


class Attendance(Base):
    __tablename__ = "attendance"
    __table_args__ = (UniqueConstraint("session_id", "student_user_id", name="uq_attendance_session_student"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[str] = mapped_column(String(36), ForeignKey("sessions.id"), nullable=False)
    student_user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    presence_ratio: Mapped[float] = mapped_column(Float, default=0.0)
    is_present: Mapped[bool] = mapped_column(Boolean, default=False)
    biometric_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    overridden_by_teacher: Mapped[bool] = mapped_column(Boolean, default=False)
    override_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
