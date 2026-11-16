# BLE Attendance Prototype Backend

Go + PostgreSQL server for the attendance API. The FastAPI implementation remains available for comparison, schema generation, and the Python seed scripts.

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
5. Build and run the Go server from the `backend` directory:

```bash
bash scripts/build_native.sh
./build/native/attendance-api
```

The build script uses Go 1.26.11. On Linux x86-64 and ARM64 it can download the pinned toolchain and verify its checksum. Install that Go version locally on other platforms. The API listens on port 8000 unless `PORT` is set.

6. Open API docs:

`http://127.0.0.1:8000/docs`

## Deployment and compatibility

The Render blueprint uses the same Python runtime image, seed command, service, database connection, health path, and JWT environment variables. Its build command also compiles the Go binary and generates API assets, and its start command runs the binary directly. The HTTP request path does not start a Python process.

The Go process accepts the existing `DATABASE_URL_OVERRIDE` including the `postgresql+psycopg://` scheme. It uses the same PostgreSQL tables, Passlib password hashes, and HMAC JWTs (`HS256`, `HS384`, or `HS512`). The seed scripts and the FastAPI reference are still used from Python.

Run the differential test with an isolated PostgreSQL test database and permission to create schemas. It starts both servers, creates separate temporary schemas, compares all 53 API operations and exported workbook cells, and drops the test schemas when it finishes.

```bash
bash scripts/build_native.sh
NATIVE_PARITY_DATABASE_URL=postgresql://user:password@localhost/test_db \
  python -m pytest -q
```

Set `NATIVE_PARITY_BENCHMARK=1` and run pytest with `-s` to measure local summary and export latency. The benchmark models a 70-student class. A full class emits roughly 2.3 detections per second if each student submits every 30 seconds. At 100 concurrent classes, detection inserts and shared PostgreSQL connections are the first constraints to measure. The Go server uses a 40-connection pool, set-based batch writes, grouped summary reads, and streamed worksheet row construction.

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
