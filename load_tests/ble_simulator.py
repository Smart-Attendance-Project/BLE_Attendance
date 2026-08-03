#!/usr/bin/env python3
"""
BLE Batch Detection Simulator
==============================
Simulates N student phones broadcasting BLE, all from a single machine.

Instead of real Bluetooth, it sends HTTP requests to the backend just like
the teacher's phone does after scanning — using the *teacher* token and the
POST /detections/batch endpoint.  This is the exact payload the real app
submits every 30 seconds.

What it tests
-------------
- The backend's /detections/batch endpoint under concurrent load
- The DB insert path for many detections in one request
- That the server does not crash or queue-overflow when all 30–70 students
  show up in a single 30-second window

Usage
-----
# 1. Make sure the backend is running and seed_full.py has been run.

# 2. Run with defaults (70 students, 4 batch rounds):
    python ble_simulator.py

# 3. Custom options:
    python ble_simulator.py \
        --host http://127.0.0.1:8000 \
        --teacher T001 \
        --password "Pass@123" \
        --students 60 \
        --rounds 6 \
        --interval 30

Environment
-----------
Requires only the stdlib + requests (already in requirements.txt via locust).
Install standalone:  pip install requests
"""

import argparse
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field

import requests

# ── Defaults ────────────────────────────────────────────────────────────────

DEFAULT_HOST = "http://127.0.0.1:8000"
DEFAULT_TEACHER_ID = "T001"
DEFAULT_PASSWORD = "Pass@123"
DEFAULT_NUM_STUDENTS = 70          # match your class size
DEFAULT_ROUNDS = 4                 # number of 30-second BLE windows to simulate
DEFAULT_INTERVAL = 30              # seconds between detection windows
DEFAULT_BATCH_CONCURRENCY = 4      # parallel batch POST threads


# ── Student ID helpers ────────────────────────────────────────────────────────

def generate_student_ids(n: int, start: int = 1) -> list[str]:
    """Return n student IDs in the format seeded by seed_full.py."""
    return [f"25CE{i:03d}" for i in range(start, start + n)]


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class SimStudent:
    student_id: str
    # running hit counter (increments each round they're "in range")
    hits: int = 0
    # simulated RSSI (-50 = good, -90 = out of range)
    rssi: int = field(default_factory=lambda: random.randint(-75, -45))
    in_range: bool = True

    def tick(self):
        """Simulate one 30-second BLE window."""
        self.rssi = random.randint(-90, -40)
        self.in_range = self.rssi > -75
        if self.in_range:
            self.hits += 1


# ── Simulator core ────────────────────────────────────────────────────────────

class BleSimulator:
    def __init__(
        self,
        host: str,
        teacher_id: str,
        password: str,
        student_ids: list[str],
        rounds: int,
        interval: float,
        batch_concurrency: int,
    ):
        self.host = host.rstrip("/")
        self.teacher_id = teacher_id
        self.password = password
        self.students = [SimStudent(sid) for sid in student_ids]
        self.rounds = rounds
        self.interval = interval
        self.batch_concurrency = batch_concurrency
        self.session = requests.Session()
        self.token: str | None = None
        self.session_id: str | None = None
        self.assignment_id: int | None = None

        # Stats
        self.total_sent = 0
        self.total_recorded = 0
        self.total_errors = 0
        self.round_latencies: list[float] = []

    # ── auth / session management ─────────────────────────────────────────────

    def login(self):
        resp = self.session.post(
            f"{self.host}/auth/login",
            json={"identifier": self.teacher_id, "password": self.password},
            timeout=10,
        )
        resp.raise_for_status()
        self.token = resp.json()["access_token"]
        print(f"[login] Teacher '{self.teacher_id}' authenticated.")

    def _headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    def _pick_assignment(self):
        resp = self.session.get(
            f"{self.host}/teacher/me/assignments",
            headers=self._headers(),
            timeout=10,
        )
        resp.raise_for_status()
        assignments = resp.json()
        if not assignments:
            raise RuntimeError(
                "No teacher assignments found. Run seed_full.py first."
            )
        self.assignment_id = assignments[0]["id"]
        print(f"[setup] Using assignment_id={self.assignment_id}")

    def start_session(self):
        resp = self.session.post(
            f"{self.host}/sessions",
            json={"subject": "BLE-Sim-LoadTest", "assignment_id": self.assignment_id},
            headers=self._headers(),
            timeout=10,
        )
        if resp.status_code == 409:
            # A session is already running (maybe from a previous test run).
            # Grab its ID from the active session endpoint.
            print("[setup] Session already active, re-using it.")
            active = self.session.get(
                f"{self.host}/sessions/active",
                headers=self._headers(),
                timeout=10,
            )
            active.raise_for_status()
            self.session_id = active.json()["id"]
        else:
            resp.raise_for_status()
            self.session_id = resp.json()["id"]
        print(f"[session] session_id={self.session_id}")

    def end_session(self):
        if self.session_id is None:
            return
        resp = self.session.post(
            f"{self.host}/sessions/{self.session_id}/end",
            headers=self._headers(),
            timeout=10,
        )
        if resp.status_code in (200, 404):
            print(f"[session] Ended session {self.session_id}.")
        else:
            print(f"[session] Could not end session: {resp.status_code} {resp.text}")

    # ── batch submission ──────────────────────────────────────────────────────

    def _build_batch_payload(self, students_in_range: list[SimStudent]) -> dict:
        """
        Mirrors the BatchDetectionIn schema:
          { detections: [ { session_id, student_identifier, rssi, proximity_ok }, ... ] }
        """
        return {
            "detections": [
                {
                    "session_id": self.session_id,
                    "student_identifier": s.student_id,
                    "rssi": s.rssi,
                    "proximity_ok": s.in_range,
                }
                for s in students_in_range
            ]
        }

    def _send_batch_chunk(self, chunk: list[SimStudent]) -> tuple[int, int]:
        """POST one chunk to /detections/batch. Returns (sent, recorded)."""
        payload = self._build_batch_payload(chunk)
        try:
            resp = self.session.post(
                f"{self.host}/detections/batch",
                json=payload,
                headers=self._headers(),
                timeout=15,
            )
            if resp.status_code == 200:
                recorded = int(
                    resp.json().get("message", "0 detections").split()[0]
                )
                return len(chunk), recorded
            else:
                print(
                    f"  [warn] batch chunk returned {resp.status_code}: {resp.text[:120]}"
                )
                return len(chunk), 0
        except requests.exceptions.RequestException as exc:
            print(f"  [error] batch chunk failed: {exc}")
            self.total_errors += 1
            return len(chunk), 0

    def _submit_detections_for_round(self, round_num: int, total_windows: int):
        """
        Simulate all students broadcasting in parallel chunks.
        Splits the student list into batch_concurrency chunks and fires them
        concurrently — mirrors what happens when all 70 students are in BLE
        range simultaneously and the teacher's phone scans them in rapid
        succession.
        """
        # Tick every student's simulated state
        for s in self.students:
            s.tick()
            s.hits = min(s.hits, total_windows)  # cap hits to realistic window

        in_range = [s for s in self.students if s.in_range]
        absent = len(self.students) - len(in_range)

        print(
            f"\n[round {round_num}/{self.rounds}] "
            f"In-range: {len(in_range)}/{len(self.students)}  "
            f"Absent: {absent}"
        )

        if not in_range:
            print("  All students out of range this round, skipping batch.")
            return

        # Split into chunks for concurrent posting
        chunk_size = max(1, len(in_range) // self.batch_concurrency)
        chunks = [
            in_range[i : i + chunk_size]
            for i in range(0, len(in_range), chunk_size)
        ]

        t0 = time.monotonic()
        with ThreadPoolExecutor(max_workers=self.batch_concurrency) as pool:
            futures = {pool.submit(self._send_batch_chunk, chunk): chunk for chunk in chunks}
            for future in as_completed(futures):
                sent, recorded = future.result()
                self.total_sent += sent
                self.total_recorded += recorded

        elapsed = time.monotonic() - t0
        self.round_latencies.append(elapsed)
        print(
            f"  Batch POST(s) completed in {elapsed:.2f}s  "
            f"sent={sum(len(c) for c in chunks)}  "
            f"cumulative_recorded={self.total_recorded}"
        )

    # ── main run loop ─────────────────────────────────────────────────────────

    def run(self):
        print("=" * 60)
        print("BLE Detection Simulator")
        print(f"  host        : {self.host}")
        print(f"  students    : {len(self.students)} ({self.students[0].student_id} … {self.students[-1].student_id})")
        print(f"  rounds      : {self.rounds}")
        print(f"  interval    : {self.interval}s")
        print(f"  concurrency : {self.batch_concurrency} parallel batches")
        print("=" * 60)

        try:
            self.login()
            self._pick_assignment()
            self.start_session()

            for rnd in range(1, self.rounds + 1):
                self._submit_detections_for_round(rnd, total_windows=rnd)
                if rnd < self.rounds:
                    print(f"  Waiting {self.interval}s until next window…")
                    time.sleep(self.interval)

        except KeyboardInterrupt:
            print("\n[interrupted] Stopping early…")
        except Exception as exc:
            print(f"[fatal] {exc}", file=sys.stderr)
            raise
        finally:
            self.end_session()
            self._print_summary()

    def _print_summary(self):
        print("\n" + "=" * 60)
        print("Simulation complete")
        print(f"  Detections sent    : {self.total_sent}")
        print(f"  Detections recorded: {self.total_recorded}")
        print(f"  Errors             : {self.total_errors}")
        if self.round_latencies:
            avg = sum(self.round_latencies) / len(self.round_latencies)
            worst = max(self.round_latencies)
            print(f"  Avg batch latency  : {avg:.2f}s")
            print(f"  Worst batch latency: {worst:.2f}s")
        if self.total_sent > 0:
            drop = (self.total_sent - self.total_recorded) / self.total_sent * 100
            print(f"  Drop rate          : {drop:.1f}%")
        print("=" * 60)


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(
        description="Simulate N student BLE beacons against the backend.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--host", default=DEFAULT_HOST, help="Backend base URL")
    p.add_argument("--teacher", default=DEFAULT_TEACHER_ID, help="Teacher login ID")
    p.add_argument("--password", default=DEFAULT_PASSWORD, help="Teacher password")
    p.add_argument(
        "--students",
        type=int,
        default=DEFAULT_NUM_STUDENTS,
        help="Number of students to simulate",
    )
    p.add_argument(
        "--student-start",
        type=int,
        default=1,
        metavar="N",
        help="Starting index for student IDs (25CE{N:03d})",
    )
    p.add_argument(
        "--rounds",
        type=int,
        default=DEFAULT_ROUNDS,
        help="Number of 30-second BLE windows to simulate",
    )
    p.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="Seconds to wait between rounds (use 0 for stress test)",
    )
    p.add_argument(
        "--concurrency",
        type=int,
        default=DEFAULT_BATCH_CONCURRENCY,
        help="Parallel batch POST threads per round",
    )
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    student_ids = generate_student_ids(args.students, start=args.student_start)
    sim = BleSimulator(
        host=args.host,
        teacher_id=args.teacher,
        password=args.password,
        student_ids=student_ids,
        rounds=args.rounds,
        interval=args.interval,
        batch_concurrency=args.concurrency,
    )
    sim.run()
