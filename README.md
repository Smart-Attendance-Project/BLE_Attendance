# BLE Attendance

Classroom attendance system using BLE proximity + biometrics, with a web frontend for teachers and admins.

## Stack

- **Mobile**: Flutter (Teacher/Student roles)
- **Backend**: FastAPI + PostgreSQL
- **Frontend**: React + Vite + TypeScript

## Repository layout

```
backend/          FastAPI app, models, seed scripts, docker-compose
mobile/           Flutter app
frontend/         React web app (teacher + admin panel)
ARCHITECTURE.md   Architecture notes
```

---

## Quick start

### 1. Start the database

```bash
cd backend
docker compose up -d
cd ..
```

### 2. Set up Python environment

```bash
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
```

### 3. Run database migrations + seed data

```bash
# Seed: creates super admin, CE timetable, students 25CE001–25CE142
PYTHONPATH=backend .venv/bin/python backend/scripts/seed_full.py

# (Optional) seed original demo accounts only
PYTHONPATH=backend .venv/bin/python backend/scripts/seed_demo.py
```

### 4. Start the backend

```bash
PYTHONPATH=backend .venv/bin/uvicorn app.main:app \
  --host 0.0.0.0 --port 8000 --reload --app-dir backend
```

API docs: http://127.0.0.1:8000/docs

### 5. Start the frontend

```bash
cd frontend
npm install
npm run dev
```

Frontend: http://localhost:5173

---

## Default credentials (after seed_full.py)

| Role         | ID        | Password  |
|--------------|-----------|-----------|
| Super Admin  | ADMIN001  | Pass@123  |
| Teacher      | T001      | Pass@123  |
| Student      | 25CE001   | Pass@123  |

---

## LAN test setup (mobile app on same Wi-Fi)

1. Start backend with `--host 0.0.0.0` (step 4 above).
2. Find your laptop IP: `ip a`
3. Verify on phone: `http://<laptop-ip>:8000/health`
4. In the app login screen, set **Server URL** to `http://<laptop-ip>:8000`

---

## Mobile quick start

```bash
cd mobile/ble_attendance_mobile
flutter pub get
flutter run
```

For physical Android device on same LAN:

```bash
flutter run --dart-define=API_BASE_URL=http://<your-laptop-ip>:8000
```

## Build APK

```bash
cd mobile/ble_attendance_mobile
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
./scripts/package_release_apks.sh v0.1.3
```

---

## Frontend features

**Teacher panel**
- Today's schedule (from timetable)
- Per-session attendance view — toggle P/A per student, lock attendance
- Export attendance to Excel (P/A format) — by day, week, month, or custom date range
- Add students to a division/batch

**Admin panel**
- Manage teachers and admin accounts (super-admin can create other admins)
- Manage subjects, branches, divisions, batches
- Assign teachers to subjects + divisions
- Manage semesters (configurable, not hardcoded)
- Visual timetable grid — add/remove schedule slots

---

## Local build prerequisites

- Python 3.11+
- Node.js 18+
- Docker (for PostgreSQL)
- Flutter SDK (for mobile only)
- Java 17 JDK + Android SDK (for APK builds only)
