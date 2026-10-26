from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.auth import hash_password
from app.database import Base
from app.models import (
    Batch,
    Branch,
    Division,
    DivisionStudent,
    Semester,
    Subject,
    TeacherAssignment,
    User,
    UserRole,
)


@pytest.fixture
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def world(db: Session):
    """Create two divisions and lecture/lab assignments for regression tests."""
    branch_ce = Branch(code="CE", name="Computer Engineering")
    branch_it = Branch(code="IT", name="Information Technology")
    db.add_all([branch_ce, branch_it])
    db.flush()

    division_ce = Division(
        branch_id=branch_ce.id,
        year=2,
        div_number=1,
        label="CE-SY-Div1",
        start_student_id="25CE010",
        end_student_id="25CE040",
    )
    division_it = Division(
        branch_id=branch_it.id,
        year=2,
        div_number=1,
        label="IT-SY-Div1",
        start_student_id="25IT001",
        end_student_id="25IT040",
    )
    db.add_all([division_ce, division_it])
    db.flush()

    batch_a = Batch(division_id=division_ce.id, label="A1")
    batch_b = Batch(division_id=division_ce.id, label="B1")
    db.add_all([batch_a, batch_b])
    db.flush()

    teacher = User(
        id="teacher-1",
        full_name="Teacher One",
        role=UserRole.teacher,
        teacher_id="T001",
        password_hash=hash_password("Pass@123"),
    )
    other_teacher = User(
        id="teacher-2",
        full_name="Teacher Two",
        role=UserRole.teacher,
        teacher_id="T002",
        password_hash=hash_password("Pass@123"),
    )
    admin = User(
        id="admin-1",
        full_name="Admin User",
        role=UserRole.admin,
        admin_id="ADMIN001",
        password_hash=hash_password("Pass@123"),
        is_super_admin=True,
    )
    students = [
        User(
            id="student-in-range",
            full_name="In Range",
            role=UserRole.student,
            student_id="25CE010",
            password_hash=hash_password("Pass@123"),
        ),
        User(
            id="student-out-range",
            full_name="Out Of Range",
            role=UserRole.student,
            student_id="25CE009",
            password_hash=hash_password("Pass@123"),
        ),
        User(
            id="student-batch-a",
            full_name="Batch A",
            role=UserRole.student,
            student_id="25CE011",
            password_hash=hash_password("Pass@123"),
        ),
        User(
            id="student-batch-b",
            full_name="Batch B",
            role=UserRole.student,
            student_id="25CE012",
            password_hash=hash_password("Pass@123"),
        ),
        User(
            id="student-other-division",
            full_name="Other Division",
            role=UserRole.student,
            student_id="25IT001",
            password_hash=hash_password("Pass@123"),
        ),
    ]
    db.add_all([teacher, other_teacher, admin, *students])
    db.flush()

    subject = Subject(code="CS201", name="Data Structures", subject_type="lecture")
    lab_subject = Subject(code="CSL201", name="Data Structures Lab", subject_type="lab")
    db.add_all([subject, lab_subject])
    db.flush()

    lecture_assignment = TeacherAssignment(
        teacher_user_id=teacher.id,
        subject_id=subject.id,
        division_id=division_ce.id,
    )
    batch_assignment = TeacherAssignment(
        teacher_user_id=teacher.id,
        subject_id=lab_subject.id,
        division_id=division_ce.id,
        batch_id=batch_a.id,
    )
    other_division_assignment = TeacherAssignment(
        teacher_user_id=teacher.id,
        subject_id=subject.id,
        division_id=division_it.id,
    )
    other_teacher_assignment = TeacherAssignment(
        teacher_user_id=other_teacher.id,
        subject_id=subject.id,
        division_id=division_ce.id,
    )
    db.add_all([
        lecture_assignment,
        batch_assignment,
        other_division_assignment,
        other_teacher_assignment,
    ])
    db.flush()

    db.add_all([
        DivisionStudent(student_user_id="student-in-range", division_id=division_ce.id),
        DivisionStudent(student_user_id="student-out-range", division_id=division_ce.id),
        DivisionStudent(
            student_user_id="student-batch-a",
            division_id=division_ce.id,
            batch_id=batch_a.id,
        ),
        DivisionStudent(
            student_user_id="student-batch-b",
            division_id=division_ce.id,
            batch_id=batch_b.id,
        ),
        DivisionStudent(
            student_user_id="student-other-division",
            division_id=division_it.id,
        ),
    ])
    semester = Semester(
        name="Semester IV",
        start_date=date.today() - timedelta(days=30),
        end_date=date.today() + timedelta(days=30),
        is_active=True,
    )
    db.add(semester)
    db.commit()

    return {
        "teacher": teacher,
        "other_teacher": other_teacher,
        "admin": admin,
        "in_range": students[0],
        "out_of_range": students[1],
        "batch_a_student": students[2],
        "batch_b_student": students[3],
        "other_division_student": students[4],
        "ce": division_ce,
        "it": division_it,
        "batch_a": batch_a,
        "batch_b": batch_b,
        "lecture_assignment": lecture_assignment,
        "batch_assignment": batch_assignment,
        "other_division_assignment": other_division_assignment,
        "other_teacher_assignment": other_teacher_assignment,
        "semester": semester,
    }


def make_session(
    db: Session,
    assignment: TeacherAssignment,
    session_id: str = "session-1",
    *,
    active: bool = True,
    minutes_old: int = 5,
):
    from app.models import Session as LectureSession

    session = LectureSession(
        id=session_id,
        subject=assignment.subject.name,
        teacher_user_id=assignment.teacher_user_id,
        assignment_id=assignment.id,
        token=f"token-{session_id}",
        starts_at=datetime.utcnow() - timedelta(minutes=minutes_old),
        is_active=active,
        finalization_open=False,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session
