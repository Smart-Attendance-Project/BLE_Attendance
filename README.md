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
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
PYTHONPATH=backend .venv/bin/python backend/scripts/seed_demo.py
PYTHONPATH=backend .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload --app-dir backend
```

API docs: `http://127.0.0.1:8000/docs`

## Temporary LAN test setup (same Wi-Fi)

1. On laptop, start backend with `--host 0.0.0.0` (command above).
2. Find laptop IP (example `192.168.1.7`) using `ip a`.
3. On phone browser, verify `http://<laptop-ip>:8000/health`.
4. In app login screen, set `Server URL` to `http://<laptop-ip>:8000`.
5. Tap `Test Connection`, then login.

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

## Build APK (smaller ARM only)

Build split release APKs for `armeabi-v7a` and `arm64-v8a`:

```bash
cd mobile/ble_attendance_mobile
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

Package them with app name + version iteration in filename:

```bash
./scripts/package_release_apks.sh v0.1.3
```

Output files (raw + packaged):

- `mobile/ble_attendance_mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `mobile/ble_attendance_mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `mobile/ble_attendance_mobile/build/app/outputs/flutter-apk/BLE_Attendance_v0.1.3_armeabi-v7a_release.apk`
- `mobile/ble_attendance_mobile/build/app/outputs/flutter-apk/BLE_Attendance_v0.1.3_arm64-v8a_release.apk`

## Local build prerequisites (Linux)

- Flutter SDK installed and in `PATH`
- Java 17 JDK available for Gradle builds
- Android SDK + licenses accepted (`platform-tools`, platform/build-tools, NDK)
- Docker running for local PostgreSQL

## Built APK

Release assets currently publish release APKs for ARM only:

- `app-armeabi-v7a-release.apk`
- `app-arm64-v8a-release.apk`
