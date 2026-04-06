"""
Seed script: creates admin, demo teacher, CE FY timetable (Sem II 2025-26),
and students 25CE001–25CE142 assigned to CE FY divisions.
"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from sqlalchemy import select
from app.auth import hash_password
from app.database import Base, SessionLocal, engine
from app.models import (
    Batch, Branch, Division, DivisionStudent, ScheduleSlot, Semester,
    Subject, TeacherAssignment, User, UserRole,
)

DEFAULT_PASS = "Pass@123"

BRANCHES = [
    ("CE", "Computer Engineering"),
    ("CS", "Computer Science"),
    ("IT", "Information Technology"),
    ("AIML", "AI & Machine Learning"),
    ("ME", "Mechanical Engineering"),
    ("CL", "Chemical Engineering"),
    ("EC", "Electronics & Communication"),
    ("EE", "Electrical Engineering"),
]

# Subjects from CE FY Sem II timetable
CE_SUBJECTS = [
    ("MSUD102", "Engineering Mathematics-II", "lecture"),
    ("CEUC102", "Object Oriented Programming with C++", "lecture"),
    ("MEUD101", "Elements of Engineering", "lab"),
    ("CLUV101", "Environmental Sciences", "lecture"),
    ("PSUD102", "Engineering Physics-II", "lecture"),
    ("CSUC101", "Digital Electronics", "lecture"),
    ("CEUC102_LAB", "OOP with C++ Lab", "lab"),
    ("PSUD102_LAB", "Engineering Physics-II Lab", "lab"),
    ("CSUC101_LAB", "Digital Electronics Lab", "lab"),
]

# CE FY Div1 timetable (day_of_week: 0=Mon..5=Sat, batches A1/B1/C1)
# Format: (subject_code, day, time_start, time_end, room, batch_label or None)
CE_DIV1_SLOTS = [
    # Monday
    ("MEUD101", 0, "09:10", "10:10", "323-C", "A1"),
    ("MEUD101", 0, "09:10", "10:10", "326", "B1"),
    ("MEUD101", 0, "09:10", "10:10", "514", "C1"),
    ("MEUD101", 0, "10:10", "11:10", "323-C", "A1"),
    ("MEUD101", 0, "10:10", "11:10", "326", "B1"),
    ("MEUD101", 0, "10:10", "11:10", "514", "C1"),
    ("MSUD102", 0, "12:10", "13:10", "310", None),
    ("MSUD102", 0, "13:10", "14:10", "310", None),
    ("CEUC102", 0, "14:20", "15:20", "316", "A1"),
    ("CEUC102", 0, "14:20", "15:20", "317", "B1"),
    ("CEUC102", 0, "14:20", "15:20", "317", "C1"),
    ("CEUC102", 0, "15:20", "16:20", "316", "A1"),
    ("CEUC102", 0, "15:20", "16:20", "317", "B1"),
    ("CEUC102", 0, "15:20", "16:20", "317", "C1"),
    # Tuesday
    ("MSUD102", 1, "09:10", "10:10", "310", None),
    ("MSUD102", 1, "10:10", "11:10", "310", None),
    ("PSUD102", 1, "12:10", "13:10", "DEPSTAR-321", None),
    ("CSUC101", 1, "13:10", "14:10", "219", None),
    ("CEUC102", 1, "14:20", "15:20", "316", "A1"),
    ("CEUC102", 1, "14:20", "15:20", "317", "B1"),
    ("CEUC102", 1, "14:20", "15:20", "317", "C1"),
    ("CEUC102", 1, "15:20", "16:20", "316", "A1"),
    ("CEUC102", 1, "15:20", "16:20", "317", "B1"),
    ("CEUC102", 1, "15:20", "16:20", "317", "C1"),
    # Wednesday
    ("CLUV101", 2, "12:10", "13:10", "310", None),
    ("CEUC102", 2, "13:10", "14:10", "310", None),
    ("MSUD102", 2, "14:20", "15:20", "310", None),  # tutorial
    ("CSUC101", 2, "15:20", "16:20", "321", None),
    # Thursday
    ("PSUD102", 3, "09:10", "10:10", "310", None),
    ("CSUC101", 3, "10:10", "11:10", "310", None),
    ("CEUC102", 3, "12:10", "13:10", "310", None),
    ("MEUD101", 3, "13:10", "14:10", "323-C", "A1"),
    ("MEUD101", 3, "13:10", "14:10", "326", "B1"),
    ("MEUD101", 3, "14:20", "15:20", "323-C", "A1"),
    ("MEUD101", 3, "14:20", "15:20", "326", "B1"),
    ("CEUC102", 3, "15:20", "16:20", "316", "A1"),
    ("CEUC102", 3, "15:20", "16:20", "317", "B1"),
    ("CEUC102", 3, "15:20", "16:20", "317", "C1"),
    # Friday
    ("PSUD102", 4, "09:10", "10:10", "310", None),
    ("CSUC101", 4, "10:10", "11:10", "310", None),
    ("CEUC102", 4, "12:10", "13:10", "310", None),
    ("PSUD102", 4, "14:20", "15:20", "308", None),
    ("CEUC102", 4, "15:20", "16:20", "321", None),
    # Saturday
    ("MSUD102", 5, "09:10", "10:10", "319", None),
    ("MSUD102", 5, "10:10", "11:10", "319", None),
]


def get_or_create(db, model, defaults=None, **kwargs):
    obj = db.scalar(select(model).filter_by(**kwargs))
    if obj:
        return obj, False
    params = {**kwargs, **(defaults or {})}
    obj = model(**params)
    db.add(obj)
    db.flush()
    return obj, True


def main():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        # ── Super admin ──────────────────────────────────────────────────────
        if not db.scalar(select(User).where(User.admin_id == "ADMIN001")):
            db.add(User(full_name="Super Admin", role=UserRole.admin, admin_id="ADMIN001",
                        password_hash=hash_password(DEFAULT_PASS), is_super_admin=True))
            print("Created super admin: ADMIN001 / Pass@123")

        # ── Demo teacher ─────────────────────────────────────────────────────
        teacher, _ = get_or_create(db, User, teacher_id="T001",
                                   defaults=dict(full_name="Demo Teacher", role=UserRole.teacher,
                                                 password_hash=hash_password(DEFAULT_PASS)))

        # ── Branches ─────────────────────────────────────────────────────────
        branch_map = {}
        for code, name in BRANCHES:
            b, _ = get_or_create(db, Branch, code=code, defaults=dict(name=name))
            branch_map[code] = b

        # ── Semester ─────────────────────────────────────────────────────────
        sem, created = get_or_create(db, Semester, name="Sem II 2025-26",
                                     defaults=dict(start_date="2026-01-19", end_date="2026-05-31",
                                                   is_active=True))
        if created:
            print("Created semester: Sem II 2025-26")

        # ── CE FY Divisions ───────────────────────────────────────────────────
        ce = branch_map["CE"]
        div1, _ = get_or_create(db, Division, branch_id=ce.id, year=1, div_number=1,
                                defaults=dict(label="CE-FY-Div1"))
        div2, _ = get_or_create(db, Division, branch_id=ce.id, year=1, div_number=2,
                                defaults=dict(label="CE-FY-Div2"))

        # Batches for Div1
        batch_map_d1 = {}
        for lbl in ["A1", "B1", "C1"]:
            b, _ = get_or_create(db, Batch, division_id=div1.id, label=lbl)
            batch_map_d1[lbl] = b

        # Batches for Div2
        batch_map_d2 = {}
        for lbl in ["A2", "B2", "C2"]:
            b, _ = get_or_create(db, Batch, division_id=div2.id, label=lbl)
            batch_map_d2[lbl] = b

        # ── Subjects ──────────────────────────────────────────────────────────
        subj_map = {}
        for code, name, stype in CE_SUBJECTS:
            s, _ = get_or_create(db, Subject, code=code,
                                 defaults=dict(name=name, subject_type=stype))
            subj_map[code] = s

        # ── Teacher assignments for CE FY Div1 ────────────────────────────────
        # We create one assignment per (subject, division, batch) combo used in slots
        assign_cache = {}

        def get_assignment(subj_code, div, batch_label):
            batch = None
            if batch_label:
                batch = batch_map_d1.get(batch_label) if div.id == div1.id else batch_map_d2.get(batch_label)
            key = (subj_code, div.id, batch.id if batch else None)
            if key in assign_cache:
                return assign_cache[key]
            subj = subj_map.get(subj_code)
            if not subj:
                return None
            a, _ = get_or_create(db, TeacherAssignment,
                                  teacher_user_id=teacher.id, subject_id=subj.id,
                                  division_id=div.id, batch_id=batch.id if batch else None)
            assign_cache[key] = a
            return a

        # ── Schedule slots for CE FY Div1 ─────────────────────────────────────
        for (scode, day, ts, te, room, batch_lbl) in CE_DIV1_SLOTS:
            a = get_assignment(scode, div1, batch_lbl)
            if not a:
                continue
            existing = db.scalar(select(ScheduleSlot).where(
                ScheduleSlot.assignment_id == a.id,
                ScheduleSlot.semester_id == sem.id,
                ScheduleSlot.day_of_week == day,
                ScheduleSlot.time_start == ts,
            ))
            if not existing:
                db.add(ScheduleSlot(assignment_id=a.id, semester_id=sem.id,
                                    day_of_week=day, time_start=ts, time_end=te, room=room))

        db.flush()

        # ── Students 25CE001–25CE142 ──────────────────────────────────────────
        # Div1: 001–071 (71 students), Div2: 072–142 (71 students)
        # Batch assignment within div: A=1-24, B=25-48, C=49-71 (approx)
        created_count = 0
        for i in range(1, 143):
            sid = f"25CE{i:03d}"
            if db.scalar(select(User).where(User.student_id == sid)):
                continue
            student = User(full_name=f"Student {sid}", role=UserRole.student,
                           student_id=sid, password_hash=hash_password(DEFAULT_PASS))
            db.add(student)
            db.flush()

            if i <= 71:
                div = div1
                # A1: 1-24, B1: 25-48, C1: 49-71
                if i <= 24:
                    batch = batch_map_d1["A1"]
                elif i <= 48:
                    batch = batch_map_d1["B1"]
                else:
                    batch = batch_map_d1["C1"]
            else:
                div = div2
                j = i - 71
                # A2: 1-24, B2: 25-48, C2: 49-71
                if j <= 24:
                    batch = batch_map_d2["A2"]
                elif j <= 48:
                    batch = batch_map_d2["B2"]
                else:
                    batch = batch_map_d2["C2"]

            db.add(DivisionStudent(student_user_id=student.id,
                                   division_id=div.id, batch_id=batch.id))
            created_count += 1

        db.commit()
        print(f"Seeded {created_count} students (25CE001–25CE142)")
        print("Seed complete.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
