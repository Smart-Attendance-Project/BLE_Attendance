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
    threshold: float = 0.75,
) -> Attendance:
    ratio = compute_presence_ratio(db, session_id, student_user_id)

    stmt = select(Attendance).where(
        and_(Attendance.session_id == session_id, Attendance.student_user_id == student_user_id)
    )
    row = db.scalar(stmt)

<<<<<<< HEAD
    if row is None:
        # Both BLE proximity AND biometric verification are required.
        # A student is only marked present if they have sufficient
        # detection ratio AND have completed biometric verification.
        is_present = (ratio >= threshold) and biometric_verified
=======
    # is_present = True only when BOTH ratio >= threshold AND biometric verified
    is_present = ratio >= threshold and biometric_verified
>>>>>>> 1d30ac5c08195e57d7d64f783ac2bc68ea526c87

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
<<<<<<< HEAD
        # Always record biometric verification first
=======
        if ratio > 0:
            row.presence_ratio = ratio
        row.is_present = is_present
>>>>>>> 1d30ac5c08195e57d7d64f783ac2bc68ea526c87
        row.biometric_verified = biometric_verified
        row.finalized_at = datetime.utcnow() if biometric_verified else row.finalized_at
        # Update presence ratio from live detections if available
        if ratio > 0:
            row.presence_ratio = ratio
        # Both BLE proximity AND biometric are required for present.
        # If the teacher already set is_present (via override or
        # batch-submit), that will be handled by the override flag.
        row.is_present = (row.presence_ratio >= threshold) and row.biometric_verified

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
<<<<<<< HEAD
        is_present=False,  # biometric not done → always absent
=======
        is_present=False,  # no biometric → not present
>>>>>>> 1d30ac5c08195e57d7d64f783ac2bc68ea526c87
        biometric_verified=False,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row
