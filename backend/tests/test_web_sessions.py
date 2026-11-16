from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, update
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.auth import hash_password
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.models import BrowserSession, User, UserRole

ORIGIN = "https://attendance.example.test"
WEB = {"Origin": ORIGIN, "X-BLE-Web": "1"}
CREDENTIALS = {"identifier": "T001", "password": "sample-test-password"}


@pytest.fixture
def client(monkeypatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(User(
            full_name="Test Teacher", role=UserRole.teacher, teacher_id="T001",
            password_hash=hash_password(CREDENTIALS["password"]),
        ))
        db.commit()

    def test_db():
        with Session(engine) as db:
            yield db

    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "web_origins", [ORIGIN])
    monkeypatch.setitem(app.dependency_overrides, get_db, test_db)
    yield TestClient(app, base_url=ORIGIN), engine
    engine.dispose()


def test_signed_in_cookie_is_short_lived_and_revoked_on_logout(client):
    browser, _ = client
    response = browser.post("/auth/web/login", json=CREDENTIALS, headers=WEB)
    assert response.status_code == 204
    cookie = response.headers["set-cookie"]
    assert cookie.startswith("__Host-ble_session=")
    assert {part.strip().lower() for part in cookie.split(";")[1:]} == {
        "httponly", "secure", "path=/", "samesite=strict", "max-age=1800",
    }
    assert response.headers["cache-control"] == "no-store"
    assert response.content == b""
    session_cookie = browser.cookies.get("__Host-ble_session")

    me = browser.get("/auth/me")
    assert me.status_code == 200
    assert me.json()["teacher_id"] == "T001"
    assert me.headers["cache-control"] == "no-store"

    logout = browser.post("/auth/web/logout", headers=WEB)
    assert logout.status_code == 204
    assert "Max-Age=0" in logout.headers["set-cookie"]
    assert browser.get("/auth/me").status_code == 401
    assert browser.get("/auth/me", headers={"Cookie": f"__Host-ble_session={session_cookie}"}).status_code == 401


def test_expired_cookie_is_rejected_server_side(client):
    browser, engine = client
    assert browser.post("/auth/web/login", json=CREDENTIALS, headers=WEB).status_code == 204
    with Session(engine) as db:
        db.execute(update(BrowserSession).values(expires_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
    assert browser.get("/auth/me").status_code == 401


@pytest.mark.parametrize("headers", [{}, {"Origin": ORIGIN}, {"Origin": "https://unapproved.example", "X-BLE-Web": "1"}])
def test_browser_session_writes_require_origin_and_header(client, headers):
    browser, _ = client
    assert browser.post("/auth/web/login", json=CREDENTIALS, headers=headers).status_code == 403
    assert browser.post("/auth/web/login", json=CREDENTIALS, headers=WEB).status_code == 204
    assert browser.post(
        "/auth/change-password",
        json={"old_password": CREDENTIALS["password"], "new_password": "new-test-password"},
        headers=headers,
    ).status_code == 403
    assert browser.post("/auth/web/logout", headers=headers).status_code == 403
    assert browser.post(
        "/auth/change-password",
        json={"old_password": CREDENTIALS["password"], "new_password": "new-test-password"},
        headers=WEB,
    ).status_code == 200


def test_anonymous_wrong_password_and_mobile_bearer_session(client):
    browser, _ = client
    assert browser.get("/auth/me").status_code == 401
    login = browser.post("/auth/web/login", json={**CREDENTIALS, "password": "wrong"}, headers=WEB)
    assert login.status_code == 401 and "set-cookie" not in login.headers
    mobile = browser.post("/auth/login", json=CREDENTIALS)
    assert mobile.status_code == 200 and "set-cookie" not in mobile.headers
    bearer = {"Authorization": "Bearer " + mobile.json()["access_token"]}
    assert browser.get("/auth/me", headers=bearer).json()["teacher_id"] == "T001"
    assert browser.post(
        "/auth/change-password", json={"old_password": CREDENTIALS["password"], "new_password": "new-test-password"},
        headers=bearer,
    ).status_code == 200


def test_cors_only_allows_configured_origins_and_methods(client):
    browser, _ = client
    response = browser.options(
        "/auth/me", headers={"Origin": "https://unapproved.example", "Access-Control-Request-Method": "GET"},
    )
    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_production_requires_exact_https_origins():
    from pydantic import ValidationError

    from app.config import Settings

    assert Settings(app_env="production", web_origins=None).allowed_web_origins == []
    for origin in ["*", "http://example.test", "https://example.test/path", "https://*.example.test"]:
        with pytest.raises(ValidationError):
            Settings(app_env="production", web_origins=[origin])
    assert Settings(app_env="production", web_origins=[ORIGIN]).allowed_web_origins == [ORIGIN]
