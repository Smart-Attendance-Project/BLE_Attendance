import secrets
from datetime import datetime
import re

from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy import and_, desc, func, or_, select
from sqlalchemy.orm import Session

from app.auth import authenticate_user, create_access_token, get_current_user, hash_password, require_role
from app.database import Base, engine, get_db
from app.models import Attendance, Detection, Session as LectureSession, User, UserRole
from app.schemas import (
    AttendanceOverrideIn,
    AttendanceStudentSummary,
    SessionAttendanceSummary,
    AttendanceFinalizeIn,
    AttendanceOut,
    DetectionIn,
    LoginRequest,
    RegisterRequest,
    SessionCreateRequest,
    SessionOut,
    TokenResponse,
    UserOut,
)
from app.services import compute_presence_ratio, upsert_attendance

app = FastAPI(title="BLE Attendance Prototype API")

STUDENT_ID_PATTERN = re.compile(r"^(?:\d{2}[A-Z]{2,3}\d{3}|D\d{2}[A-Z]{2,3}\d{3})$")


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/auth/register", response_model=UserOut)
def register_user(payload: RegisterRequest, db: Session = Depends(get_db)) -> UserOut:
    if payload.role == UserRole.student:
        if not STUDENT_ID_PATTERN.match(payload.identifier):
            raise HTTPException(
                status_code=422,
                detail="Student ID must match formats like 25CE099 or D26CE045",
            )
        existing = db.scalar(select(User).where(User.student_id == payload.identifier))
        if existing:
            raise HTTPException(status_code=409, detail="Student ID already exists")
        user = User(
            full_name=payload.full_name,
            role=payload.role,
            student_id=payload.identifier,
            password_hash=hash_password(payload.password),
        )
    else:
        existing = db.scalar(select(User).where(User.teacher_id == payload.identifier))
        if existing:
            raise HTTPException(status_code=409, detail="Teacher ID already exists")
        user = User(
            full_name=payload.full_name,
            role=payload.role,
            teacher_id=payload.identifier,
            password_hash=hash_password(payload.password),
        )

    db.add(user)
    db.commit()
    db.refresh(user)

    return UserOut(
        id=user.id,
        full_name=user.full_name,
        role=user.role,
        student_id=user.student_id,
        teacher_id=user.teacher_id,
    )


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = authenticate_user(db, payload.identifier, payload.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = create_access_token(subject=user.id)
    return TokenResponse(access_token=token)


@app.post("/sessions", response_model=SessionOut)
def start_session(
    payload: SessionCreateRequest,
    db: Session = Depends(get_db),
    teacher: User = Depends(require_role(UserRole.teacher)),
) -> SessionOut:
    active = db.scalar(
        select(LectureSession).where(
            and_(LectureSession.teacher_user_id == teacher.id, LectureSession.is_active.is_(True))
        )
    )
    if active:
        raise HTTPException(status_code=409, detail="A session is already active")

    session = LectureSession(
        subject=payload.subject,
        teacher_user_id=teacher.id,
        token=secrets.token_hex(8),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return SessionOut(
        id=session.id,
        subject=session.subject,
        token=session.token,
        teacher_user_id=session.teacher_user_id,
        starts_at=session.starts_at,
        ends_at=session.ends_at,
        is_active=session.is_active,
    )


@app.post("/sessions/{session_id}/end", response_model=SessionOut)
def end_session(
    session_id: str,
    db: Session = Depends(get_db),
    teacher: User = Depends(require_role(UserRole.teacher)),
) -> SessionOut:
    session = db.get(LectureSession, session_id)
    if session is None or session.teacher_user_id != teacher.id:
        raise HTTPException(status_code=404, detail="Session not found")
    session.is_active = False
    session.ends_at = datetime.utcnow()
    db.commit()
    db.refresh(session)
    return SessionOut(
        id=session.id,
        subject=session.subject,
        token=session.token,
        teacher_user_id=session.teacher_user_id,
        starts_at=session.starts_at,
        ends_at=session.ends_at,
        is_active=session.is_active,
    )


@app.get("/sessions/active", response_model=SessionOut)
def get_active_session(db: Session = Depends(get_db), _: User = Depends(get_current_user)) -> SessionOut:
    session = db.scalar(select(LectureSession).where(LectureSession.is_active.is_(True)).order_by(desc(LectureSession.starts_at)))
    if session is None:
        raise HTTPException(status_code=404, detail="No active session")
    return SessionOut(
        id=session.id,
        subject=session.subject,
        token=session.token,
        teacher_user_id=session.teacher_user_id,
        starts_at=session.starts_at,
        ends_at=session.ends_at,
        is_active=session.is_active,
    )


@app.post("/detections")
def submit_detection(
    payload: DetectionIn,
    db: Session = Depends(get_db),
    student: User = Depends(require_role(UserRole.student)),
) -> dict[str, str]:
    session = db.get(LectureSession, payload.session_id)
    if session is None or not session.is_active:
        raise HTTPException(status_code=404, detail="Active session not found")

    detection = Detection(
        session_id=payload.session_id,
        student_user_id=student.id,
        rssi=payload.rssi,
        proximity_ok=payload.proximity_ok,
    )
    db.add(detection)
    db.commit()
    return {"message": "Detection recorded"}


@app.post("/attendance/finalize", response_model=AttendanceOut)
def finalize_attendance(
    payload: AttendanceFinalizeIn,
    db: Session = Depends(get_db),
    student: User = Depends(require_role(UserRole.student)),
) -> AttendanceOut:
    session = db.get(LectureSession, payload.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")

    attendance = upsert_attendance(
        db=db,
        session_id=payload.session_id,
        student_user_id=student.id,
        biometric_verified=payload.biometric_verified,
    )
    return AttendanceOut(
        session_id=attendance.session_id,
        student_user_id=attendance.student_user_id,
        presence_ratio=attendance.presence_ratio,
        is_present=attendance.is_present,
        biometric_verified=attendance.biometric_verified,
    )


@app.get("/teacher/sessions/{session_id}/attendance-summary", response_model=SessionAttendanceSummary)
def get_attendance_summary(
    session_id: str,
    db: Session = Depends(get_db),
    teacher: User = Depends(require_role(UserRole.teacher)),
) -> SessionAttendanceSummary:
    session = db.get(LectureSession, session_id)
    if session is None or session.teacher_user_id != teacher.id:
        raise HTTPException(status_code=404, detail="Session not found")

    rows = db.execute(
        select(User, Attendance, func.count(Detection.id).label("detection_count"))
        .select_from(User)
        .outerjoin(Detection, and_(Detection.student_user_id == User.id, Detection.session_id == session_id))
        .outerjoin(
            Attendance,
            and_(Attendance.student_user_id == User.id, Attendance.session_id == session_id),
        )
        .where(User.role == UserRole.student)
        .having(or_(func.count(Detection.id) > 0, Attendance.id.is_not(None)))
        .group_by(User.id, Attendance.id)
        .order_by(User.student_id)
    ).all()

    records: list[AttendanceStudentSummary] = []
    present_students = 0
    for user, attendance, detection_count in rows:
        if attendance is None:
            presence_ratio = compute_presence_ratio(db, session_id, user.id)
            is_present = presence_ratio >= 0.6
            biometric_verified = False
            overridden_by_teacher = False
            override_reason = None
        else:
            presence_ratio = attendance.presence_ratio
            is_present = attendance.is_present
            biometric_verified = attendance.biometric_verified
            overridden_by_teacher = attendance.overridden_by_teacher
            override_reason = attendance.override_reason

        if is_present:
            present_students += 1

        records.append(
            AttendanceStudentSummary(
                student_user_id=user.id,
                student_id=user.student_id,
                student_name=user.full_name,
                detection_count=detection_count,
                presence_ratio=presence_ratio,
                is_present=is_present,
                biometric_verified=biometric_verified,
                overridden_by_teacher=overridden_by_teacher,
                override_reason=override_reason,
            )
        )

    return SessionAttendanceSummary(
        session_id=session.id,
        subject=session.subject,
        starts_at=session.starts_at,
        ends_at=session.ends_at,
        total_students=len(records),
        present_students=present_students,
        records=records,
    )


@app.post("/teacher/sessions/{session_id}/attendance/override", response_model=AttendanceOut)
def override_attendance(
    session_id: str,
    payload: AttendanceOverrideIn,
    db: Session = Depends(get_db),
    teacher: User = Depends(require_role(UserRole.teacher)),
) -> AttendanceOut:
    session = db.get(LectureSession, session_id)
    if session is None or session.teacher_user_id != teacher.id:
        raise HTTPException(status_code=404, detail="Session not found")

    student = db.get(User, payload.student_user_id)
    if student is None or student.role != UserRole.student:
        raise HTTPException(status_code=404, detail="Student not found")

    attendance = db.scalar(
        select(Attendance).where(
            and_(Attendance.session_id == session_id, Attendance.student_user_id == payload.student_user_id)
        )
    )
    if attendance is None:
        attendance = Attendance(
            session_id=session_id,
            student_user_id=payload.student_user_id,
            presence_ratio=0.0,
            biometric_verified=False,
        )
        db.add(attendance)

    attendance.is_present = payload.is_present
    attendance.overridden_by_teacher = True
    attendance.override_reason = payload.reason
    db.commit()
    db.refresh(attendance)

    return AttendanceOut(
        session_id=attendance.session_id,
        student_user_id=attendance.student_user_id,
        presence_ratio=attendance.presence_ratio,
        is_present=attendance.is_present,
        biometric_verified=attendance.biometric_verified,
    )


@app.get("/teacher/sessions/{session_id}/detections")
def get_session_detections(
    session_id: str,
    db: Session = Depends(get_db),
    teacher: User = Depends(require_role(UserRole.teacher)),
) -> list[dict]:
    session = db.get(LectureSession, session_id)
    if session is None or session.teacher_user_id != teacher.id:
        raise HTTPException(status_code=404, detail="Session not found")

    rows = db.execute(
        select(Detection, User)
        .join(User, Detection.student_user_id == User.id)
        .where(Detection.session_id == session_id)
        .order_by(desc(Detection.detected_at))
    ).all()

    output = []
    for detection, user in rows:
        output.append(
            {
                "student_id": user.student_id,
                "student_name": user.full_name,
                "rssi": detection.rssi,
                "proximity_ok": detection.proximity_ok,
                "detected_at": detection.detected_at.isoformat(),
            }
        )
    return output
