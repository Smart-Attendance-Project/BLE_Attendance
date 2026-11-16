from datetime import datetime

from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from app.models import Attendance, Detection, Session as LectureSession


def compute_presence_ratio(db: Session, session_id: str, student_user_id: str) -> float:
    session = db.get(LectureSession, session_id)
    if session is None:
        return 0.0

    total_windows = max(1, int((datetime.utcnow() - session.starts_at).total_seconds() // 30))
    stmt = (
        select(func.count(Detection.id))
        .where(
            and_(
                Detection.session_id == session_id,
                Detection.student_user_id == student_user_id,
                Detection.proximity_ok.is_(True),
            )
        )
    )
    valid_detections = db.scalar(stmt) or 0
    ratio = valid_detections / total_windows
    return min(1.0, round(ratio, 3))


def record_student_observation(
    db: Session, session_id: str, student_user_id: str, biometric_reported: bool,
) -> Attendance:
    ratio = compute_presence_ratio(db, session_id, student_user_id)
    row = db.scalar(select(Attendance).where(
        Attendance.session_id == session_id,
        Attendance.student_user_id == student_user_id,
    ))
    if row is None:
        row = Attendance(session_id=session_id, student_user_id=student_user_id)
        db.add(row)

    row.biometric_verified = biometric_reported
    if biometric_reported:
        row.finalized_at = datetime.utcnow()
    if not row.overridden_by_teacher:
        row.presence_ratio = max(ratio, row.presence_ratio or 0.0)

    db.commit()
    db.refresh(row)
    return row


def build_attendance_if_missing(
    db: Session,
    session_id: str,
    student_user_id: str,
    threshold: float = 0.75,
) -> Attendance:
    stmt = select(Attendance).where(
        and_(Attendance.session_id == session_id, Attendance.student_user_id == student_user_id)
    )
    row = db.scalar(stmt)
    if row is not None:
        return row

    ratio = compute_presence_ratio(db, session_id, student_user_id)
    row = Attendance(
        session_id=session_id,
        student_user_id=student_user_id,
        presence_ratio=ratio,
        is_present=False,  # biometric not done → always absent
        biometric_verified=False,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row
