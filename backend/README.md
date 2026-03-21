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
