from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from app.main import (
    _build_summary,
    _session_out,
    _student_is_in_session,
    batch_submit_attendance,
    get_active_session,
    login,
    submit_detection_batch,
    teacher_today_schedule,
)
from app.models import Attendance, Detection, ScheduleSlot, Session as LectureSession
from app.schemas import BatchDetectionIn, LoginRequest
from app.services import upsert_attendance
from tests.conftest import make_session


def test_student_is_allowed_in_division_scoped_lecture(world, db):
    session = make_session(db, world["lecture_assignment"])

    assert _student_is_in_session(db, world["in_range"].id, session)
    assert not _student_is_in_session(db, world["other_division_student"].id, session)
    # Range boundaries are enforced by the BLE batch endpoint; enrollment
    # itself remains division-scoped so attendance summaries include the full
    # class roster.
    assert _student_is_in_session(db, world["out_of_range"].id, session)


def test_batch_assignment_requires_matching_batch(world, db):
    session = make_session(db, world["batch_assignment"])

    assert _student_is_in_session(db, world["batch_a_student"].id, session)
    assert not _student_is_in_session(db, world["batch_b_student"].id, session)
    assert not _student_is_in_session(db, world["in_range"].id, session)


def test_student_cannot_discover_session_from_another_division(world, db):
    session = make_session(db, world["other_division_assignment"])

    assert get_active_session(db=db, current_user=world["other_division_student"]).id == session.id
    with pytest.raises(HTTPException) as exc:
        get_active_session(db=db, current_user=world["in_range"])
    assert exc.value.status_code == 404


def test_batch_student_only_discovers_matching_batch_session(world, db):
    session = make_session(db, world["batch_assignment"])

    assert get_active_session(db=db, current_user=world["batch_a_student"]).id == session.id
    with pytest.raises(HTTPException) as exc:
        get_active_session(db=db, current_user=world["batch_b_student"])
    assert exc.value.status_code == 404


def test_teacher_only_discovers_own_active_session(world, db):
    make_session(db, world["other_teacher_assignment"], session_id="other-session")

    with pytest.raises(HTTPException) as exc:
        get_active_session(db=db, current_user=world["teacher"])
    assert exc.value.status_code == 404
    assert get_active_session(
        db=db, current_user=world["other_teacher"]
    ).id == "other-session"


def test_detection_batch_enforces_student_range_and_class_scope(world, db):
    session = make_session(db, world["lecture_assignment"])
    payload = BatchDetectionIn(
        detections=[
            {
                "session_id": session.id,
                "student_identifier": "25CE010",
                "rssi": -55,
            },
            {
                "session_id": session.id,
                "student_identifier": "25CE009",
                "rssi": -55,
            },
            {
                "session_id": session.id,
                "student_identifier": "25IT001",
                "rssi": -55,
            },
            {
                "session_id": session.id,
                "student_identifier": "25CE999",
                "rssi": -55,
            },
        ]
    )

    result = submit_detection_batch(payload, db=db, teacher=world["teacher"])

    assert result == {"message": "1 detections recorded"}
    detections = db.query(Detection).filter_by(session_id=session.id).all()
    assert [d.student_user_id for d in detections] == [world["in_range"].id]


def test_detection_batch_rejects_inactive_and_foreign_teacher_sessions(world, db):
    inactive = make_session(db, world["lecture_assignment"], active=False)
    foreign = make_session(db, world["other_teacher_assignment"], session_id="foreign")
    payload = BatchDetectionIn(
        detections=[
            {"session_id": inactive.id, "student_identifier": "25CE010", "rssi": -50},
            {"session_id": foreign.id, "student_identifier": "25CE010", "rssi": -50},
        ]
    )

    result = submit_detection_batch(payload, db=db, teacher=world["teacher"])

    assert result == {"message": "0 detections recorded"}
    assert db.query(Detection).count() == 0


def test_batch_submit_is_scoped_to_enrolled_batch_and_is_idempotent(world, db):
    session = make_session(db, world["batch_assignment"])
    payload = [
        {"student_id": "25CE011", "is_present": True},
        {"student_id": "25CE012", "is_present": True},
        {"student_id": "25CE010", "is_present": True},
        {"student_id": "unknown", "is_present": True},
    ]

    result = batch_submit_attendance(session.id, payload, db=db, teacher=world["teacher"])
    assert result == {"message": "1 attendance records saved"}
    records = db.query(Attendance).filter_by(session_id=session.id).all()
    assert len(records) == 1
    assert records[0].student_user_id == world["batch_a_student"].id

    result = batch_submit_attendance(
        session.id,
        [{"student_id": "25CE011", "is_present": False}],
        db=db,
        teacher=world["teacher"],
    )
    assert result == {"message": "1 attendance records saved"}
    records = db.query(Attendance).filter_by(session_id=session.id).all()
    assert len(records) == 1
    assert records[0].is_present is False


def test_batch_submit_empty_payload_is_safe(world, db):
    session = make_session(db, world["lecture_assignment"])

    assert batch_submit_attendance(session.id, [], db=db, teacher=world["teacher"]) == {
        "message": "0 attendance records saved"
    }
    assert db.query(Attendance).count() == 0


def test_batch_submit_rejects_locked_attendance(world, db):
    session = make_session(db, world["lecture_assignment"])
    session.attendance_locked = True
    db.commit()

    with pytest.raises(HTTPException) as exc:
        batch_submit_attendance(
            session.id,
            [{"student_id": "25CE010", "is_present": True}],
            db=db,
            teacher=world["teacher"],
        )
    assert exc.value.status_code == 409


def test_summary_contains_all_students_but_only_assignment_batch(world, db):
    session = make_session(db, world["batch_assignment"], minutes_old=1)
    db.add(Detection(
        session_id=session.id,
        student_user_id=world["batch_a_student"].id,
        rssi=-45,
        proximity_ok=True,
    ))
    db.add(Detection(
        session_id=session.id,
        student_user_id=world["batch_b_student"].id,
        rssi=-45,
        proximity_ok=True,
    ))
    db.commit()

    summary = _build_summary(db, session)

    assert summary.total_students == 1
    assert [record.student_id for record in summary.records] == ["25CE011"]
    assert summary.records[0].detection_count == 1


def test_summary_marks_missing_attendance_as_absent(world, db):
    session = make_session(db, world["lecture_assignment"])

    summary = _build_summary(db, session)

    assert summary.total_students == 4
    assert summary.present_students == 0
    assert all(record.is_present is False for record in summary.records)
    assert all(record.biometric_verified is False for record in summary.records)


def test_summary_counts_only_proximity_valid_detections(world, db):
    session = make_session(db, world["lecture_assignment"], minutes_old=5)
    for _ in range(8):
        db.add(Detection(
            session_id=session.id,
            student_user_id=world["in_range"].id,
            rssi=-45,
            proximity_ok=True,
        ))
    for _ in range(2):
        db.add(Detection(
            session_id=session.id,
            student_user_id=world["in_range"].id,
            rssi=-100,
            proximity_ok=False,
        ))
    db.add(Attendance(
        session_id=session.id,
        student_user_id=world["in_range"].id,
        biometric_verified=True,
        is_present=True,
    ))
    db.commit()

    summary = _build_summary(db, session)
    record = next(record for record in summary.records if record.student_id == "25CE010")

    assert record.detection_count == 10
    assert record.presence_ratio == 0.8
    assert record.is_present is True


def test_attendance_requires_biometric_verification(world, db):
    session = make_session(db, world["lecture_assignment"], minutes_old=5)
    for _ in range(8):
        db.add(Detection(
            session_id=session.id,
            student_user_id=world["in_range"].id,
            rssi=-45,
            proximity_ok=True,
        ))
    db.commit()

    attendance = upsert_attendance(
        db, session.id, world["in_range"].id, biometric_verified=False
    )
    assert attendance.presence_ratio == 0.8
    assert attendance.is_present is False

    attendance = upsert_attendance(
        db, session.id, world["in_range"].id, biometric_verified=True
    )
    assert attendance.is_present is True
    assert attendance.finalized_at is not None


def test_teacher_override_is_preserved_in_summary(world, db):
    session = make_session(db, world["lecture_assignment"])
    db.add(Attendance(
        session_id=session.id,
        student_user_id=world["in_range"].id,
        presence_ratio=0.0,
        is_present=True,
        biometric_verified=False,
        overridden_by_teacher=True,
        override_reason="Present in classroom",
    ))
    db.commit()

    summary = _build_summary(db, session)
    record = next(record for record in summary.records if record.student_id == "25CE010")

    assert record.is_present is True
    assert record.overridden_by_teacher is True
    assert record.override_reason == "Present in classroom"


def test_session_output_contains_assignment_scope_metadata(world, db):
    session = make_session(db, world["lecture_assignment"])

    output = _session_out(session)

    assert output.subject_code == "CS201"
    assert output.division_id == world["ce"].id
    assert output.batch_id is None
    assert output.start_student_id == "25CE010"
    assert output.end_student_id == "25CE040"


def test_teacher_schedule_is_filtered_and_ordered(world, db):
    today = datetime.now().weekday()
    db.add_all([
        ScheduleSlot(
            assignment_id=world["lecture_assignment"].id,
            semester_id=world["semester"].id,
            day_of_week=today,
            time_start="11:00",
            time_end="12:00",
            room="B",
        ),
        ScheduleSlot(
            assignment_id=world["batch_assignment"].id,
            semester_id=world["semester"].id,
            day_of_week=today,
            time_start="09:00",
            time_end="10:00",
            room="A",
        ),
        ScheduleSlot(
            assignment_id=world["other_teacher_assignment"].id,
            semester_id=world["semester"].id,
            day_of_week=(today + 1) % 7,
            time_start="08:00",
            time_end="09:00",
            room="C",
        ),
    ])
    db.commit()

    slots = teacher_today_schedule(db=db, teacher=world["teacher"])

    assert [(slot.time_start, slot.room) for slot in slots] == [
        ("09:00", "A"),
        ("11:00", "B"),
    ]


def test_login_returns_sorted_division_ids_and_enrollment_scope(world, db):
    response = login(
        LoginRequest(identifier="25CE010", password="Pass@123"),
        db=db,
    )

    assert response.role.value == "student"
    assert response.division_ids == [world["ce"].id]
    assert len(response.enrollments) == 1
    assert response.enrollments[0].division_id == world["ce"].id
    assert response.enrollments[0].batch_id is None
    assert response.access_token


def test_login_rejects_bad_password(world, db):
    with pytest.raises(HTTPException) as exc:
        login(LoginRequest(identifier="25CE010", password="wrong"), db=db)
    assert exc.value.status_code == 401


def test_active_session_lookup_returns_latest_matching_session(world, db):
    older = make_session(
        db,
        world["lecture_assignment"],
        session_id="older",
        minutes_old=20,
    )
    newer = make_session(
        db,
        world["lecture_assignment"],
        session_id="newer",
        minutes_old=2,
    )

    found = get_active_session(db=db, current_user=world["in_range"])

    assert older.id != newer.id
    assert found.id == newer.id
