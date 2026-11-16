"""Shared API quotas, request correlation, and structured security audit events."""

import hmac
import json
import re
import time
from collections import Counter
from dataclasses import dataclass
from uuid import uuid4

from fastapi import HTTPException, Request
from sqlalchemy import case
from sqlalchemy.dialects.postgresql import insert as postgres_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session
from starlette.datastructures import MutableHeaders
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.config import settings
from app.models import ApiRateBucket, AuditEvent, User

BODY_LIMITS = {
    "/auth/login": 8 * 1024,
    "/auth/register-face": 128 * 1024,
    "/auth/re-register-face": 128 * 1024,
    "/detections": 4 * 1024,
    "/detections/batch": 128 * 1024,
    "/attendance/finalize": 4 * 1024,
}

SENSITIVE_REASON = re.compile(
    r"\b(?:password|secret|token|embedding|authorization)\s*[:=]"
    r"|\bbearer\s+\S|\beyJ[\w-]+\.[\w.-]+|\[\s*[+-]?\d+(?:\.\d+)?\s*[,\]]"
    r"|[\w-]{32,}",
    re.IGNORECASE,
)


class SecurityRequestMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = uuid4().hex
        scope.setdefault("state", {})["security_request_id"] = request_id

        async def send_correlated(message: Message):
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["X-Request-ID"] = request_id
            await send(message)

        limit = BODY_LIMITS.get(scope["path"]) if scope["method"] == "POST" else None
        if limit is None:
            await self.app(scope, receive, send_correlated)
            return

        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > limit:
                response = JSONResponse({"detail": "Request body too large"}, status_code=413)
                await response(scope, receive, send_correlated)
                return
            body.extend(chunk)
            if not message.get("more_body", False):
                break

        async def receive_bounded():
            nonlocal body
            if body is None:
                return await receive()
            bounded = bytes(body)
            body = None
            return {"type": "http.request", "body": bounded, "more_body": False}

        await self.app(scope, receive_bounded, send_correlated)


def _fingerprint(*parts: str) -> str:
    encoded = json.dumps(parts, separators=(",", ":")).encode()
    return hmac.digest(settings.jwt_secret.encode(), encoded, "sha256").hex()


def _source_ip(request: Request | None) -> str | None:
    # Uvicorn only populates this from headers sent by a trusted proxy.
    return request.client.host if request is not None and request.client is not None else None


def audit_request_id(request: Request | None) -> str:
    return request.state.security_request_id if request is not None else uuid4().hex


def login_target(identifier: str) -> str:
    return _fingerprint("login-identifier", identifier)


def audit_event(
    db: Session,
    request: Request | None,
    action: str,
    *,
    target_id: str,
    actor: User | None = None,
    session_id: str | None = None,
    outcome: str = "allowed",
    details: dict | None = None,
    request_id: str | None = None,
):
    source_ip = _source_ip(request) if settings.security_audit_ip_enabled else None
    db.add(AuditEvent(
        request_id=request_id or audit_request_id(request),
        action=action,
        actor_id=actor.id if actor else None,
        actor_role=actor.role.value if actor else None,
        target_id=target_id,
        session_id=session_id,
        outcome=outcome,
        network_fingerprint=_fingerprint("network", source_ip) if source_ip else None,
        details=details or {},
    ))


def audit_override(
    db: Session, request: Request | None, actor: User, session_id: str, student_id: str,
    old_present: bool | None, new_present: bool, reason: str, *, request_id: str | None = None,
):
    normalized = " ".join(reason.split())
    audit_event(
        db, request, "attendance.override", target_id=student_id, actor=actor, session_id=session_id,
        details={
            "old_present": old_present,
            "new_present": new_present,
            "reason": "[redacted]" if SENSITIVE_REASON.search(normalized) else normalized,
        },
        request_id=request_id,
    )


@dataclass(frozen=True)
class Limit:
    scope: tuple[str, ...]
    quota: int
    seconds: int
    cost: int = 1


def _now_epoch() -> int:
    return int(time.time())


def enforce_limits(db: Session, *rules: Limit) -> None:
    now = _now_epoch()
    rows = sorted(
        (
            {
                "key": _fingerprint(*rule.scope, str(rule.seconds)),
                "count": rule.cost,
                "quota": rule.quota,
                "window_end": (now // rule.seconds + 1) * rule.seconds,
            }
            for rule in rules
        ),
        key=lambda row: row["key"],
    )
    insert = sqlite_insert if db.get_bind().dialect.name == "sqlite" else postgres_insert
    statement = insert(ApiRateBucket).values(rows)
    # Update all dimensions in one transaction or roll the reservation back.
    expired = ApiRateBucket.window_end <= now
    new_count = case(
        (expired, statement.excluded.count),
        else_=ApiRateBucket.count + statement.excluded.count,
    )
    accepted = set(db.scalars(statement.on_conflict_do_update(
        index_elements=[ApiRateBucket.key],
        set_={
            "count": new_count,
            "quota": statement.excluded.quota,
            "window_end": statement.excluded.window_end,
        },
        where=new_count <= statement.excluded.quota,
    ).returning(ApiRateBucket.key)))

    if len(accepted) != len(rows):
        db.rollback()
        retry_after = max(row["window_end"] - now for row in rows if row["key"] not in accepted)
        raise HTTPException(
            status_code=429,
            detail="Too many requests. Try again later.",
            headers={"Retry-After": str(retry_after)},
        )
    db.commit()


def limit_login(db: Session, request: Request | None, identifier: str) -> None:
    source = _source_ip(request) or "unknown"
    enforce_limits(
        db,
        Limit(("login-ip", source), 120, 60),
        Limit(("login-account", identifier), 3, 15),
        Limit(("login-account", identifier), 8, 120),
        Limit(("login-account", identifier), 15, 900),
    )


def limit_detections(db: Session, actor_id: str, sessions: Counter[str], *, batch: bool) -> None:
    action = "detection-batch" if batch else "detection"
    account_cap, session_cap = (1200, 600) if batch else (32, 8)
    enforce_limits(
        db,
        Limit((action + "-requests", actor_id), 120 if batch else 32, 60),
        Limit((action + "-items", actor_id), account_cap, 60, sum(sessions.values())),
        *(Limit((action + "-session", actor_id, session), session_cap, 60, cost)
          for session, cost in sessions.items()),
    )
