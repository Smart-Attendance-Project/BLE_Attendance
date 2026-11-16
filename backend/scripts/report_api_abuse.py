"""Summarize recent login failures and unusually high detection counts."""

import argparse
import json
import time
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import ApiRateBucket, AuditEvent, Detection


def report(db: Session, since: datetime, login_threshold: int, detection_threshold: int) -> dict:
    failures = func.count()
    failed_logins = db.execute(
        select(AuditEvent.target_id, failures.label("count"))
        .where(AuditEvent.action == "login", AuditEvent.outcome == "denied", AuditEvent.occurred_at >= since)
        .group_by(AuditEvent.target_id)
        .having(failures >= login_threshold)
        .order_by(failures.desc(), AuditEvent.target_id)
        .limit(100)
    )
    detections = func.count()
    high_detection_volume = db.execute(
        select(Detection.session_id, Detection.student_user_id, detections.label("count"))
        .where(Detection.detected_at >= since.replace(tzinfo=None))
        .group_by(Detection.session_id, Detection.student_user_id)
        .having(detections >= detection_threshold)
        .order_by(detections.desc(), Detection.session_id, Detection.student_user_id)
        .limit(100)
    )
    return {
        "since": since.isoformat(),
        "failed_login_groups": [dict(row) for row in failed_logins.mappings()],
        "high_detection_groups": [dict(row) for row in high_detection_volume.mappings()],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--minutes", type=int, default=15)
    parser.add_argument("--login-threshold", type=int, default=10)
    parser.add_argument("--detection-threshold", type=int, default=45)
    parser.add_argument("--prune-rate-buckets", action="store_true", help="Also delete expired rate counters")
    args = parser.parse_args()
    if min(args.minutes, args.login_threshold, args.detection_threshold) <= 0:
        parser.error("the report window and thresholds must be positive")
    since = datetime.now(timezone.utc) - timedelta(minutes=args.minutes)
    with SessionLocal() as db:
        result = report(db, since, args.login_threshold, args.detection_threshold)
        if args.prune_rate_buckets:
            db.execute(delete(ApiRateBucket).where(ApiRateBucket.window_end <= int(time.time())))
            db.commit()
    print(json.dumps(result))


if __name__ == "__main__":
    main()
