import secrets
from hashlib import sha256
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, Request, Response, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import BrowserSession, User, UserRole

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)
BROWSER_SESSION_SECONDS = 30 * 60


def hash_password(raw_password: str) -> str:
    return pwd_context.hash(raw_password)


def verify_password(raw_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(raw_password, hashed_password)


def create_access_token(subject: str) -> str:
    expiry = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_exp_minutes)
    payload = {"sub": subject, "exp": expiry}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def authenticate_user(db: Session, identifier: str, password: str) -> User | None:
    stmt = select(User).where(
        or_(
            User.student_id == identifier,
            User.teacher_id == identifier,
            User.admin_id == identifier,
        )
    )
    user = db.scalar(stmt)
    if user is None or not verify_password(password, user.password_hash):
        return None
    return user


def browser_cookie_name() -> str:
    return "ble_session" if settings.app_env == "dev" else "__Host-ble_session"


def require_web_origin(request: Request) -> None:
    if (
        request.headers.get("Origin") not in settings.allowed_web_origins
        or request.headers.get("X-BLE-Web") != "1"
    ):
        raise HTTPException(status_code=403, detail="Browser request origin not allowed")


def _session_hash(cookie: str) -> str:
    return sha256(cookie.encode()).hexdigest()


def _remove_browser_session(db: Session, request: Request) -> None:
    cookie = request.cookies.get(browser_cookie_name())
    if cookie:
        db.execute(delete(BrowserSession).where(BrowserSession.token_hash == _session_hash(cookie)))


def create_browser_session(db: Session, user: User, request: Request, response: Response) -> None:
    now = datetime.now(timezone.utc)
    cookie = secrets.token_urlsafe(32)
    _remove_browser_session(db, request)
    db.execute(delete(BrowserSession).where(BrowserSession.expires_at <= now))
    db.add(BrowserSession(
        token_hash=_session_hash(cookie),
        user_id=user.id,
        expires_at=now + timedelta(seconds=BROWSER_SESSION_SECONDS),
    ))
    db.commit()
    response.set_cookie(
        browser_cookie_name(), cookie, max_age=BROWSER_SESSION_SECONDS,
        secure=settings.app_env != "dev", httponly=True, samesite="strict",
    )


def revoke_browser_session(db: Session, request: Request, response: Response) -> None:
    _remove_browser_session(db, request)
    db.commit()
    response.delete_cookie(
        browser_cookie_name(), secure=settings.app_env != "dev", httponly=True, samesite="strict",
    )


def get_current_user(
    request: Request,
    token: str | None = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if token is None:
        cookie = request.cookies.get(browser_cookie_name())
        if not cookie or "authorization" in request.headers:
            raise credentials_error
        if request.method not in {"GET", "HEAD", "OPTIONS"}:
            require_web_origin(request)
        user = db.scalar(
            select(User).join(BrowserSession, BrowserSession.user_id == User.id).where(
                BrowserSession.token_hash == _session_hash(cookie),
                BrowserSession.expires_at > datetime.now(timezone.utc),
            )
        )
        if user is None:
            raise credentials_error
        return user

    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_error
    except JWTError as exc:
        raise credentials_error from exc

    user = db.get(User, user_id)
    if user is None:
        raise credentials_error
    return user


def require_role(*required_roles: UserRole):
    def checker(user: User = Depends(get_current_user)) -> User:
        if user.role not in required_roles:
            raise HTTPException(status_code=403, detail="Forbidden for this role")
        return user
    return checker


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


def require_super_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != UserRole.admin or not user.is_super_admin:
        raise HTTPException(status_code=403, detail="Super-admin access required")
    return user
