#!/usr/bin/env python3
"""
Database Stress Test
=====================
Tests the two DB-heavy operations that run during a real class session:

  1. Detection inserts — every student is "seen" every 30 s.
     For 70 students over a 1-hour class that's ~8,400 rows.
     This script inserts all of them as fast as possible and reports
     throughput (rows/s) and p95 latency.

  2. Attendance summary query — the teacher polls this every 10 s.
     It does a per-student aggregate (COUNT detections, fetch attendance row)
     for every student in the division.  We run it 20× concurrently to
     simulate the teacher phone polling while students are still beaconing.

Usage
-----
  # Make sure the backend venv is active and postgres is running:
  PYTHONPATH=backend .venv/bin/python load_tests/db_stress.py

  # Or point at a custom DB URL:
  DATABASE_URL="postgresql+psycopg://user:pass@host/db" \
      PYTHONPATH=backend .venv/bin/python load_tests/db_stress.py

  # Tune concurrency:
  .venv/bin/python load_tests/db_stress.py --workers 8 --students 70 --rounds 10
"""

import argparse
import os
import statistics
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

# Allow running from repo root with PYTHONPATH=backend
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from sqlalchemy import create_engine, func, and_, select, text
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.models import (
    Attendance, Base, Batch, Branch, Detection, Division, DivisionStudent,
    ScheduleSlot, Semester, Session as LectureSession, Subject,
    TeacherAssignment, User, UserRole,
)


# ── Engine setup ─────────────────────────────────────────────────────────────

def make_engine(pool_size: int = 10):
    url = os.environ.get("DATABASE_URL", settings.database_url)
    return create_engine(
        url,
        pool_pre_ping=True,
        pool_size=pool_size,
        max_overflow=pool_size,
    )


# ── Test fixtures (created fresh, torn down after) ───────────────────────────

class Fixtures:
    """Creates isolated test data rows and cleans them up after the test."""

    def __init__(self, Session):
        self.Session = Session
        self.teacher_id: str | None = None
        self.session_id: str | None = None
        self.student_ids: list[str] = []
        self._created_user_ids: list[str] = []
        self._created_session_ids: list[str] = []
        self._created_detection_ids: list[int] = []
        self._created_attendance_ids: list[int] = []
        self._created_assignment_ids: list[int] = []
        self._created_division_ids: list[int] = []
        self._created_branch_ids: list[int] = []
        self._created_semester_ids: list[int] = []
        self._created_subject_ids: list[int] = []
        self._created_div_student_ids: list[int] = []

    def create(self, num_students: int):
        db = self.Session()
        try:
            # Branch
            branch = Branch(code=f"ST{uuid.uuid4().hex[:4].upper()}", name="StressTest")
            db.add(branch)
            db.flush()
            self._created_branch_ids.append(branch.id)

            # Division
            div = Division(
                branch_id=branch.id, year=2, div_number=99,
                label="StressDiv",
                start_student_id=None, end_student_id=None,
            )
            db.add(div)
            db.flush()
            self._created_division_ids.append(div.id)

            # Semester
            from datetime import date
            sem = Semester(
                name="StressSem", start_date=date.today(),
                end_date=date.today(), is_active=False,
            )
            db.add(sem)
            db.flush()
            self._created_semester_ids.append(sem.id)

            # Subject
            subj = Subject(code="STR01", name="StressSubject", subject_type="lecture")
            db.add(subj)
            db.flush()
            self._created_subject_ids.append(subj.id)

            # Teacher
            from app.auth import hash_password
            teacher = User(
                id=str(uuid.uuid4()),
                full_name="StressTeacher",
                role=UserRole.teacher,
                teacher_id=f"STRT{uuid.uuid4().hex[:4].upper()}",
                password_hash=hash_password("test"),
            )
            db.add(teacher)
            db.flush()
            self._created_user_ids.append(teacher.id)
            self.teacher_id = teacher.id

            # Assignment
            assignment = TeacherAssignment(
                teacher_user_id=teacher.id,
                subject_id=subj.id,
                division_id=div.id,
                batch_id=None,
            )
            db.add(assignment)
            db.flush()
            self._created_assignment_ids.append(assignment.id)

            # Session
            session = LectureSession(
                id=str(uuid.uuid4()),
                subject="StressTest",
                teacher_user_id=teacher.id,
                assignment_id=assignment.id,
                token="stresstoken",
                is_active=True,
            )
            db.add(session)
            db.flush()
            self._created_session_ids.append(session.id)
            self.session_id = session.id

            # Students
            import re
            for i in range(1, num_students + 1):
                sid = f"ST{i:05d}"
                student = User(
                    id=str(uuid.uuid4()),
                    full_name=f"StressStudent {i}",
                    role=UserRole.student,
                    student_id=sid,
                    password_hash=hash_password("test"),
                )
                db.add(student)
                db.flush()
                self._created_user_ids.append(student.id)
                self.student_ids.append(student.id)

                ds = DivisionStudent(
                    student_user_id=student.id,
                    division_id=div.id,
                    batch_id=None,
                )
                db.add(ds)
                db.flush()
                self._created_div_student_ids.append(ds.id)

            db.commit()
            print(f"[fixtures] Created session={self.session_id}, {num_students} students")
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def teardown(self):
        db = self.Session()
        try:
            if self._created_attendance_ids:
                db.execute(
                    text(f"DELETE FROM attendance WHERE id = ANY(:ids)"),
                    {"ids": self._created_attendance_ids},
                )
            if self._created_detection_ids:
                db.execute(
                    text(f"DELETE FROM detections WHERE id = ANY(:ids)"),
                    {"ids": self._created_detection_ids},
                )
            for sid in self._created_session_ids:
                db.execute(text("DELETE FROM sessions WHERE id = :id"), {"id": sid})
            if self._created_assignment_ids:
                db.execute(
                    text("DELETE FROM teacher_assignments WHERE id = ANY(:ids)"),
                    {"ids": self._created_assignment_ids},
                )
            if self._created_div_student_ids:
                db.execute(
                    text("DELETE FROM division_students WHERE id = ANY(:ids)"),
                    {"ids": self._created_div_student_ids},
                )
            if self._created_user_ids:
                db.execute(
                    text("DELETE FROM users WHERE id = ANY(:ids)"),
                    {"ids": self._created_user_ids},
                )
            if self._created_division_ids:
                db.execute(
                    text("DELETE FROM divisions WHERE id = ANY(:ids)"),
                    {"ids": self._created_division_ids},
                )
            if self._created_branch_ids:
                db.execute(
                    text("DELETE FROM branches WHERE id = ANY(:ids)"),
                    {"ids": self._created_branch_ids},
                )
            if self._created_subject_ids:
                db.execute(
                    text("DELETE FROM subjects WHERE id = ANY(:ids)"),
                    {"ids": self._created_subject_ids},
                )
            if self._created_semester_ids:
                db.execute(
                    text("DELETE FROM semesters WHERE id = ANY(:ids)"),
                    {"ids": self._created_semester_ids},
                )
            db.commit()
            print("[fixtures] Cleaned up test data.")
        except Exception as e:
            db.rollback()
            print(f"[fixtures] Cleanup error (non-fatal): {e}")
        finally:
            db.close()


# ── Test 1: Detection insert throughput ──────────────────────────────────────

def test_detection_inserts(Session, fixtures: Fixtures, workers: int, rounds: int):
    """
    Insert one Detection row per student per round.
    rounds=10 simulates 10 × 30-second windows = 5 minutes of class.
    """
    print(f"\n{'='*56}")
    print(f"TEST 1: Detection insert throughput")
    print(f"  students={len(fixtures.student_ids)}  rounds={rounds}  workers={workers}")
    print(f"{'='*56}")

    latencies: list[float] = []
    errors = 0
    total_inserted = 0

    def insert_one(student_user_id: str) -> float:
        db = Session()
        try:
            t0 = time.monotonic()
            det = Detection(
                session_id=fixtures.session_id,
                student_user_id=student_user_id,
                rssi=-60,
                proximity_ok=True,
            )
            db.add(det)
            db.commit()
            elapsed = time.monotonic() - t0
            fixtures._created_detection_ids.append(det.id)
            return elapsed
        except Exception as e:
            db.rollback()
            raise
        finally:
            db.close()

    wall_start = time.monotonic()

    for rnd in range(1, rounds + 1):
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(insert_one, sid): sid for sid in fixtures.student_ids}
            for future in as_completed(futures):
                try:
                    latencies.append(future.result())
                    total_inserted += 1
                except Exception as e:
                    errors += 1
                    print(f"  [error] {e}")

        if rnd % 2 == 0:
            print(f"  Round {rnd}/{rounds}  cumulative={total_inserted} rows")

    wall_elapsed = time.monotonic() - wall_start

    latencies.sort()
    p50 = statistics.median(latencies) * 1000
    p95 = latencies[int(len(latencies) * 0.95)] * 1000
    p99 = latencies[int(len(latencies) * 0.99)] * 1000
    throughput = total_inserted / wall_elapsed

    print(f"\n  Results:")
    print(f"    Total rows inserted : {total_inserted}")
    print(f"    Errors              : {errors}")
    print(f"    Wall time           : {wall_elapsed:.2f}s")
    print(f"    Throughput          : {throughput:.1f} rows/s")
    print(f"    Latency p50         : {p50:.1f}ms")
    print(f"    Latency p95         : {p95:.1f}ms")
    print(f"    Latency p99         : {p99:.1f}ms")

    # Pass/fail thresholds for a single Postgres instance
    ok = errors == 0 and p95 < 200
    print(f"\n  {'✓ PASS' if ok else '✗ FAIL'}: p95 < 200ms, 0 errors")
    return ok


# ── Test 2: Attendance summary query under concurrent load ───────────────────

def test_summary_query(Session, fixtures: Fixtures, workers: int, query_rounds: int):
    """
    Run the attendance summary query N times concurrently.
    Mirrors: GET /teacher/sessions/{id}/attendance-summary
    which does:
      - SELECT all students in the division
      - For each student: COUNT(detections), SELECT attendance row
    This is an N+1 query pattern — the stress test will expose it if it's slow.
    """
    print(f"\n{'='*56}")
    print(f"TEST 2: Attendance summary query load")
    print(f"  students={len(fixtures.student_ids)}  concurrent_queries={workers}  rounds={query_rounds}")
    print(f"{'='*56}")

    latencies: list[float] = []
    errors = 0

    def run_summary_query() -> float:
        db = Session()
        try:
            t0 = time.monotonic()

            # Mirror _build_summary: fetch all students in division
            students = db.execute(
                select(User)
                .join(DivisionStudent, DivisionStudent.student_user_id == User.id)
                .where(DivisionStudent.division_id == fixtures._created_division_ids[0])
                .order_by(User.student_id)
            ).scalars().all()

            # Per-student detection count + attendance (the N+1 that production does)
            for student in students:
                db.scalar(
                    select(func.count(Detection.id)).where(
                        and_(
                            Detection.session_id == fixtures.session_id,
                            Detection.student_user_id == student.id,
                        )
                    )
                )
                db.scalar(
                    select(Attendance).where(
                        and_(
                            Attendance.session_id == fixtures.session_id,
                            Attendance.student_user_id == student.id,
                        )
                    )
                )

            return time.monotonic() - t0
        except Exception as e:
            raise
        finally:
            db.close()

    wall_start = time.monotonic()

    for rnd in range(1, query_rounds + 1):
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(run_summary_query) for _ in range(workers)]
            for future in as_completed(futures):
                try:
                    latencies.append(future.result())
                except Exception as e:
                    errors += 1
                    print(f"  [error] {e}")

        if rnd % 5 == 0:
            print(f"  Round {rnd}/{query_rounds}  queries so far={len(latencies)}")

    wall_elapsed = time.monotonic() - wall_start

    latencies.sort()
    p50 = statistics.median(latencies) * 1000
    p95 = latencies[int(len(latencies) * 0.95)] * 1000
    p99 = latencies[int(len(latencies) * 0.99)] * 1000

    print(f"\n  Results:")
    print(f"    Total queries run   : {len(latencies)}")
    print(f"    Errors              : {errors}")
    print(f"    Wall time           : {wall_elapsed:.2f}s")
    print(f"    Latency p50         : {p50:.1f}ms")
    print(f"    Latency p95         : {p95:.1f}ms")
    print(f"    Latency p99         : {p99:.1f}ms")

    ok = errors == 0 and p95 < 500
    print(f"\n  {'✓ PASS' if ok else '✗ FAIL'}: p95 < 500ms, 0 errors")
    return ok


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(
        description="Stress-test the DB detection insert and summary query paths.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--students",      type=int, default=70,  help="Students per session")
    p.add_argument("--rounds",        type=int, default=10,  help="Detection insert rounds (each = 1 BLE window)")
    p.add_argument("--query-rounds",  type=int, default=20,  help="Summary query rounds")
    p.add_argument("--workers",       type=int, default=8,   help="Concurrent DB threads")
    p.add_argument("--skip-inserts",  action="store_true",   help="Skip insert test, only run summary query")
    p.add_argument("--skip-summary",  action="store_true",   help="Skip summary query test")
    args = p.parse_args()

    engine = make_engine(pool_size=args.workers + 2)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    fixtures = Fixtures(Session)
    results = {}

    try:
        fixtures.create(args.students)

        if not args.skip_inserts:
            results["inserts"] = test_detection_inserts(
                Session, fixtures, workers=args.workers, rounds=args.rounds
            )

        if not args.skip_summary:
            results["summary"] = test_summary_query(
                Session, fixtures, workers=args.workers, query_rounds=args.query_rounds
            )

    finally:
        fixtures.teardown()

    print(f"\n{'='*56}")
    print("OVERALL RESULT")
    all_pass = all(results.values())
    for name, ok in results.items():
        print(f"  {name:20s}: {'✓ PASS' if ok else '✗ FAIL'}")
    print(f"{'='*56}")
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
