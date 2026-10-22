import io
from datetime import datetime, date, timedelta
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.models import (
    Base, User, UserRole, Semester, Subject, Branch, Division, Batch,
    TeacherAssignment, ScheduleSlot, DivisionStudent, Session as LectureSession,
    Detection, Attendance,
)
from app.main import (
    _build_summary, batch_submit_attendance, teacher_today_schedule,
    teacher_today_slots_mobile, export_attendance_range, list_slots,
    list_assignments, list_divisions, _now_ist,
)


def setup_db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    return Session()


def test_optimizations():
    db = setup_db()

    # 1. Create Teacher and Admin
    teacher = User(
        id="teacher-uuid",
        full_name="Prof. Ramanujan",
        role=UserRole.teacher,
        teacher_id="T001",
        password_hash="fakehash",
    )
    admin = User(
        id="admin-uuid",
        full_name="Admin User",
        role=UserRole.admin,
        admin_id="A001",
        password_hash="fakehash",
    )
    db.add_all([teacher, admin])
    db.flush()

    # 2. Academic structure
    branch = Branch(code="CE", name="Computer Engineering")
    db.add(branch)
    db.flush()

    div = Division(
        branch_id=branch.id,
        year=2,
        div_number=1,
        label="CE-SY-Div1",
        start_student_id="25CE001",
        end_student_id="25CE070",
    )
    db.add(div)
    db.flush()

    batch = Batch(division_id=div.id, label="A1")
    db.add(batch)
    db.flush()

    subj = Subject(code="CS201", name="Data Structures", subject_type="lecture")
    db.add(subj)
    db.flush()

    assignment = TeacherAssignment(
        teacher_user_id=teacher.id,
        subject_id=subj.id,
        division_id=div.id,
        batch_id=batch.id,
    )
    db.add(assignment)
    db.flush()

    today_dow = _now_ist().weekday()
    sem = Semester(
        name="Sem IV 2026",
        start_date=date.today() - timedelta(days=30),
        end_date=date.today() + timedelta(days=60),
        is_active=True,
    )
    db.add(sem)
    db.flush()

    slot = ScheduleSlot(
        assignment_id=assignment.id,
        semester_id=sem.id,
        day_of_week=today_dow,
        time_start="10:00",
        time_end="11:00",
        room="Room 301",
    )
    db.add(slot)
    db.flush()

    # 3. Create Students and enrollment
    students = []
    for i in range(1, 11):
        sid = f"25CE{i:03d}"
        s = User(
            id=f"student-{i}",
            student_id=sid,
            full_name=f"Student {i}",
            role=UserRole.student,
            password_hash="fakehash",
        )
        students.append(s)
        db.add(s)
        db.flush()
        db.add(DivisionStudent(student_user_id=s.id, division_id=div.id, batch_id=batch.id))
    db.flush()

    # 4. Session
    sess = LectureSession(
        id="session-uuid-1",
        subject="Data Structures",
        teacher_user_id=teacher.id,
        assignment_id=assignment.id,
        token="token123",
        starts_at=datetime.utcnow() - timedelta(minutes=45),
        ends_at=datetime.utcnow(),
        is_active=False,
    )
    db.add(sess)
    db.flush()

    # Add detections for student 1 & 2
    db.add(Detection(session_id=sess.id, student_user_id="student-1", rssi=-60, proximity_ok=True))
    db.add(Detection(session_id=sess.id, student_user_id="student-1", rssi=-65, proximity_ok=True))
    db.add(Detection(session_id=sess.id, student_user_id="student-2", rssi=-95, proximity_ok=False))
    db.flush()

    # Add attendance for student 1 (e.g. from teacher submit or manual override)
    db.add(Attendance(session_id=sess.id, student_user_id="student-1", presence_ratio=0.8, is_present=True, biometric_verified=True, overridden_by_teacher=True))
    db.commit()

    print("--- Testing _build_summary ---")
    summary = _build_summary(db, sess)
    assert summary.total_students == 10
    assert summary.present_students == 1
    rec1 = next(r for r in summary.records if r.student_id == "25CE001")
    assert rec1.is_present is True
    assert rec1.detection_count == 2
    rec2 = next(r for r in summary.records if r.student_id == "25CE002")
    assert rec2.is_present is False
    assert rec2.detection_count == 1
    print("✓ _build_summary passed!")

    print("--- Testing batch_submit_attendance ---")
    sess_active = LectureSession(
        id="session-uuid-2",
        subject="Data Structures Active",
        teacher_user_id=teacher.id,
        assignment_id=assignment.id,
        token="token456",
        starts_at=datetime.utcnow(),
        is_active=True,
    )
    db.add(sess_active)
    db.commit()

    payload = [
        {"student_id": "25CE001", "is_present": True},
        {"student_id": "25CE002", "is_present": True},
        {"student_id": "25CE003", "is_present": False},
    ]
    res = batch_submit_attendance(sess_active.id, payload, db=db, teacher=teacher)
    assert "attendance records saved" in res["message"]
    # Verify records created in DB
    att1 = db.query(Attendance).filter_by(session_id=sess_active.id, student_user_id="student-1").first()
    assert att1 is not None and att1.is_present is True
    att3 = db.query(Attendance).filter_by(session_id=sess_active.id, student_user_id="student-3").first()
    assert att3 is not None and att3.is_present is False
    print("✓ batch_submit_attendance passed!")

    print("--- Testing teacher_today_schedule ---")
    today_slots = teacher_today_schedule(db=db, teacher=teacher)
    assert len(today_slots) == 1
    assert today_slots[0].subject_code == "CS201"
    print("✓ teacher_today_schedule passed!")

    print("--- Testing teacher_today_slots_mobile ---")
    mob_slots = teacher_today_slots_mobile(db=db, teacher=teacher)
    assert len(mob_slots) == 1
    assert mob_slots[0]["subject_code"] == "CS201"
    print("✓ teacher_today_slots_mobile passed!")

    print("--- Testing export_attendance_range ---")
    from_date = (date.today() - timedelta(days=2)).isoformat()
    to_date = date.today().isoformat()
    export_resp = export_attendance_range(
        assignment_id=assignment.id,
        from_date=from_date,
        to_date=to_date,
        db=db,
        teacher=teacher,
    )
    assert export_resp.status_code == 200
    print("✓ export_attendance_range passed!")

    print("--- Testing list_divisions, list_assignments, list_slots ---")
    divs = list_divisions(db=db, _=admin)
    assert len(divs) == 1
    assert divs[0].branch_code == "CE"

    assigns = list_assignments(db=db, _=admin)
    assert len(assigns) == 1
    assert assigns[0].subject_code == "CS201"

    slots = list_slots(semester_id=sem.id, db=db, _=admin)
    assert len(slots) == 1
    assert slots[0].room == "Room 301"
    print("✓ list_divisions, list_assignments, and list_slots passed!")

    print("\nALL OPTIMIZATION TESTS PASSED SUCCESSFULLY! 🚀")


if __name__ == "__main__":
    test_optimizations()
