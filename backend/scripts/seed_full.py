"""
Seed script: creates admin, CE FY teachers from timetable, CE FY timetable (Sem II 2025-26),
and students 25CE001–25CE142 assigned to CE FY divisions.
"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from sqlalchemy import select, text
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

# Teachers from CE FY Div1 + Div2 timetable
# (short_code, full_name, teacher_id)
CE_TEACHERS = [
    ("RBC", "Dr. Rajendra Chauhan",    "T001"),
    ("YFP", "Dr. Yogeshwari Patel",    "T002"),
    ("APC", "Dr. Aayushi Chaudhari",   "T003"),
    ("MJP", "Mayuri Popat",            "T004"),
    ("KJM", "Krunal Maheriya",         "T005"),
    ("BSS", "Bijal Suthar",            "T006"),
    ("TRP", "Trusha Patel",            "T007"),
    ("SRC", "Sagar Chokshi",           "T008"),
    ("AVP", "Axat Patel",              "T009"),
    ("GAP", "Gaurang Patel",           "T010"),
    ("APP", "Anand Patel",             "T011"),
    ("DYP", "Dipali Patel",            "T012"),
    ("SRP", "Dr. Sachin Patel",        "T013"),
    ("MNS", "Dr. Manan Shah",          "T014"),
    ("RNP", "Ronak Patel",             "T015"),
    ("AYT", "Ashif Thakor",            "T016"),
    ("NAP", "Nirpex Patel",            "T017"),
    ("PCP", "Pinal Patel",             "T018"),
    ("AK",  "Amit Kumar",              "T019"),
    ("PMP", "Dr. Pratik Pataniya",     "T020"),
    ("SB",  "Dr. Sanjay Bhakhar",      "T021"),
    ("AYT2","Ashif Thakor",            "T016"),  # same person, skip duplicate
]

# Subjects: (code, name, type)
CE_SUBJECTS = [
    ("MSUD102",     "Engineering Mathematics-II",          "lecture"),
    ("CEUC102",     "Object Oriented Programming with C++","lecture"),
    ("CEUC102_LAB", "OOP with C++ Lab",                    "lab"),
    ("MEUD101",     "Elements of Engineering",             "lab"),
    ("CLUV101",     "Environmental Sciences",              "lecture"),
    ("PSUD102",     "Engineering Physics-II",              "lecture"),
    ("CSUC101",     "Digital Electronics",                 "lecture"),
    ("CSUC101_LAB", "Digital Electronics Lab",             "lab"),
]

# CE Div1 assignments: (teacher_short, subject_code, batch_label or None)
# batch=None means lecture (whole division), batch=label means lab group
CE_DIV1_ASSIGNMENTS = [
    # MSUD102 lectures — RBC and YFP both teach (different slots)
    ("RBC", "MSUD102",     None),
    ("YFP", "MSUD102",     None),
    # CEUC102 lectures
    ("APC", "CEUC102",     None),
    ("MJP", "CEUC102",     None),
    ("KJM", "CEUC102",     None),
    ("BSS", "CEUC102",     None),
    ("TRP", "CEUC102",     None),
    # CEUC102 lab batches
    ("MJP", "CEUC102_LAB", "A1"),
    ("APC", "CEUC102_LAB", "B1"),
    ("TRP", "CEUC102_LAB", "C1"),
    # MEUD101 lab batches
    ("SRC", "MEUD101",     "A1"),
    ("AVP", "MEUD101",     "A1"),
    ("GAP", "MEUD101",     "B1"),
    ("APP", "MEUD101",     "B1"),
    ("SRC", "MEUD101",     "C1"),
    # CLUV101 lecture
    ("DYP", "CLUV101",     None),
    # PSUD102 lecture
    ("SRP", "PSUD102",     None),
    ("MNS", "PSUD102",     None),
    # CSUC101 lecture
    ("RNP", "CSUC101",     None),
    ("AYT", "CSUC101",     None),
]

# CE Div2 assignments
CE_DIV2_ASSIGNMENTS = [
    ("RBC", "MSUD102",     None),
    ("YFP", "MSUD102",     None),
    ("APC", "CEUC102",     None),
    ("MJP", "CEUC102",     None),
    ("KJM", "CEUC102",     None),
    ("TRP", "CEUC102",     None),
    ("MJP", "CEUC102_LAB", "A2"),
    ("APC", "CEUC102_LAB", "B2"),
    ("TRP", "CEUC102_LAB", "C2"),
    ("SRC", "MEUD101",     "A2"),
    ("AVP", "MEUD101",     "A2"),
    ("GAP", "MEUD101",     "B2"),
    ("NAP", "MEUD101",     "B2"),
    ("DYP", "MEUD101",     "C2"),
    ("PCP", "MEUD101",     "C2"),
    ("AK",  "CLUV101",     None),
    ("DYP", "CLUV101",     None),
    ("SRP", "PSUD102",     None),
    ("PMP", "PSUD102",     None),
    ("MNS", "PSUD102",     None),
    ("RNP", "CSUC101",     None),
    ("AYT", "CSUC101",     None),
    ("SB",  "MEUD101",     "A2"),
]

# Schedule slots for CE Div1
# (teacher_short, subject_code, batch_label, day, time_start, time_end, room)
CE_DIV1_SLOTS = [
    # Monday
    ("SRC", "MEUD101", "A1", 0, "09:10", "10:10", "323-C"),
    ("GAP", "MEUD101", "B1", 0, "09:10", "10:10", "326"),
    ("APP", "MEUD101", "C1", 0, "09:10", "10:10", "514"),
    ("SRC", "MEUD101", "A1", 0, "10:10", "11:10", "323-C"),
    ("GAP", "MEUD101", "B1", 0, "10:10", "11:10", "326"),
    ("APP", "MEUD101", "C1", 0, "10:10", "11:10", "514"),
    ("RBC", "MSUD102", None, 0, "12:10", "13:10", "310"),
    ("RBC", "MSUD102", None, 0, "13:10", "14:10", "310"),
    ("MJP", "CEUC102_LAB", "A1", 0, "14:20", "15:20", "316"),
    ("APC", "CEUC102_LAB", "B1", 0, "14:20", "15:20", "317"),
    ("TRP", "CEUC102_LAB", "C1", 0, "14:20", "15:20", "317"),
    ("MJP", "CEUC102_LAB", "A1", 0, "15:20", "16:20", "316"),
    ("APC", "CEUC102_LAB", "B1", 0, "15:20", "16:20", "317"),
    ("TRP", "CEUC102_LAB", "C1", 0, "15:20", "16:20", "317"),
    # Tuesday
    ("YFP", "MSUD102", None, 1, "09:10", "10:10", "310"),
    ("YFP", "MSUD102", None, 1, "10:10", "11:10", "310"),
    ("SRP", "PSUD102", None, 1, "12:10", "13:10", "DEPSTAR-321"),
    ("RNP", "CSUC101", None, 1, "13:10", "14:10", "219"),
    ("MJP", "CEUC102", None, 1, "14:20", "15:20", "316"),
    ("KJM", "CEUC102", None, 1, "15:20", "16:20", "317"),
    # Wednesday
    ("DYP", "CLUV101", None, 2, "12:10", "13:10", "310"),
    ("TRP", "CEUC102", None, 2, "13:10", "14:10", "310"),
    ("YFP", "MSUD102", None, 2, "14:20", "15:20", "310"),
    ("AYT", "CSUC101", None, 2, "15:20", "16:20", "323B"),
    # Thursday
    ("SRP", "PSUD102", None, 3, "09:10", "10:10", "310"),
    ("RNP", "CSUC101", None, 3, "10:10", "11:10", "310"),
    ("APC", "CEUC102", None, 3, "12:10", "13:10", "310"),
    ("SRC", "MEUD101", "A1", 3, "13:10", "14:10", "323-C"),
    ("GAP", "MEUD101", "B1", 3, "13:10", "14:10", "326"),
    ("SRC", "MEUD101", "A1", 3, "14:20", "15:20", "323-C"),
    ("GAP", "MEUD101", "B1", 3, "14:20", "15:20", "326"),
    ("MJP", "CEUC102", None, 3, "15:20", "16:20", "316"),
    # Friday
    ("MNS", "PSUD102", None, 4, "09:10", "10:10", "310"),
    ("AYT", "CSUC101", None, 4, "10:10", "11:10", "310"),
    ("BSS", "CEUC102", None, 4, "12:10", "13:10", "310"),
    ("MNS", "PSUD102", None, 4, "14:20", "15:20", "308"),
    ("APC", "CEUC102", None, 4, "15:20", "16:20", "321"),
    # Saturday
    ("RBC", "MSUD102", None, 5, "09:10", "10:10", "319"),
    ("RBC", "MSUD102", None, 5, "10:10", "11:10", "319"),
]

CE_DIV2_SLOTS = [
    # Monday
    ("MJP", "CEUC102", None, 0, "09:10", "10:10", "310"),
    ("SRC", "MEUD101", "A2", 0, "09:10", "10:10", "323-C"),
    ("GAP", "MEUD101", "B2", 0, "09:10", "10:10", "326"),
    ("APP", "MEUD101", "C2", 0, "09:10", "10:10", "514"),
    ("MJP", "CEUC102", None, 0, "10:10", "11:10", "310"),
    ("NAP", "MEUD101", "A2", 0, "10:10", "11:10", "323-C"),
    ("DYP", "MEUD101", "B2", 0, "10:10", "11:10", "326"),
    ("PCP", "MEUD101", "C2", 0, "10:10", "11:10", "514"),
    ("RBC", "MSUD102", None, 0, "12:10", "13:10", "303"),
    ("YFP", "MSUD102", None, 0, "13:10", "14:10", "304"),
    ("AK",  "CLUV101", None, 0, "14:20", "15:20", "304"),
    ("MJP", "CEUC102_LAB", "A2", 0, "14:20", "15:20", "316"),
    ("APC", "CEUC102_LAB", "B2", 0, "14:20", "15:20", "317"),
    ("TRP", "CEUC102_LAB", "C2", 0, "14:20", "15:20", "317"),
    ("MJP", "CEUC102_LAB", "A2", 0, "15:20", "16:20", "316"),
    ("APC", "CEUC102_LAB", "B2", 0, "15:20", "16:20", "317"),
    ("TRP", "CEUC102_LAB", "C2", 0, "15:20", "16:20", "317"),
    # Tuesday
    ("GAP", "MEUD101", "A2", 1, "09:10", "10:10", "323-C"),
    ("APC", "CEUC102", None, 1, "10:10", "11:10", "316"),
    ("SRP", "PSUD102", None, 1, "12:10", "13:10", "DEPSTAR-321"),
    ("AYT", "CSUC101", None, 1, "13:10", "14:10", "323B"),
    ("KJM", "CEUC102", None, 1, "14:20", "15:20", "316"),
    ("APC", "CEUC102", None, 1, "15:20", "16:20", "317"),
    # Wednesday
    ("RBC", "MSUD102", None, 2, "12:10", "13:10", "303"),
    ("AYT", "CSUC101", None, 2, "13:10", "14:10", "303"),
    ("YFP", "MSUD102", None, 2, "14:20", "15:20", "303"),
    ("SRC", "MEUD101", "A2", 2, "15:20", "16:20", "303"),
    # Thursday
    ("PMP", "PSUD102", None, 3, "09:10", "10:10", "617-A"),
    ("RNP", "CSUC101", None, 3, "10:10", "11:10", "617-A"),
    ("MNS", "PSUD102", None, 3, "12:10", "13:10", "308"),
    ("SB",  "MEUD101", "A2", 3, "13:10", "14:10", "323-C"),
    ("NAP", "MEUD101", "B2", 3, "13:10", "14:10", "326"),
    ("DYP", "MEUD101", "C2", 3, "13:10", "14:10", "514"),
    ("TRP", "CEUC102", None, 3, "14:20", "15:20", "317"),
    ("KJM", "CEUC102", None, 3, "15:20", "16:20", "316"),
    # Friday
    ("PMP", "PSUD102", None, 4, "09:10", "10:10", "321"),
    ("AYT", "CSUC101", None, 4, "10:10", "11:10", "323B"),
    ("DYP", "CLUV101", None, 4, "12:10", "13:10", "304"),
    ("YFP", "MSUD102", None, 4, "13:10", "14:10", "313"),
    ("APC", "CEUC102", None, 4, "14:20", "15:20", "303"),
    # Saturday
    ("RBC", "MSUD102", None, 5, "09:10", "10:10", "304"),
    ("RBC", "MSUD102", None, 5, "10:10", "11:10", "304"),
]


def get_or_create(db, model, defaults=None, **kwargs):
    obj = db.scalar(select(model).filter_by(**kwargs))
    if obj:
        return obj, False
    obj = model(**{**kwargs, **(defaults or {})})
    db.add(obj)
    db.flush()
    return obj, True


def main():
    Base.metadata.create_all(bind=engine)

    # Ensure admin enum value exists
    with engine.begin() as conn:
        conn.execute(text("ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'admin'"))

    db = SessionLocal()
    try:
        # ── Super admin ──────────────────────────────────────────────────────
        if not db.scalar(select(User).where(User.admin_id == "ADMIN001")):
            db.add(User(full_name="Super Admin", role=UserRole.admin, admin_id="ADMIN001",
                        password_hash=hash_password(DEFAULT_PASS), is_super_admin=True))
            print("Created super admin: ADMIN001")

        # ── Teachers from CE timetable ────────────────────────────────────────
        teacher_map = {}  # short_code -> User
        seen_ids = set()
        for short, name, tid in CE_TEACHERS:
            if short in teacher_map or tid in seen_ids:
                # map duplicate short codes to existing user
                if tid in seen_ids:
                    existing = db.scalar(select(User).where(User.teacher_id == tid))
                    if existing:
                        teacher_map[short] = existing
                continue
            user, created = get_or_create(db, User, teacher_id=tid,
                                          defaults=dict(full_name=name, role=UserRole.teacher,
                                                        password_hash=hash_password(DEFAULT_PASS)))
            teacher_map[short] = user
            seen_ids.add(tid)
            if created:
                print(f"Created teacher: {tid} {name}")

        # ── Branches ─────────────────────────────────────────────────────────
        branch_map = {}
        for code, name in BRANCHES:
            b, _ = get_or_create(db, Branch, code=code, defaults=dict(name=name))
            branch_map[code] = b

        # ── Semester ─────────────────────────────────────────────────────────
        sem, _ = get_or_create(db, Semester, name="Sem II 2025-26",
                               defaults=dict(start_date="2026-01-19", end_date="2026-05-31",
                                             is_active=True))

        # ── CE FY Divisions + Batches ─────────────────────────────────────────
        ce = branch_map["CE"]
        div1, _ = get_or_create(db, Division, branch_id=ce.id, year=1, div_number=1,
                                defaults=dict(label="CE-FY-Div1"))
        div2, _ = get_or_create(db, Division, branch_id=ce.id, year=1, div_number=2,
                                defaults=dict(label="CE-FY-Div2"))

        batch_map_d1 = {}
        for lbl in ["A1", "B1", "C1"]:
            b, _ = get_or_create(db, Batch, division_id=div1.id, label=lbl)
            batch_map_d1[lbl] = b

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

        # ── Assignments ───────────────────────────────────────────────────────
        assign_cache = {}

        def get_assign(short, subj_code, div, batch_label):
            teacher = teacher_map.get(short)
            subj = subj_map.get(subj_code)
            if not teacher or not subj:
                return None
            bmap = batch_map_d1 if div.id == div1.id else batch_map_d2
            batch = bmap.get(batch_label) if batch_label else None
            key = (teacher.id, subj.id, div.id, batch.id if batch else None)
            if key in assign_cache:
                return assign_cache[key]
            a, _ = get_or_create(db, TeacherAssignment,
                                  teacher_user_id=teacher.id, subject_id=subj.id,
                                  division_id=div.id, batch_id=batch.id if batch else None)
            assign_cache[key] = a
            return a

        for (short, scode, blbl) in CE_DIV1_ASSIGNMENTS:
            get_assign(short, scode, div1, blbl)

        for (short, scode, blbl) in CE_DIV2_ASSIGNMENTS:
            get_assign(short, scode, div2, blbl)

        db.flush()

        # ── Schedule slots ────────────────────────────────────────────────────
        def add_slots(slot_list, div):
            for (short, scode, blbl, day, ts, te, room) in slot_list:
                a = get_assign(short, scode, div, blbl)
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

        # Clear old slots first to avoid duplicates from previous seed
        old_slots = db.execute(select(ScheduleSlot).where(ScheduleSlot.semester_id == sem.id)).scalars().all()
        for s in old_slots:
            db.delete(s)
        db.flush()

        add_slots(CE_DIV1_SLOTS, div1)
        add_slots(CE_DIV2_SLOTS, div2)
        db.flush()

        # ── Students 25CE001–25CE142 ──────────────────────────────────────────
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
                batch = batch_map_d1["A1"] if i <= 24 else (batch_map_d1["B1"] if i <= 48 else batch_map_d1["C1"])
            else:
                div = div2
                j = i - 71
                batch = batch_map_d2["A2"] if j <= 24 else (batch_map_d2["B2"] if j <= 48 else batch_map_d2["C2"])

            if not db.scalar(select(DivisionStudent).where(
                DivisionStudent.student_user_id == student.id,
                DivisionStudent.division_id == div.id
            )):
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
