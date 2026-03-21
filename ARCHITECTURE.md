# BLE Attendance Prototype Architecture

## Scope locked for prototype

- Single mobile app with teacher/student roles
- FastAPI + PostgreSQL backend
- Android-first delivery with iOS-safe constraints from start
- Local login and end-of-session biometric confirmation

## Flow

1. Teacher logs in and starts a lecture session.
2. Backend creates active session and issues token.
3. Teacher app advertises token over BLE.
4. Student app scans and detects token repeatedly.
5. Student app submits `session_id`, RSSI, and proximity flag to backend.
6. Session ends by teacher.
7. Student confirms identity with biometrics and finalizes attendance.

## Data model

- `users` (teacher or student)
- `sessions` (single active session per teacher)
- `detections` (time-stamped RSSI samples)
- `attendance` (presence ratio + biometric status)

## Presence ratio (prototype)

- Window size: 30 seconds
- ratio = valid detections / elapsed windows
- present if ratio >= 0.6

## iOS feasibility guardrails

- Student app should be foreground/background active and not force-killed
- BLE behavior when force-killed is not guaranteed by iOS
- Early iOS spike should validate scan reliability on one physical device

## Hosting options for testing

- API: Render free tier
- DB: Supabase or Neon free Postgres
- Alternative: expose local API with Cloudflare Tunnel
