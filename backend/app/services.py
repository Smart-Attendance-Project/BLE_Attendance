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


def upsert_attendance(
    db: Session,
    session_id: str,
    student_user_id: str,
    biometric_verified: bool,
    threshold: float = 0.6,
) -> Attendance:
    ratio = compute_presence_ratio(db, session_id, student_user_id)
    is_present = ratio >= threshold

    stmt = select(Attendance).where(
        and_(Attendance.session_id == session_id, Attendance.student_user_id == student_user_id)
    )
    row = db.scalar(stmt)

    if row is None:
        row = Attendance(
            session_id=session_id,
            student_user_id=student_user_id,
            presence_ratio=ratio,
            is_present=is_present,
            biometric_verified=biometric_verified,
            finalized_at=datetime.utcnow() if biometric_verified else None,
        )
        db.add(row)
    else:
        row.presence_ratio = ratio
        row.is_present = is_present
        row.biometric_verified = biometric_verified
        row.finalized_at = datetime.utcnow() if biometric_verified else row.finalized_at

    db.commit()
    db.refresh(row)
    return row


def build_attendance_if_missing(
    db: Session,
    session_id: str,
    student_user_id: str,
    threshold: float = 0.6,
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
        is_present=ratio >= threshold,
        biometric_verified=False,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row
