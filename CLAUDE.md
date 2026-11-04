# BLE Attendance Architecture Guide (CLAUDE.md)

Guidelines, invariants, and coding standards for contributors and AI assistants working on the BLE Attendance system.

---

## 1. Project Overview

BLE Attendance is a proximity-based lecture attendance platform designed for educational institutions. It consists of:
- **Mobile Client (`mobile/ble_attendance_mobile`)**: Flutter application running on teacher and student Android devices. Uses Bluetooth Low Energy (BLE) peripheral advertising and central scanning to detect student presence, coupled with local on-device biometric (TFLite/MLKit) face verification.
- **Backend API (`backend/`)**: FastAPI application backed by PostgreSQL (or SQLite for testing), managing course structures, enrollments, schedule slots, and final attendance persistence.
- **Web Frontend (`frontend/`)**: React + Vite dashboard for administrators and faculty to manage departments, semesters, timetables, and export attendance records.

---

## 2. Strict Architectural Constraints

### 2.1 Offline-First BLE Architecture
1. **Never block on server availability at session start**:
   - Teachers must be able to start an active classroom session and begin BLE beaconing without requiring an active internet connection.
   - Schedules and enrolled rosters must be cached locally on device.
2. **Offline attendance buffering**:
   - The teacher's device aggregates student beacons locally during lecture time.
   - If network connectivity is lost, attendance records are stored locally in secure storage (`teacher_pending_attendance`) and retried with exponential backoff once connectivity resumes.
3. **No synchronous HTTP during live tracking**:
   - Never inject blocking HTTP requests into the BLE scanning, advertising, or local tallying loops.

### 2.2 Polling & Synchronization Limits
1. **Ban unthrottled HTTP polling**:
   - Do not poll server status faster than every 15 seconds.
   - Prefer in-band BLE signaling over network polling. The teacher transmits state transitions (such as finalization opening) via BLE advertisement flags (`|F`), allowing student devices to react immediately without network access.
2. **Background sync**:
   - All network synchronization must be asynchronous and resilient to intermittent disconnects.

### 2.3 Database & Query Optimization (No N+1 Queries)
1. **Always batch database queries**:
   - Never query or write student records in a loop.
   - Endpoints such as `POST /teacher/sessions/{session_id}/attendance/batch-submit`, `GET /teacher/sessions/{session_id}/attendance-summary`, and `GET /teacher/attendance/export` must fetch students, enrollments, detections, and attendance in single batch queries using SQL `IN` clauses.
2. **Preserve pre-computed presence metrics**:
   - Compute presence ratios against elapsed 30-second windows (`total_windows = max(1, elapsed_seconds // 30)`).

---

## 3. Trust Boundaries & Security Model

### 3.1 Attendance Decisions
1. **Dual-factor requirement**:
   - Automatic presence requires **both** BLE detection threshold (`presence_ratio >= 0.75`) **and** biometric verification (`biometric_verified = True`).
2. **Teacher override distinction**:
   - Manual teacher corrections are explicitly tracked via `overridden_by_teacher = True` and must record `override_reason`.
   - Once a session's attendance is locked (`attendance_locked = True`), no further student or teacher modifications are permitted.

### 3.2 Biometric Protection
1. **Rate limiting face re-registrations**:
   - Face registration and re-registration enforce a rolling 30-day limit (`MAX_FACE_REGISTRATIONS_PER_MONTH = 2`).
   - Timestamps older than 30 days are automatically pruned.
   - Requests exceeding the limit are rejected with HTTP `429 Too Many Requests` and a `Retry-After` header.
2. **Template security**:
   - Biometric embeddings must never be exposed over unencrypted channels or printed to server logs.

### 3.3 Network & Transport Security
1. **HTTPS Enforcement**:
   - Production mobile builds must strictly reject unencrypted `http://` API endpoints.
   - Android release manifests must specify `android:usesCleartextTraffic="false"`. Cleartext traffic is permitted solely in `src/debug/AndroidManifest.xml` for local development.
2. **Canonical Host**:
   - The documented production API URL is `https://ble-attendance-api.onrender.com`.

---

## 4. Code Organization

```
BLE_Attendance/
├── backend/
│   ├── app/
│   │   ├── auth.py         # JWT tokens & role-based route dependencies
│   │   ├── config.py       # Pydantic BaseSettings environment configuration
│   │   ├── database.py     # SQLAlchemy engine & session dependency
│   │   ├── main.py         # FastAPI routes, startup schema evolution, & business logic
│   │   ├── models.py       # SQLAlchemy ORM models
│   │   ├── schemas.py      # Pydantic request/response validation schemas
│   │   └── services.py     # Presence ratio computation & attendance upsert logic
│   ├── tests/              # Pytest regression and optimization suites
│   └── scripts/            # Database seed scripts
├── frontend/               # React + TypeScript management portal
├── mobile/
│   └── ble_attendance_mobile/
│       ├── lib/            # Flutter application code (BLE, Face verification, UI)
│       └── test/           # Mobile tests (stress tests, URL normalization, widgets)
└── .github/
    └── workflows/          # GitHub Actions CI and release pipelines
```

---

## 5. Development & Testing Commands

### Backend
```bash
# Run backend regression tests
cd backend
python -m pytest tests -q
```

### Mobile
```bash
# Run flutter test suite
cd mobile/ble_attendance_mobile
flutter test
```

### Frontend
```bash
# Build frontend
cd frontend
npm ci
npm run build
```

---

## 6. Contributor Review Checklist

Before submitting or merging any pull request:
- [ ] No new network dependencies added to session startup or BLE scanning paths.
- [ ] Database queries are batched; no N+1 query loops.
- [ ] All new backend endpoints enforce role-based dependencies (`require_role`, `require_admin`).
- [ ] Face registration limit is respected and tests verify rolling window behavior.
- [ ] Release configuration maintains HTTPS-only and disables cleartext traffic.
- [ ] Backend tests pass without errors (`pytest tests`).
