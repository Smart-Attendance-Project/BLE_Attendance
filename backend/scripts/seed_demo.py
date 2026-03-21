import os
import sys


ROOT = os.path.dirname(os.path.dirname(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from sqlalchemy import select

from app.auth import hash_password
from app.database import Base, SessionLocal, engine
from app.models import User, UserRole


def create_user_if_missing(
    db,
    *,
    full_name: str,
    role: UserRole,
    identifier: str,
    password: str,
) -> None:
    if role == UserRole.teacher:
        existing = db.scalar(select(User).where(User.teacher_id == identifier))
        if existing:
            return
        user = User(
            full_name=full_name,
            role=role,
            teacher_id=identifier,
            password_hash=hash_password(password),
        )
    else:
        existing = db.scalar(select(User).where(User.student_id == identifier))
        if existing:
            return
        user = User(
            full_name=full_name,
            role=role,
            student_id=identifier,
            password_hash=hash_password(password),
        )
    db.add(user)


def main() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        create_user_if_missing(
            db,
            full_name="Demo Teacher",
            role=UserRole.teacher,
            identifier="T001",
            password="Pass@123",
        )
        create_user_if_missing(
            db,
            full_name="Student One",
            role=UserRole.student,
            identifier="25CE099",
            password="Pass@123",
        )
        create_user_if_missing(
            db,
            full_name="Student Two",
            role=UserRole.student,
            identifier="25CE100",
            password="Pass@123",
        )
        create_user_if_missing(
            db,
            full_name="Student Three",
            role=UserRole.student,
            identifier="D26CE045",
            password="Pass@123",
        )
        db.commit()
        print("Seed complete: teacher + 3 students")
    finally:
        db.close()


if __name__ == "__main__":
    main()
