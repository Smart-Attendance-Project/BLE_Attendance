# BLE Attendance Prototype Backend

FastAPI + PostgreSQL backend for prototype attendance workflow.

## What is included

- Role-based registration/login (teacher or student)
- JWT-protected APIs
- Teacher session start/end
- Student detection submissions with RSSI + proximity flag
- Attendance finalization with biometric confirmation flag
- Teacher endpoint to inspect session detections
- Teacher attendance summary endpoint
- Teacher manual attendance override endpoint
- Demo seed script for teacher and students

## Start PostgreSQL with Docker

```bash
docker compose -f docker-compose.yml up -d
```

## Local run

1. Create and activate virtual environment.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Copy env file and edit DB credentials:

```bash
cp .env.example .env
```

4. Ensure PostgreSQL database exists (`ble_attendance` by default).
5. Run server:

```bash
uvicorn app.main:app --reload
```

6. Open API docs:

`http://127.0.0.1:8000/docs`

## Core endpoints

- `POST /auth/register`
- `POST /auth/login`
- `POST /sessions`
- `POST /sessions/{session_id}/end`
- `GET /sessions/active`
- `POST /detections`
- `POST /attendance/finalize`
- `GET /teacher/sessions/{session_id}/detections`
- `GET /teacher/sessions/{session_id}/attendance-summary`
- `POST /teacher/sessions/{session_id}/attendance/override`

## Seed demo users

```bash
PYTHONPATH=. python scripts/seed_demo.py
```

Demo logins:

- Teacher: `T001` / `Pass@123`
- Student: `25CE099` / `Pass@123`
- Student: `25CE100` / `Pass@123`
- Student: `D26CE045` / `Pass@123`

## iOS-safe prototype note

This backend assumes the mobile app follows the agreed prototype behavior:
student app is opened before class and not force-closed until session ends.

## API quotas and security audit

All API workers share quotas in PostgreSQL. These are fixed UTC windows. Exceeding a quota returns HTTP 429 with a generic error and a `Retry-After` duration in seconds. Clients should retry only after that duration.

| Endpoint | Quota | Request cap |
| --- | --- | --- |
| `POST /auth/login` | 120 attempts per source IP per minute and progressive account delays at 3 per 15 seconds, 8 per 2 minutes, and 15 per 15 minutes | 8 KiB |
| `POST /auth/register-face`, `POST /auth/re-register-face` | 6 attempts per user per 10 minutes across both endpoints | 128 KiB per request |
| `GET /auth/face-profile` | 30 reads per user per minute | — |
| `POST /detections` | 32 requests per student per minute, with 8 per student/session | 4 KiB |
| `POST /detections/batch` | 120 requests and 1,200 items per teacher per minute, with 600 items per teacher/session | 200 items and 128 KiB |
| `POST /attendance/finalize` | 12 requests per student per minute, with 4 per student/session | 4 KiB |

Login source IP uses the client address resolved by Uvicorn. Behind a trusted ingress, configure Uvicorn's `FORWARDED_ALLOW_IPS` to the ingress addresses and verify the effective client addresses. Preserve the default loopback trust for local development. No raw IP addresses or client-supplied forwarded headers are stored. Set `SECURITY_AUDIT_IP_ENABLED=true` only if your access policy allows storing a keyed network fingerprint.

`security_audit_events` records login outcomes, face registration and profile access, student finalization, teacher/administrator overrides, teacher batch decisions, and attendance locks. Events carry the API-generated `X-Request-ID`, action, timestamp, actor/role when authenticated, outcome and relevant record IDs. Overrides include the previous and new presence state and a redacted reason. Use reasons that contain only the attendance decision's context. The audit code excludes credentials and biometrics from event payloads and redacts common credential and embedding patterns in free-form reasons.

Audit writes for attendance and face registration are committed with the underlying data changes. A database trigger blocks updates, deletes and truncation of audit rows in PostgreSQL. Access audit data through a restricted read-only role. Schema owners can administer the table itself, so restrict schema-owner access and retain protected backups according to your data retention policy.

Run the scheduled report from a trusted environment with the backend database configuration:

```bash
python -m scripts.report_api_abuse --minutes 15 --login-threshold 10 --detection-threshold 45 --prune-rate-buckets
```

Schedule it every 15 minutes. Non-empty login or detection groups should be investigated. The JSON output lists up to 100 groups of each type. Login groups use keyed account fingerprints, and detection groups use internal student/session IDs. Keep output restricted to operators. The optional pruning flag removes expired quota counters only.

Run the tests from `backend` after installing `requirements-dev.txt`. Set `TEST_API_ABUSE_POSTGRES_URL` to an isolated test PostgreSQL connection string to exercise the concurrent quota checks and PostgreSQL audit trigger. The tests create and delete temporary schemas.
