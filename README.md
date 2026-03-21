# BLE Attendance Prototype

Prototype implementation of a classroom attendance system using BLE proximity + biometrics.

## Stack

- Mobile: Flutter (single app with Teacher/Student roles)
- Backend: FastAPI
- Database: PostgreSQL (Docker compose provided)

## Repository layout

- `backend/` - FastAPI APIs, models, seed script, docker compose
- `mobile/ble_attendance_mobile/` - Flutter app source
- `ARCHITECTURE.md` - architecture and scope notes

## Prototype capabilities implemented

- Role-based register/login (teacher/student)
- Teacher starts/ends sessions and advertises BLE token
- Student scans BLE, sends periodic RSSI detections
- Presence ratio computed from detection windows
- Student biometric finalization endpoint flow
- Teacher detections + attendance summary endpoints
- Teacher manual attendance override endpoint

## Test credentials

Seeded accounts (from `backend/scripts/seed_demo.py`):

- Teacher: `T001` / `Pass@123`
- Student: `25CE099` / `Pass@123`
- Student: `25CE100` / `Pass@123`
- Student: `D26CE045` / `Pass@123`

## Backend quick start

```bash
cd backend
docker compose up -d
cd ..
PYTHONPATH=backend .venv/bin/python backend/scripts/seed_demo.py
PYTHONPATH=backend .venv/bin/uvicorn app.main:app --reload --app-dir backend
```

API docs: `http://127.0.0.1:8000/docs`

## Mobile quick start

```bash
cd mobile/ble_attendance_mobile
flutter pub get
flutter run
```

For physical Android devices on same LAN:

```bash
flutter run --dart-define=API_BASE_URL=http://<your-laptop-ip>:8000
```

## Built APK

Debug APK generated at:

- `mobile/ble_attendance_mobile/build/app/outputs/flutter-apk/app-debug.apk`
