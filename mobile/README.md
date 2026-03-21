# BLE Attendance Prototype Mobile (Flutter)

This repository does not yet include generated Flutter project files because Flutter SDK is not installed in the current environment.

## Planned stack

- Flutter app (single app, teacher + student role)
- `flutter_reactive_ble` for student scanning
- `flutter_ble_peripheral` for teacher token advertising
- `local_auth` for end-of-session student biometric confirmation

## Project bootstrap (run on your machine with Flutter installed)

```bash
flutter create ble_attendance_mobile
cd ble_attendance_mobile
```

## Required dependencies

```bash
flutter pub add dio
flutter pub add flutter_secure_storage
flutter pub add flutter_reactive_ble
flutter pub add flutter_ble_peripheral
flutter pub add local_auth
```

## iOS-safe prototype requirement

For prototype behavior, student app must be opened before class and not force-closed until class end.

## High-level screens

- Login / Register
- Role home router
- Teacher dashboard: start/end session, advertise token, live detections
- Student dashboard: active session status, RSSI indicator, biometric finalize button

## Next implementation step

Once Flutter SDK is available, generate app skeleton and wire backend API endpoints from `../backend`.
