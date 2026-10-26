"""
Backend load test — locust
==========================
Simulates a real class session with:
  - 1 teacher  → starts session, polls summary every 30 s, ends session
  - N students → login, poll active session, submit detections every 30 s,
                 finalize attendance at the end

Usage (see README in this directory):
    locust -f locustfile.py --host http://127.0.0.1:8000

Tune with --users / --spawn-rate, e.g.:
    locust -f locustfile.py --host http://127.0.0.1:8000 \
           --users 71 --spawn-rate 5 --run-time 5m --headless
"""

import random
import time
from locust import HttpUser, TaskSet, between, events, task

# ── Seed credentials (must match seed_full.py) ────────────────────────────────
TEACHER_ID = "T001"
TEACHER_PW = "Pass@123"

# Students 25CE001 … 25CE070 seeded by seed_full.py
NUM_STUDENTS = 70
STUDENT_IDS = [f"25CE{n:03d}" for n in range(1, NUM_STUDENTS + 1)]
STUDENT_PW = "Pass@123"

# Track the shared active session id across users
_shared_session_id: str | None = None
_shared_session_token: str | None = None


# ── Teacher behaviour ─────────────────────────────────────────────────────────

class TeacherTasks(TaskSet):
    """
    Teacher lifecycle:
    1. login
    2. GET today's schedule → pick first slot
    3. POST /sessions  (start)
    4. Poll /teacher/sessions/{id}/attendance-summary every 30 s
    5. After a while, POST open-finalization
    6. POST /sessions/{id}/end
    """

    token: str = ""
    session_id: str | None = None
    assignment_id: int | None = None

    def on_start(self):
        self._login()
        self._pick_assignment()

    # ── helpers ──────────────────────────────────────────────────────────────

    def _login(self):
        with self.client.post(
            "/auth/login",
            json={"identifier": TEACHER_ID, "password": TEACHER_PW},
            name="/auth/login [teacher]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                self.token = resp.json().get("access_token", "")
            else:
                resp.failure(f"Teacher login failed: {resp.status_code}")

    def _headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    def _pick_assignment(self):
        """Grab the first assignment available for this teacher."""
        resp = self.client.get(
            "/teacher/me/assignments",
            headers=self._headers(),
            name="/teacher/me/assignments",
        )
        if resp.status_code == 200:
            assignments = resp.json()
            if assignments:
                self.assignment_id = assignments[0]["id"]

    # ── tasks ─────────────────────────────────────────────────────────────────

    @task(1)
    def full_session_lifecycle(self):
        global _shared_session_id, _shared_session_token
        if self.assignment_id is None:
            self._pick_assignment()
            return

        # --- Start session ---
        with self.client.post(
            "/sessions",
            json={"subject": "LoadTest", "assignment_id": self.assignment_id},
            headers=self._headers(),
            name="/sessions [start]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                self.session_id = data["id"]
                _shared_session_id = self.session_id
                _shared_session_token = data.get("token")
            elif resp.status_code == 409:
                # Another teacher already has an active session in the test run —
                # just re-use the existing one for the summary poll below.
                self.session_id = _shared_session_id
                resp.success()
            else:
                resp.failure(f"Start session failed: {resp.status_code} {resp.text}")
                return

        if self.session_id is None:
            return

        # --- Poll summary several times (simulates teacher phone polling) ---
        for _ in range(3):
            self.client.get(
                f"/teacher/sessions/{self.session_id}/attendance-summary",
                headers=self._headers(),
                name="/teacher/sessions/{id}/attendance-summary",
            )
            time.sleep(2)

        # --- Open finalization ---
        self.client.post(
            f"/teacher/sessions/{self.session_id}/open-finalization",
            headers=self._headers(),
            name="/teacher/sessions/{id}/open-finalization",
        )

        time.sleep(2)

        # --- End session ---
        with self.client.post(
            f"/sessions/{self.session_id}/end",
            headers=self._headers(),
            name="/sessions/{id}/end",
            catch_response=True,
        ) as resp:
            if resp.status_code in (200, 404):
                resp.success()
                _shared_session_id = None
            else:
                resp.failure(f"End session failed: {resp.status_code}")

        self.session_id = None
        # Pause before next cycle so students have time to interact
        time.sleep(30)

    @task(3)
    def poll_summary(self):
        sid = self.session_id or _shared_session_id
        if sid is None:
            return
        self.client.get(
            f"/teacher/sessions/{sid}/attendance-summary",
            headers=self._headers(),
            name="/teacher/sessions/{id}/attendance-summary",
        )

    @task(2)
    def get_today_schedule(self):
        self.client.get(
            "/teacher/me/schedule/today/slots",
            headers=self._headers(),
            name="/teacher/me/schedule/today/slots",
        )


# ── Student behaviour ─────────────────────────────────────────────────────────

class StudentTasks(TaskSet):
    """
    Student lifecycle (mirrors real app behaviour):
    1. login
    2. GET /sessions/active   → wait for an active session
    3. POST /detections        every ~30 s while session is open
    4. POST /attendance/finalize  when finalization_open == True
    """

    token: str = ""
    student_id_str: str = ""
    user_id: str = ""
    session_id: str | None = None
    finalization_done: bool = False
    detection_count: int = 0

    def on_start(self):
        # Each user picks a random student from the pool
        self.student_id_str = random.choice(STUDENT_IDS)
        self._login()

    def _login(self):
        with self.client.post(
            "/auth/login",
            json={"identifier": self.student_id_str, "password": STUDENT_PW},
            name="/auth/login [student]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                self.token = data.get("access_token", "")
                self.user_id = data.get("user_id", "")
            else:
                resp.failure(f"Student login failed ({self.student_id_str}): {resp.status_code}")

    def _headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    @task(5)
    def poll_and_detect(self):
        """Poll for active session, then send a detection if one exists."""
        with self.client.get(
            "/sessions/active",
            headers=self._headers(),
            name="/sessions/active [student]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 404:
                # No session yet — normal
                resp.success()
                self.session_id = None
                self.finalization_done = False
                self.detection_count = 0
                return
            elif resp.status_code != 200:
                resp.failure(f"Active session poll: {resp.status_code}")
                return

            data = resp.json()
            self.session_id = data["id"]
            finalization_open = data.get("finalization_open", False)

        # Send a detection
        if self.session_id:
            rssi = random.randint(-80, -45)
            proximity_ok = rssi > -75
            with self.client.post(
                "/detections",
                json={
                    "session_id": self.session_id,
                    "rssi": rssi,
                    "proximity_ok": proximity_ok,
                },
                headers=self._headers(),
                name="/detections [student]",
                catch_response=True,
            ) as resp:
                if resp.status_code in (200, 403, 404):
                    resp.success()
                    if resp.status_code == 200:
                        self.detection_count += 1
                else:
                    resp.failure(f"Detection failed: {resp.status_code}")

        # Finalize if allowed and not already done
        if (
            self.session_id
            and finalization_open
            and not self.finalization_done
            and self.detection_count >= 3
        ):
            with self.client.post(
                "/attendance/finalize",
                json={
                    "session_id": self.session_id,
                    "biometric_verified": random.random() > 0.1,  # 90 % pass biometric
                },
                headers=self._headers(),
                name="/attendance/finalize [student]",
                catch_response=True,
            ) as resp:
                if resp.status_code in (200, 409, 403, 404):
                    resp.success()
                    if resp.status_code == 200:
                        self.finalization_done = True
                else:
                    resp.failure(f"Finalize failed: {resp.status_code}")

    @task(1)
    def refresh_me(self):
        """Background auth token validation — students call /auth/me on app resume."""
        self.client.get(
            "/auth/me",
            headers=self._headers(),
            name="/auth/me [student]",
        )


# ── User classes ──────────────────────────────────────────────────────────────

class TeacherUser(HttpUser):
    tasks = [TeacherTasks]
    weight = 1
    wait_time = between(1, 3)


class StudentUser(HttpUser):
    tasks = [StudentTasks]
    weight = 70  # 70 students per 1 teacher
    wait_time = between(25, 35)  # mirrors the real 30 s detection interval


# ── Event hooks for a tidy summary ───────────────────────────────────────────

@events.quitting.add_listener
def on_quit(environment, **kwargs):
    stats = environment.stats
    print("\n=== Load Test Summary ===")
    for name, entry in stats.entries.items():
        if entry.num_requests == 0:
            continue
        fail_pct = (entry.num_failures / entry.num_requests * 100) if entry.num_requests else 0
        print(
            f"  {name[1]:50s}  "
            f"reqs={entry.num_requests:5d}  "
            f"fails={entry.num_failures:4d} ({fail_pct:5.1f}%)  "
            f"p50={entry.get_response_time_percentile(0.50):5.0f}ms  "
            f"p95={entry.get_response_time_percentile(0.95):5.0f}ms"
        )
