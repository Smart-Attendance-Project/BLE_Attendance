"""
Seed: admin, CE FY teachers (from timetable images), CE Div1+Div2 slots, students 25CE001-25CE142.
Timetable source: CSPIT CE B.Tech Sem II 2025-26 (pages 2 & 3 of tt.pdf)
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
    ("CE", "Computer Engineering"), ("CS", "Computer Science"),
    ("IT", "Information Technology"), ("AIML", "AI & Machine Learning"),
    ("ME", "Mechanical Engineering"), ("CL", "Chemical Engineering"),
    ("EC", "Electronics & Communication"), ("EE", "Electrical Engineering"),
]

# (short_code, full_name, teacher_id)
# Extracted from CE Div1 + Div2 legend boxes in timetable images
CE_TEACHERS = [
    ("RBC", "Dr. Rajendra Chauhan",  "T001"),
    ("YFP", "Dr. Yogeshwari Patel",  "T002"),
    ("APC", "Dr. Aayushi Chaudhari", "T003"),
    ("MJP", "Mayuri Popat",          "T004"),
    ("KJM", "Krunal Maheriya",       "T005"),
    ("BSS", "Bijal Suthar",          "T006"),
    ("TRP", "Trusha Patel",          "T007"),
    ("SRC", "Sagar Chokshi",         "T008"),
    ("AVP", "Axat Patel",            "T009"),
    ("GAP", "Gaurang Patel",         "T010"),
    ("APP", "Anand Patel",           "T011"),
    ("DYP", "Dipali Patel",          "T012"),
    ("SRP", "Dr. Sachin Patel",      "T013"),
    ("MNS", "Dr. Manan Shah",        "T014"),
    ("RNP", "Ronak Patel",           "T015"),
    ("AYT", "Ashif Thakor",          "T016"),
    ("NAP", "Nirpex Patel",          "T017"),
    ("PCP", "Pinal Patel",           "T018"),
    ("AK",  "Amit Kumar",            "T019"),
    ("PMP", "Dr. Pratik Pataniya",   "T020"),
    ("SB",  "Dr. Sanjay Bhakhar",    "T021"),
    ("GKR", "Gargi Ray",             "T022"),
]

CE_SUBJECTS = [
    ("MSUD102",     "Engineering Mathematics-II",           "lecture"),
    ("CEUC102",     "Object Oriented Programming with C++", "lecture"),
    ("CEUC102_LAB", "OOP with C++ Lab",                    "lab"),
    ("MEUD101",     "Elements of Engineering",              "lab"),
    ("CLUV101",     "Environmental Sciences",               "lecture"),
    ("PSUD102",     "Engineering Physics-II",               "lecture"),
    ("CSUC101",     "Digital Electronics",                  "lecture"),
    ("CSUC101_LAB", "Digital Electronics Lab",              "lab"),
]

# ── CE Div1 schedule slots ────────────────────────────────────────────────────
# Read directly from image 1 (page 2 of pdf), cell by cell.
# Format: (teacher_short, subject_code, batch_label_or_None, day 0=Mon, time_start, time_end, room)
# Batch labels: A1/B1/C1 for Div1
CE_DIV1_SLOTS = [
    # MON 09:10-10:10 — MEUD101 lab batches
    ("AVP", "MEUD101", "A1", 0, "09:10", "10:10", "323-C"),
    ("APP", "MEUD101", "B1", 0, "09:10", "10:10", "326"),
    ("SRC", "MEUD101", "C1", 0, "09:10", "10:10", "514"),
    # MON 10:10-11:10 — MEUD101 lab batches
    ("DYP", "MEUD101", "A1", 0, "10:10", "11:10", "323-C"),
    ("NAP", "MEUD101", "B1", 0, "10:10", "11:10", "326"),
    ("GKR", "MEUD101", "C1", 0, "10:10", "11:10", "514"),
    # MON 12:10-13:10 — MSUD102 lecture (YFP)
    ("YFP", "MSUD102", None, 0, "12:10", "13:10", "310"),
    # MON 13:10-14:10 — CEUC102 lecture (APC)
    ("APC", "CEUC102", None, 0, "13:10", "14:10", "310"),
    # MON 14:20-15:20 — CEUC102 lab batches
    ("MJP", "CEUC102_LAB", "A1", 0, "14:20", "15:20", "316"),
    ("APC", "CEUC102_LAB", "B1", 0, "14:20", "15:20", "317"),
    ("BSS", "CEUC102_LAB", "C1", 0, "14:20", "15:20", "317"),
    # MON 15:20-16:20 — CEUC102 lab batches (same)
    ("MJP", "CEUC102_LAB", "A1", 0, "15:20", "16:20", "316"),
    ("APC", "CEUC102_LAB", "B1", 0, "15:20", "16:20", "317"),
    ("BSS", "CEUC102_LAB", "C1", 0, "15:20", "16:20", "317"),

    # TUE 09:10-10:10 — MEUD101 SRC whole div (no batch shown = whole class practical)
    ("SRC", "MEUD101", None, 1, "09:10", "10:10", "310"),
    # TUE 10:10-11:10 — CSUC101 RNP
    ("RNP", "CSUC101", None, 1, "10:10", "11:10", "310"),
    # TUE 12:10-13:10 — MSUD102 YFP
    ("YFP", "MSUD102", None, 1, "12:10", "13:10", "310"),
    # TUE 13:10-14:10 — MEUD101 GKR
    ("GKR", "MEUD101", None, 1, "13:10", "14:10", "310"),
    # TUE 14:20-15:20 — CLUV101 DYP
    ("DYP", "CLUV101", None, 1, "14:20", "15:20", "310"),

    # WED 09:10-10:10 — MEUD101 SRC
    ("SRC", "MEUD101", None, 2, "09:10", "10:10", "310"),
    # WED 10:10-11:10 — MSUD102 RBC
    ("RBC", "MSUD102", None, 2, "10:10", "11:10", "310"),
    # WED 12:10-13:10 — CLUV101 DYP
    ("DYP", "CLUV101", None, 2, "12:10", "13:10", "310"),
    # WED 13:10-14:10 — CEUC102 TRP
    ("TRP", "CEUC102", None, 2, "13:10", "14:10", "310"),
    # WED 14:20-15:20 — MSUD102(T) YFP
    ("YFP", "MSUD102", None, 2, "14:20", "15:20", "310"),
    # WED 15:20-16:20 — CSUC101 RNP
    ("RNP", "CSUC101", None, 2, "15:20", "16:20", "310"),

    # THU 09:10-10:10 — MSUD102 RBC
    ("RBC", "MSUD102", None, 3, "09:10", "10:10", "310"),
    # THU 10:10-11:10 — MEUD101 GAP
    ("GAP", "MEUD101", None, 3, "10:10", "11:10", "310"),
    # THU 12:10-13:10 — PSUD102 SRP (B1), CSUC101 RNP (C1)
    ("SRP", "PSUD102", "B1", 3, "12:10", "13:10", "DEPSTAR-321"),
    ("RNP", "CSUC101", "C1", 3, "12:10", "13:10", "219"),
    # THU 13:10-14:10 — PSUD102 SRP (B1), CSUC101 RNP (C1)
    ("SRP", "PSUD102", "B1", 3, "13:10", "14:10", "DEPSTAR-321"),
    ("RNP", "CSUC101", "C1", 3, "13:10", "14:10", "219"),
    # THU 14:20-15:20 — CSUC101 AYT (A1)
    ("AYT", "CSUC101", "A1", 3, "14:20", "15:20", "323B"),
    # THU 15:20-16:20 — CSUC101 AYT (A1)
    ("AYT", "CSUC101", "A1", 3, "15:20", "16:20", "323B"),

    # FRI 09:10-10:10 — PSUD102 SB (A1), CSUC101 RNP (B1)
    ("SB",  "PSUD102", "A1", 4, "09:10", "10:10", "308"),
    ("RNP", "CSUC101", "B1", 4, "09:10", "10:10", "319"),
    # FRI 10:10-11:10 — PSUD102 SB (A1), CSUC101 RNP (B1)
    ("SB",  "PSUD102", "A1", 4, "10:10", "11:10", "308"),
    ("RNP", "CSUC101", "B1", 4, "10:10", "11:10", "319"),
    # FRI 12:10-13:10 — CEUC102 TRP
    ("TRP", "CEUC102", None, 4, "12:10", "13:10", "310"),
    # FRI 14:20-15:20 — PSUD102 MNS (C1), CEUC102 MJP/A1, KJM/B1, TRP/C1
    ("MNS", "PSUD102",  "C1", 4, "14:20", "15:20", "321"),
    ("MJP", "CEUC102_LAB", "A1", 4, "14:20", "15:20", "316"),
    ("KJM", "CEUC102_LAB", "B1", 4, "14:20", "15:20", "317"),
    ("TRP", "CEUC102_LAB", "C1", 4, "14:20", "15:20", "317"),
    # FRI 15:20-16:20 — PSUD102 MNS (C1), CEUC102 MJP/A1, KJM/B1, TRP/C1
    ("MNS", "PSUD102",  "C1", 4, "15:20", "16:20", "321"),
    ("MJP", "CEUC102_LAB", "A1", 4, "15:20", "16:20", "316"),
    ("KJM", "CEUC102_LAB", "B1", 4, "15:20", "16:20", "317"),
    ("TRP", "CEUC102_LAB", "C1", 4, "15:20", "16:20", "317"),
]

# ── CE Div2 schedule slots ────────────────────────────────────────────────────
# Read from image 2 (page 3 of pdf)
# Batch labels: A2/B2/C2 for Div2
CE_DIV2_SLOTS = [
    # MON 09:10-10:10 — CEUC102 MJP (A2), CEUC102 MJP/B2, APC/C2... wait image shows:
    # MON col: CEUC102 MJP/310/A2 (single cell spanning)
    ("MJP", "CEUC102", None, 0, "09:10", "10:10", "310"),
    # TUE 09:10-10:10 — CEUC102 MJP/A2, APC/B2, TRP/C2
    ("MJP", "CEUC102_LAB", "A2", 1, "09:10", "10:10", "316"),
    ("APC", "CEUC102_LAB", "B2", 1, "09:10", "10:10", "317"),
    ("TRP", "CEUC102_LAB", "C2", 1, "09:10", "10:10", "317"),
    # TUE 10:10-11:10 — CEUC102 MJP/A2, APC/B2, TRP/C2
    ("MJP", "CEUC102_LAB", "A2", 1, "10:10", "11:10", "316"),
    ("APC", "CEUC102_LAB", "B2", 1, "10:10", "11:10", "317"),
    ("TRP", "CEUC102_LAB", "C2", 1, "10:10", "11:10", "317"),
    # WED 09:10-10:10 — CSUC101 RNP (A2), PSUD102 SRP/B2, PMP/C2
    ("RNP", "CSUC101", "A2", 2, "09:10", "10:10", "617-A"),
    ("SRP", "PSUD102", "B2", 2, "09:10", "10:10", "Depstar-321"),
    ("PMP", "PSUD102", "C2", 2, "09:10", "10:10", "321"),
    # WED 10:10-11:10 — CSUC101 RNP (A2), PSUD102 SRP/B2, PMP/C2
    ("RNP", "CSUC101", "A2", 2, "10:10", "11:10", "617-A"),
    ("SRP", "PSUD102", "B2", 2, "10:10", "11:10", "Depstar-321"),
    ("PMP", "PSUD102", "C2", 2, "10:10", "11:10", "321"),
    # THU 09:10-10:10 — MEUD101 MVS/A2, AVP/B2, APP/C2
    ("AVP", "MEUD101", "A2", 3, "09:10", "10:10", "323-C"),
    ("AVP", "MEUD101", "B2", 3, "09:10", "10:10", "326"),
    ("APP", "MEUD101", "C2", 3, "09:10", "10:10", "514"),
    # THU 10:10-11:10 — MEUD101 PCP/A2, NAP/B2, DYP/C2
    ("PCP", "MEUD101", "A2", 3, "10:10", "11:10", "323-C"),
    ("NAP", "MEUD101", "B2", 3, "10:10", "11:10", "326"),
    ("DYP", "MEUD101", "C2", 3, "10:10", "11:10", "514"),
    # MON 10:10-11:10 — MEUD101 GAP (A2)
    ("GAP", "MEUD101", "A2", 0, "10:10", "11:10", "310"),
    # MON 12:10-13:10 — MEUD101 DYP (whole)
    ("DYP", "MEUD101", None, 0, "12:10", "13:10", "304"),
    # MON 13:10-14:10 — MSUD102 YFP
    ("YFP", "MSUD102", None, 0, "13:10", "14:10", "304"),
    # MON 14:20-15:20 — PSUD102 PMP (A2), CSUC101 AYT (B2)
    ("PMP", "PSUD102", "A2", 0, "14:20", "15:20", "321"),
    ("AYT", "CSUC101", "B2", 0, "14:20", "15:20", "323B"),
    # MON 15:20-16:20 — PSUD102 PMP (A2), CSUC101 AYT (B2)
    ("PMP", "PSUD102", "A2", 0, "15:20", "16:20", "321"),
    ("AYT", "CSUC101", "B2", 0, "15:20", "16:20", "323B"),
    # TUE 12:10-13:10 — MSUD102 RBC
    ("RBC", "MSUD102", None, 1, "12:10", "13:10", "303"),
    # TUE 13:10-14:10 — MSUD102 YFP
    ("YFP", "MSUD102", None, 1, "13:10", "14:10", "313"),
    # TUE 14:20-15:20 — CLUV101 AK
    ("AK",  "CLUV101", None, 1, "14:20", "15:20", "304"),
    # TUE 15:20-16:20 — CLUV101 AK
    ("AK",  "CLUV101", None, 1, "15:20", "16:20", "304"),
    # WED 12:10-13:10 — MSUD102 RBC
    ("RBC", "MSUD102", None, 2, "12:10", "13:10", "303"),
    # WED 13:10-14:10 — CSUC101 AYT
    ("AYT", "CSUC101", None, 2, "13:10", "14:10", "303"),
    # WED 14:20-15:20 — MSUD102(T) YFP
    ("YFP", "MSUD102", None, 2, "14:20", "15:20", "303"),
    # WED 15:20-16:20 — CEUC102 KJM (A2)
    ("KJM", "CEUC102", "A2", 2, "15:20", "16:20", "303"),
    # THU 12:10-13:10 — CSUC101 AYT, MSUD102(T) RBC
    ("AYT", "CSUC101", None, 3, "12:10", "13:10", "303"),
    ("RBC", "MSUD102", None, 3, "12:10", "13:10", "304"),
    # THU 13:10-14:10 — MEUD101 SRC
    ("SRC", "MEUD101", None, 3, "13:10", "14:10", "303"),
    # FRI 09:10-10:10 — CSUC101 AYT (C2)
    ("AYT", "CSUC101", "C2", 4, "09:10", "10:10", "323B"),
    # FRI 10:10-11:10 — CSUC101 AYT (C2)
    ("AYT", "CSUC101", "C2", 4, "10:10", "11:10", "323B"),
    # FRI 12:10-13:10 — MSUD102 RBC
    ("RBC", "MSUD102", None, 4, "12:10", "13:10", "314"),
    # FRI 14:20-15:20 — MEUD101 SRC, CEUC102 KJM/A2, APC/B2, TRP/C2
    ("SRC", "MEUD101", None, 4, "14:20", "15:20", "303"),
    ("KJM", "CEUC102_LAB", "A2", 4, "14:20", "15:20", "316"),
    ("APC", "CEUC102_LAB", "B2", 4, "14:20", "15:20", "317"),
    ("TRP", "CEUC102_LAB", "C2", 4, "14:20", "15:20", "317"),
    # FRI 15:20-16:20 — CEUC102 APC
    ("APC", "CEUC102", None, 4, "15:20", "16:20", "303"),
    ("KJM", "CEUC102_LAB", "A2", 4, "15:20", "16:20", "316"),
    ("APC", "CEUC102_LAB", "B2", 4, "15:20", "16:20", "317"),
    ("TRP", "CEUC102_LAB", "C2", 4, "15:20", "16:20", "317"),
    # SAT 09:10-10:10 — MSUD102 RBC
    ("RBC", "MSUD102", None, 5, "09:10", "10:10", "304"),
    # SAT 10:10-11:10 — MSUD102 RBC
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
    with engine.begin() as conn:
        conn.execute(text("ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'admin'"))

    db = SessionLocal()
    try:
        # Super admin
        if not db.scalar(select(User).where(User.admin_id == "ADMIN001")):
            db.add(User(full_name="Super Admin", role=UserRole.admin, admin_id="ADMIN001",
                        password_hash=hash_password(DEFAULT_PASS), is_super_admin=True))
            print("Created super admin: ADMIN001")

        # Teachers — update name if exists, create if not
        teacher_map = {}
        for short, name, tid in CE_TEACHERS:
            existing = db.scalar(select(User).where(User.teacher_id == tid))
            if existing:
                existing.full_name = name  # fix name if wrong
                teacher_map[short] = existing
            else:
                user = User(full_name=name, role=UserRole.teacher,
                            teacher_id=tid, password_hash=hash_password(DEFAULT_PASS))
                db.add(user)
                db.flush()
                teacher_map[short] = user
                print(f"Created teacher: {tid} {name}")

        db.flush()

        # Branches
        branch_map = {}
        for code, name in BRANCHES:
            b, _ = get_or_create(db, Branch, code=code, defaults=dict(name=name))
            branch_map[code] = b

        # Semester
        sem, _ = get_or_create(db, Semester, name="Sem II 2025-26",
                               defaults=dict(start_date="2026-01-19", end_date="2026-05-31",
                                             is_active=True))

        # CE FY Divisions
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

        # Subjects
        subj_map = {}
        for code, name, stype in CE_SUBJECTS:
            s, _ = get_or_create(db, Subject, code=code,
                                 defaults=dict(name=name, subject_type=stype))
            subj_map[code] = s

        # Build assignment cache
        assign_cache = {}

        def get_assign(short, subj_code, div, batch_label):
            teacher = teacher_map.get(short)
            subj = subj_map.get(subj_code)
            if not teacher or not subj:
                print(f"  WARN: missing teacher={short} or subj={subj_code}")
                return None
            bmap = batch_map_d1 if div.id == div1.id else batch_map_d2
            batch = bmap.get(batch_label) if batch_label else None
            key = (teacher.id, subj.id, div.id, batch.id if batch else None)
            if key in assign_cache:
                return assign_cache[key]
            a, _ = get_or_create(db, TeacherAssignment,
                                  teacher_user_id=teacher.id, subject_id=subj.id,
                                  division_id=div.id,
                                  batch_id=batch.id if batch else None)
            assign_cache[key] = a
            return a

        # Clear old slots for this semester
        old = db.execute(select(ScheduleSlot).where(ScheduleSlot.semester_id == sem.id)).scalars().all()
        for s in old:
            db.delete(s)
        db.flush()

        # Add Div1 slots
        for (short, scode, blbl, day, ts, te, room) in CE_DIV1_SLOTS:
            a = get_assign(short, scode, div1, blbl)
            if a:
                db.add(ScheduleSlot(assignment_id=a.id, semester_id=sem.id,
                                    day_of_week=day, time_start=ts, time_end=te, room=room))

        # Add Div2 slots
        for (short, scode, blbl, day, ts, te, room) in CE_DIV2_SLOTS:
            a = get_assign(short, scode, div2, blbl)
            if a:
                db.add(ScheduleSlot(assignment_id=a.id, semester_id=sem.id,
                                    day_of_week=day, time_start=ts, time_end=te, room=room))

        db.flush()

        # Students 25CE001-25CE142
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
        print(f"Seeded {created_count} students")
        print("Done.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
