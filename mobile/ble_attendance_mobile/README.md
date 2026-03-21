# BLE Attendance Mobile

Single Flutter app for teacher and student prototype flows.

## Prototype features

- Register/login for teacher or student
- Teacher can start/end session and advertise BLE token
- Student scans BLE and posts RSSI detections
- Student biometric attendance finalization
- Teacher can view live detections list

## Run app

1. Start backend server on your machine (`http://127.0.0.1:8000`).
2. For Android emulator, default API base is already `http://10.0.2.2:8000`.
3. For real device testing, pass local IP:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Notes

- iOS prototype assumes app is opened at class start and not force-closed.
- BLE broadcast/scanning behavior differs by platform and OS power policies.
