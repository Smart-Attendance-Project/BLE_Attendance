import json
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, delete, select, text, update
from sqlalchemy.exc import DBAPIError
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import abuse
from app.auth import create_access_token, hash_password
from app.database import Base, get_db
from app.main import app
from app.models import (
    AuditEvent, Branch, Division, DivisionStudent, Session as LectureSession,
    Subject, TeacherAssignment, User, UserRole,
)
from scripts.report_api_abuse import report


@pytest.fixture(params=["sqlite", "postgresql"])
def api(monkeypatch, request):
    admin_engine = schema = None
    if request.param == "postgresql":
        url = os.environ.get("TEST_API_ABUSE_POSTGRES_URL")
        if not url:
            pytest.skip("set TEST_API_ABUSE_POSTGRES_URL to run against PostgreSQL")
        admin_engine = create_engine(url)
        schema = "test_api_abuse_" + uuid4().hex
        with admin_engine.begin() as connection:
            connection.execute(text(f"CREATE SCHEMA {schema}"))
        engine = create_engine(url, connect_args={"options": f"-csearch_path={schema}"})
    else:
        engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool,
        )

    def cleanup():
        engine.dispose()
        if admin_engine is not None:
            with admin_engine.begin() as connection:
                connection.execute(text(f"DROP SCHEMA {schema} CASCADE"))
            admin_engine.dispose()

    request.addfinalizer(cleanup)
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add_all([
            User(id="teacher", role=UserRole.teacher, teacher_id="T001",
                 full_name="Test Teacher", password_hash=hash_password("correct-demo-password")),
            User(id="student", role=UserRole.student, student_id="26CE001",
                 full_name="Test Student", password_hash=hash_password("correct-demo-password")),
        ])
        db.flush()
        branch = Branch(code="CE", name="Computer Engineering")
        db.add(branch)
        db.flush()
        division = Division(branch_id=branch.id, year=2, div_number=1, label="CE Year 2")
        subject = Subject(code="CE201", name="Test Course")
        db.add_all([division, subject])
        db.flush()
        assignment = TeacherAssignment(
            teacher_user_id="teacher", subject_id=subject.id, division_id=division.id,
        )
        db.add(assignment)
        db.add(DivisionStudent(student_user_id="student", division_id=division.id))
        db.flush()
        db.add(LectureSession(
            id="class", teacher_user_id="teacher", assignment_id=assignment.id, subject="Test Course",
            token="session-secret", is_active=True, finalization_open=True,
        ))
        db.commit()

    def test_db():
        with Session(engine) as db:
            yield db

    monkeypatch.setitem(app.dependency_overrides, get_db, test_db)
    clock = [9000]
    monkeypatch.setattr(abuse, "_now_epoch", lambda: clock[0])
    return TestClient(app), engine, clock


def _headers(user_id):
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def test_login_limits_recover_at_fixed_window_boundaries_and_redact(api):
    client, engine, clock = api
    payload = {"identifier": "T001", "password": "incorrect-demo-password"}
    for _ in range(3):
        assert client.post("/auth/login", json=payload).status_code == 401
    denied = client.post("/auth/login", json=payload)
    assert denied.status_code == 429
    assert denied.headers["Retry-After"] == "15"
    assert denied.json() == {"detail": "Too many requests. Try again later."}

    with Session(engine) as db:
        events = db.scalars(select(AuditEvent).where(AuditEvent.action == "login")).all()
        assert len(events) == 3
        assert all(event.outcome == "denied" for event in events)
        assert all(event.target_id != payload["identifier"] and event.request_id for event in events)
        assert payload["password"] not in json.dumps([event.details for event in events])

    clock[0] += 15
    for _ in range(3):
        assert client.post("/auth/login", json=payload).status_code == 401
    clock[0] += 15
    for _ in range(2):
        assert client.post("/auth/login", json=payload).status_code == 401
    denied = client.post("/auth/login", json=payload)
    assert denied.status_code == 429
    assert denied.headers["Retry-After"] == "90"
    clock[0] += 90
    assert client.post("/auth/login", json={**payload, "password": "correct-demo-password"}).status_code == 200


@pytest.mark.parametrize(("url", "payload", "count"), [
    ("/detections", {"session_id": "class", "rssi": -67}, 8),
    ("/attendance/finalize", {"session_id": "class", "biometric_verified": False}, 4),
])
def test_authenticated_limits_and_reset(api, url, payload, count):
    client, _, clock = api
    for _ in range(count):
        assert client.post(url, json=payload, headers=_headers("student")).status_code == 200
    denied = client.post(url, json=payload, headers=_headers("student"))
    assert denied.status_code == 429
    clock[0] += int(denied.headers["retry-after"])
    assert client.post(url, json=payload, headers=_headers("student")).status_code == 200


def test_short_window_also_counts_invalid_face_registration_attempts(api):
    client, _, clock = api
    headers = _headers("student")
    for route in ("/auth/register-face", "/auth/re-register-face") * 3:
        assert client.post(route, json={}, headers=headers).status_code == 422

    denied = client.post("/auth/register-face", json={"embedding": [0.123456]}, headers=headers)
    assert denied.status_code == 429
    assert denied.json() == {"detail": "Too many requests. Try again later."}
    clock[0] += int(denied.headers["retry-after"])

    for path in ("/auth/register-face", "/auth/re-register-face"):
        assert client.post(path, json={"embedding": [0.123456]}, headers=headers).status_code == 200
    monthly = client.post("/auth/re-register-face", json={"embedding": [0.123456]}, headers=headers)
    assert monthly.status_code == 429
    assert monthly.json()["detail"].startswith("Monthly face registration limit of 2 reached")


def test_batch_quota_and_body_limit(api):
    client, _, _ = api
    single = {"session_id": "class", "student_identifier": "26CE001", "rssi": -67}
    assert client.post("/detections/batch", json={"detections": [single] * 201}, headers=_headers("teacher")).status_code == 422
    too_large = client.post("/detections", content=b"x" * 4097, headers=_headers("student"))
    assert too_large.status_code == 413
    for _ in range(3):
        assert client.post("/detections/batch", json={"detections": [single] * 200}, headers=_headers("teacher")).status_code == 200
    denied = client.post("/detections/batch", json={"detections": [single]}, headers=_headers("teacher"))
    assert denied.status_code == 429


def test_audit_events_are_redacted_searchable_and_append_only(api):
    client, engine, _ = api
    registration = client.post("/auth/register-face", json={"embedding": [0.757271]}, headers=_headers("student"))
    assert registration.status_code == 200
    assert client.get("/auth/face-profile", headers=_headers("student")).status_code == 200
    for status, reason in [(True, "Teacher verified attendance"), (False, "password: secret-value")]:
        response = client.post(
            "/teacher/sessions/class/attendance/override",
            json={"student_user_id": "student", "is_present": status, "reason": reason},
            headers=_headers("teacher"),
        )
        assert response.status_code == 200

    locked = client.post("/teacher/sessions/class/lock", headers=_headers("teacher"))
    assert locked.status_code == 200

    with Session(engine) as db:
        events = db.scalars(select(AuditEvent).order_by(AuditEvent.id)).all()
        assert [event.action for event in events] == [
            "face.register", "face.read", "attendance.override", "attendance.override", "attendance.lock",
        ]
        first, second = events[2:4]
        assert first.actor_id == "teacher" and first.actor_role == "teacher" and first.target_id == "student"
        assert first.session_id == "class"
        assert first.details == {"old_present": None, "new_present": True, "reason": "Teacher verified attendance"}
        assert second.details == {"old_present": True, "new_present": False, "reason": "[redacted]"}
        assert events[0].request_id == registration.headers["X-Request-ID"]
        assert events[-1].request_id == locked.headers["X-Request-ID"]
        assert "0.757271" not in json.dumps([event.details for event in events])

        statements = [update(AuditEvent).values(outcome="changed"), delete(AuditEvent)]
        if engine.dialect.name == "postgresql":
            statements.append(text("TRUNCATE security_audit_events"))
        for stmt in statements:
            with pytest.raises(DBAPIError, match="append-only"):
                db.execute(stmt)
            db.rollback()



def test_report_groups_failures_and_high_detection_volume(api):
    client, engine, _ = api
    for _ in range(2):
        client.post("/auth/login", json={"identifier": "T001", "password": "wrong"})
        client.post("/detections", json={"session_id": "class", "rssi": -64}, headers=_headers("student"))
    with Session(engine) as db:
        result = report(db, datetime.now(timezone.utc) - timedelta(minutes=1), 2, 2)
    assert result["failed_login_groups"] == [{"target_id": abuse.login_target("T001"), "count": 2}]
    assert result["high_detection_groups"] == [{"session_id": "class", "student_user_id": "student", "count": 2}]


def test_postgresql_parallel_requests_share_the_quota(api):
    client, engine, _ = api
    if engine.dialect.name != "postgresql":
        pytest.skip("concurrency uses independent PostgreSQL connections")

    def attempt(_):
        payload = {"identifier": "T001", "password": "incorrect-demo-password"}
        return client.post("/auth/login", json=payload).status_code

    with ThreadPoolExecutor(max_workers=8) as pool:
        statuses = list(pool.map(attempt, range(12)))
    assert statuses.count(401) == 3
    assert statuses.count(429) == 9
