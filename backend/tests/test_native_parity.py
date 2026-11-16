"""Exercise the Python and Go HTTP APIs against separate PostgreSQL schemas."""

import io
import json
import os
import socket
import subprocess
import sys
import time
from contextlib import ExitStack, contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from statistics import median
from urllib.error import HTTPError
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from uuid import UUID, uuid4

import psycopg
import pytest
from jose import jwt
from openpyxl import load_workbook
from passlib.hash import pbkdf2_sha256
from psycopg import sql


BACKEND = Path(__file__).resolve().parents[1]
NATIVE = BACKEND / "build/native/attendance-api"
SECRET = "synthetic-parity-test-secret"
PASSWORD = "ParityOnly-Password"
ADMIN = "PARITYADMIN"
ADMIN_USER_ID = "synthetic-admin-user-id"


def database_url(base, schema, implementation):
    parsed = urlsplit(base)
    query = parse_qsl(parsed.query, keep_blank_values=True)
    query.append(("options", f"-c search_path={schema}"))
    scheme = "postgresql+psycopg" if implementation == "Python" else "postgresql"
    return urlunsplit((scheme, parsed.netloc, parsed.path, urlencode(query, quote_via=quote), ""))


@contextmanager
def isolated_schema(base):
    name = f"attendance_parity_{uuid4().hex}"
    with psycopg.connect(base, autocommit=True) as connection:
        connection.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(name)))
        try:
            yield name
        finally:
            connection.execute(sql.SQL("DROP SCHEMA {} CASCADE").format(sql.Identifier(name)))


def send(base, method, path, token=None, payload=None, extra_headers=None):
    data, headers = None, dict(extra_headers or {})
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(base + path, data=data, headers=headers, method=method)
    try:
        response = urlopen(request, timeout=10)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read()


@contextmanager
def server(implementation, base, schema):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = {
        **os.environ,
        "DATABASE_URL_OVERRIDE": database_url(base, schema, implementation),
        "JWT_SECRET": SECRET,
        "JWT_ALGORITHM": "HS256",
        "JWT_EXP_MINUTES": "480",
        "HOST": "127.0.0.1",
        "PORT": str(port),
    }
    cmd = [str(NATIVE)]
    if implementation == "Python":
        cmd = [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", str(port), "--no-access-log"]
    process = subprocess.Popen(cmd, cwd=BACKEND, env=env)
    try:
        origin = f"http://127.0.0.1:{port}"
        for _ in range(100):
            if process.poll() is not None:
                pytest.fail(f"{implementation} exited with {process.returncode}")
            try:
                if send(origin, "GET", "/health")[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(0.05)
        else:
            pytest.fail(f"{implementation} failed to start")
        with psycopg.connect(database_url(base, schema, "Go")) as connection:
            connection.execute(
                """INSERT INTO users
                (id,full_name,role,admin_id,password_hash,biometric_enabled,is_super_admin,created_at)
                VALUES (%s,'Migration Fixture','admin',%s,%s,false,true,now())""",
                (ADMIN_USER_ID, ADMIN, pbkdf2_sha256.hash(PASSWORD)),
            )
        yield origin
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


class Scenario:
    def __init__(self, base, implementation, database):
        self.base = base
        self.database = database
        self.implementation = implementation
        self.ids = {}
        self.tokens = {}
        self.operations = set()
        self.responses = []

    def normalize(self, value):
        if isinstance(value, list):
            return [self.normalize(child) for child in value]
        if isinstance(value, dict):
            normalized = {}
            for key, item in value.items():
                if isinstance(item, str) and key in {"starts_at", "ends_at", "detected_at"}:
                    assert datetime.fromisoformat(item).tzinfo is None
                    item = f"<{key}>"
                normalized[key] = self.normalize(item)
            return normalized
        if isinstance(value, str):
            return next(
                (f"<{name}>" for name, identity in self.ids.items() if identity == value),
                value,
            )
        return value

    def call(self, method, route, *, actor=None, payload=None, query=None, status=200, remember=None):
        path = route.format_map(self.ids)
        if query:
            path += "?" + urlencode(query)
        code, headers, raw = send(self.base, method, path, self.tokens.get(actor), payload)
        assert code == status, (self.implementation, method, path, status, code, raw)
        content_type = headers["Content-Type"]
        metadata = {}
        for name in ("Content-Disposition", "WWW-Authenticate"):
            if name in headers:
                metadata[name] = headers[name]
        if content_type.startswith("application/json"):
            value = json.loads(raw)
            if remember:
                if "access_token" in value:
                    self.tokens[remember] = value.pop("access_token")
                    claims = jwt.decode(self.tokens[remember], SECRET, algorithms=["HS256"])
                    assert claims["sub"] == value["user_id"]
                    assert claims["exp"] > time.time()
                    value["access_token"] = "<valid token>"
                else:
                    identity = value["id"]
                    if isinstance(identity, str):
                        assert str(UUID(identity)) == identity
                    self.ids[remember] = identity
                    if "token" in value:
                        assert len(bytes.fromhex(value["token"])) == 8
                        self.ids["session-token"] = value["token"]
        elif content_type.startswith("application/vnd.openxmlformats"):
            workbook = load_workbook(io.BytesIO(raw), read_only=True)
            try:
                assert workbook.sheetnames == ["Attendance"]
                value = [list(row) for row in workbook.active.values]
            finally:
                workbook.close()
        else:
            value = raw
        self.operations.add((method, route))
        self.responses.append((method, route, code, content_type, metadata, self.normalize(value)))
        return value

    def login(self, identifier, label):
        return self.call(
            "POST", "/auth/login", payload={"identifier": identifier, "password": PASSWORD},
            remember=label,
        )

    def run(self):
        call = self.call
        assert call("GET", "/health") == {"status": "ok"}
        for path in ("/docs", "/redoc", "/docs/oauth2-redirect"):
            assert call("GET", path)
        contract = call("GET", "/openapi.json")
        call("GET", "/auth/me", status=401)
        call("GET", "/missing", status=404)
        call("POST", "/auth/login", payload={"identifier": ADMIN}, status=422)
        call("POST", "/auth/login", payload={"identifier": ADMIN, "password": "incorrect"}, status=401)
        admin = self.login(ADMIN, "admin")
        assert admin["role"] == "admin"
        assert call("GET", "/auth/me", actor="admin")["is_super_admin"]

        teacher_id = "PARITY01"
        teacher = call("POST", "/admin/teachers", actor="admin", payload={
            "full_name": "Parity Teacher", "teacher_id": teacher_id, "password": PASSWORD,
        }, remember="teacher_user")
        assert call("GET", "/admin/teachers", actor="admin")[0]["teacher_id"] == teacher_id
        self.login(teacher_id, "teacher")
        call("GET", "/admin/admins", actor="teacher", status=403)
        call("POST", "/admin/admins", actor="admin", payload={
            "full_name": "Parity Admin", "admin_id": "PARITY02", "password": PASSWORD,
        }, remember="new_admin")
        call("GET", "/admin/admins", actor="admin")
        call("POST", "/auth/register", payload={
            "full_name": "Parity Student", "role": "student", "identifier": "25CE001", "password": PASSWORD,
        }, remember="student_user")
        call("POST", "/auth/register", payload={
            "full_name": "Parity Student", "role": "student", "identifier": "25CE001", "password": PASSWORD,
        }, status=409)
        call("POST", "/auth/register", payload={
            "full_name": "Too short", "role": "invalid", "identifier": "?", "password": "bad",
        }, status=422)
        self.login("25CE001", "student")
        call("POST", "/auth/change-password", actor="student", payload={
            "old_password": "wrong", "new_password": "another-password",
        }, status=400)
        call("POST", "/auth/change-password", actor="student", payload={
            "old_password": PASSWORD, "new_password": "another-password",
        })
        call("POST", "/auth/login", payload={"identifier": "25CE001", "password": "another-password"}, remember="student")
        call("GET", "/auth/face-profile", actor="student", status=404)
        call("POST", "/auth/register-face", actor="student", payload={"embedding": [0.12, 0.24]})
        call("POST", "/auth/re-register-face", actor="student", payload={"embedding": [0.13]}, status=422)
        call("POST", "/auth/re-register-face", actor="student", payload={"embedding": [1.12, 1.24]}, status=400)
        call("POST", "/auth/re-register-face", actor="student", payload={"embedding": [0.13, 0.25]})
        assert call("GET", "/auth/face-profile", actor="student")["embedding"] == [[0.12, 0.24], [0.13, 0.25]]

        semester = call("POST", "/admin/semesters", actor="admin", payload={
            "name": "Parity Semester", "start_date": "2026-01-01", "end_date": "2030-12-31",
        }, remember="semester")
        call("PATCH", "/admin/semesters/{semester}/activate", actor="admin")
        assert call("GET", "/admin/semesters", actor="student")[0]["is_active"]
        branch = call("POST", "/admin/branches", actor="admin", payload={
            "code": "CE", "name": "Computing",
        }, remember="branch")
        call("GET", "/admin/branches", actor="student")
        division = call("POST", "/admin/divisions", actor="admin", payload={
            "branch_id": branch["id"], "year": 1, "div_number": 1, "label": "Parity Division",
            "start_student_id": "25CE001", "end_student_id": "25CE002",
        }, remember="division")
        assert call("GET", "/admin/divisions", actor="teacher", query={"branch_id": branch["id"]}) == [division]
        call("GET", "/admin/divisions", actor="teacher", query={"branch_id": "invalid"}, status=422)
        batch = call("POST", "/admin/batches", actor="admin", payload={
            "division_id": division["id"], "label": "Parity",
        }, remember="batch")
        call("GET", "/admin/batches", actor="teacher", query={"division_id": division["id"]})
        subject = call("POST", "/admin/subjects", actor="admin", payload={"code": "PAR", "name": "Parity"}, remember="subject")
        call("GET", "/admin/subjects", actor="teacher")
        assignment_data = {"teacher_user_id": teacher["id"], "subject_id": subject["id"], "division_id": division["id"]}
        call("POST", "/admin/assignments", actor="admin", payload=assignment_data, remember="unused_assignment")
        call("DELETE", "/admin/assignments/{unused_assignment}", actor="admin")
        assignment = call("POST", "/admin/assignments", actor="admin",
                          payload={**assignment_data, "batch_id": batch["id"]}, remember="assignment")
        call("GET", "/admin/assignments", actor="student", query={"teacher_id": teacher["id"]})
        call("GET", "/teacher/me/assignments", actor="teacher")
        slot = {
            "assignment_id": assignment["id"], "semester_id": semester["id"],
            "day_of_week": datetime.now(timezone(timedelta(hours=5, minutes=30))).weekday(),
            "time_start": "09:00", "time_end": "10:00", "room": "R1",
        }
        call("POST", "/admin/schedule-slots", actor="admin", payload=slot, remember="slot")
        call("PUT", "/admin/schedule-slots/{slot}", actor="admin", payload={**slot, "room": "R2"})
        call("GET", "/admin/schedule-slots", actor="student", query={"semester_id": semester["id"]})
        call("GET", "/teacher/me/schedule/today", actor="teacher")
        assert call("GET", "/teacher/me/schedule/today/slots", actor="teacher")[0]["room"] == "R2"
        call("DELETE", "/admin/schedule-slots/{slot}", actor="admin")
        call("DELETE", "/admin/schedule-slots/{slot}", actor="admin", status=404)

        call("POST", "/teacher/students", actor="teacher", payload={
            "full_name": "Second Student", "student_id": "25CE002", "password": PASSWORD,
            "division_id": division["id"], "batch_id": batch["id"],
        }, remember="second")
        call("POST", "/admin/students", actor="admin", payload={
            "full_name": "Third Student", "student_id": "25CE003", "password": PASSWORD,
            "division_id": division["id"], "batch_id": batch["id"],
        }, remember="third")
        call("POST", "/admin/division-students", actor="admin", payload={
            "student_user_id": self.ids["student_user"], "division_id": division["id"], "batch_id": batch["id"],
        })
        call("GET", "/teacher/me/divisions", actor="teacher")
        assert len(call("GET", "/teacher/divisions/{division}/students", actor="teacher")) == 3
        assert call("POST", "/auth/login", payload={"identifier": "25CE001", "password": "another-password"},
                    remember="student")["division_ids"] == [division["id"]]
        self.login("25CE002", "second")
        self.login("25CE003", "third")

        call("GET", "/sessions/active", actor="student", status=404)
        call("POST", "/sessions", actor="teacher", payload={"subject": "Parity"}, status=422)
        session_body = {"subject": "Parity Lecture", "assignment_id": assignment["id"]}
        session = call("POST", "/sessions", actor="teacher", payload=session_body, remember="session")
        call("POST", "/sessions", actor="teacher", payload=session_body, status=409)
        active = call("GET", "/sessions/active", actor="student")
        assert active["id"] == session["id"] and active["batch_id"] == batch["id"]
        report_path = "/teacher/sessions/{session}/attendance-summary"
        teacher_prefix = "/teacher/sessions/{session}"
        call("POST", "/attendance/finalize", actor="student", payload={"session_id": session["id"]}, status=409)
        call("POST", teacher_prefix + "/open-finalization", actor="teacher")
        call("POST", "/detections", actor="student", payload={"session_id": session["id"], "rssi": -51})
        batch_response = call("POST", "/detections/batch", actor="teacher", payload={"detections": [
            {"session_id": session["id"], "student_identifier": "25CE002", "rssi": -61},
            {"session_id": session["id"], "student_identifier": "25CE003", "rssi": -67},
            {"session_id": session["id"], "student_identifier": "25CE999", "rssi": -65},
        ]})
        assert batch_response["message"] == "1 detections recorded"
        assert len(call("GET", teacher_prefix + "/detections", actor="teacher")) == 2
        call("POST", "/attendance/finalize", actor="student", payload={
            "session_id": session["id"], "biometric_verified": True,
        })
        call("POST", teacher_prefix + "/attendance/batch-submit", actor="teacher", payload=[
            {"student_id": "25CE002", "is_present": False},
            {"student_id": "25CE002", "is_present": True},
            {"student_id": "25CE999", "is_present": True},
        ])
        assert call("GET", report_path, actor="teacher")["present_students"] == 2
        call("POST", teacher_prefix + "/attendance/override", actor="teacher", payload={
            "student_user_id": self.ids["second"], "is_present": False, "reason": "Test correction",
        })
        call("POST", "/admin/sessions/{session}/attendance/override", actor="admin", payload={
            "student_user_id": self.ids["second"], "is_present": True, "reason": "Test correction",
        })
        call("POST", teacher_prefix + "/lock", actor="teacher")
        call("POST", teacher_prefix + "/attendance/batch-submit", actor="teacher", payload=[], status=409)
        call("POST", "/sessions/{session}/end", actor="teacher")
        assert call("GET", report_path, actor="teacher")["present_students"] == 2
        dates = {"assignment_id": assignment["id"], "from_date": "2000-01-01", "to_date": "2099-12-31"}
        call("GET", "/teacher/me/sessions", actor="teacher", query=dates)
        export = call("GET", "/teacher/attendance/export", actor="teacher", query=dates)
        assert export[1:] == [["25CE001", "P"], ["25CE002", "P"], ["25CE003", "A"]]
        call("GET", "/teacher/attendance/export", actor="teacher", query={"assignment_id": "bad"}, status=422)

        # Normalize the IDs used by the reference OpenAPI template only for coverage.
        contract_operations = {
            (method.upper(), route) for route, endpoints in contract["paths"].items()
            for method in endpoints
        }
        aliases = {"semester": "sem_id", "slot": "slot_id", "unused_assignment": "assignment_id",
                   "division": "division_id", "session": "session_id"}
        exercised = set(self.operations)
        for method, route in self.operations:
            for label, parameter in aliases.items():
                route = route.replace("{" + label + "}", "{" + parameter + "}")
            exercised.add((method, route))
        assert contract_operations <= exercised, contract_operations - exercised

        if os.getenv("NATIVE_PARITY_BENCHMARK") == "1":
            self.benchmark(report_path, dates)
        return self.responses

    def benchmark(self, report_path, dates):
        session_id = self.ids["session"]
        with psycopg.connect(self.database) as connection:
            connection.execute(
                """INSERT INTO users (id,full_name,role,student_id,password_hash,biometric_enabled,is_super_admin,created_at)
                SELECT 'benchmark-student-'||n,'Synthetic Student '||n,'student',
                    '26CE'||lpad(n::text,3,'0'),'benchmark-only',false,false,CURRENT_TIMESTAMP
                FROM generate_series(1,67) AS n"""
            )
            connection.execute(
                """INSERT INTO division_students (student_user_id,division_id,batch_id)
                SELECT id,%s,%s FROM users WHERE id LIKE 'benchmark-student-%%'""",
                (self.ids["division"], self.ids["batch"]),
            )
            connection.execute(
                """INSERT INTO sessions (id,subject,teacher_user_id,assignment_id,token,
                    starts_at,ends_at,is_active,finalization_open,attendance_locked)
                SELECT 'benchmark-session-'||n,'Synthetic Session',%s,%s,'benchmark-only',
                    now()-n*interval '1 day',now()-n*interval '1 day'+interval '30 minutes',false,false,true
                FROM generate_series(1,19) AS n""",
                (self.ids["teacher_user"], self.ids["assignment"]),
            )
            connection.execute(
                """INSERT INTO attendance (session_id,student_user_id,presence_ratio,is_present,
                    biometric_verified,overridden_by_teacher)
                SELECT s.id,u.id,1,true,true,false FROM sessions s CROSS JOIN users u
                WHERE s.id LIKE 'benchmark-session-%%' AND u.role='student'"""
            )
            connection.execute(
                """INSERT INTO detections (session_id,student_user_id,rssi,proximity_ok,detected_at)
                SELECT %s,u.id,-55,true,now()-n*interval '30 seconds'
                FROM users u CROSS JOIN generate_series(1,60) AS n WHERE u.role='student'""",
                (session_id,),
            )
        target_paths = (
            report_path.format_map(self.ids),
            "/teacher/attendance/export?" + urlencode(dates),
        )
        for target in target_paths:
            samples = []
            for index in range(120):
                start = time.perf_counter_ns()
                assert send(self.base, "GET", target, self.tokens["teacher"])[0] == 200
                if index >= 20:
                    samples.append((time.perf_counter_ns() - start) / 1_000_000)
            print(f"{self.implementation} {target.split('?')[0]}: median={median(samples):.2f} ms p95={sorted(samples)[94]:.2f} ms")


def test_native_http_parity():
    base = os.getenv("NATIVE_PARITY_DATABASE_URL")
    if not base:
        pytest.skip("Set NATIVE_PARITY_DATABASE_URL to a PostgreSQL test database")
    assert NATIVE.is_file(), "Build the native backend with scripts/build_native.sh"
    with ExitStack() as stack:
        scenarios = []
        for implementation in ("Python", "Go"):
            schema = stack.enter_context(isolated_schema(base))
            origin = stack.enter_context(server(implementation, base, schema))
            scenarios.append(Scenario(origin, implementation, database_url(base, schema, "Go")))
        reference, port = scenarios
        expected, actual = reference.run(), port.run()
        assert len(expected) == len(actual)
        for before, after in zip(expected, actual):
            assert before == after, (before[:3], after[:3])
        # Both servers accept tokens from the other with the same production-style JWT configuration.
        for issuer, recipient in ((reference, port), (port, reference)):
            status, _, body = send(recipient.base, "GET", "/auth/me", issuer.tokens["admin"])
            assert status == 200
            assert json.loads(body)["id"] == ADMIN_USER_ID


def test_native_migrates_legacy_postgresql_schema():
    base = os.getenv("NATIVE_PARITY_DATABASE_URL")
    if not base:
        pytest.skip("Set NATIVE_PARITY_DATABASE_URL to a PostgreSQL test database")
    assert NATIVE.is_file(), "Build the native backend with scripts/build_native.sh"
    with isolated_schema(base) as schema:
        database = database_url(base, schema, "Go")
        with psycopg.connect(database) as connection:
            connection.execute("CREATE TYPE userrole AS ENUM ('teacher', 'student')")
            connection.execute(
                """CREATE TABLE users (
                    id varchar(36) PRIMARY KEY, student_id varchar(16), teacher_id varchar(16),
                    full_name varchar(120) NOT NULL, role userrole NOT NULL, password_hash varchar(255) NOT NULL,
                    biometric_enabled boolean NOT NULL, created_at timestamp NOT NULL
                )"""
            )
            connection.execute(
                """INSERT INTO users (id,student_id,full_name,role,password_hash,biometric_enabled,created_at)
                VALUES ('legacy-student','26CE100','Legacy Student','student',%s,false,now())""",
                (pbkdf2_sha256.hash(PASSWORD),),
            )
        with server("Go", base, schema) as origin:
            scenario = Scenario(origin, "Go", database)
            assert scenario.login("26CE100", "student")["user_id"] == "legacy-student"
            assert scenario.login(ADMIN, "admin")["role"] == "admin"
            assert scenario.call("GET", "/auth/me", actor="student")["is_super_admin"] is False
