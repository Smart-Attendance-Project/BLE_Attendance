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

## Android background reliability

On Android, BLE advertising is hosted by a native foreground service rather
than only by the Flutter UI isolate. The service stores the latest payload,
uses a partial wake lock, requests low-latency/high-power advertising, and
restarts after service recreation or device reboot.

For Oppo/ColorOS, Vivo/FuntouchOS, OnePlus/OxygenOS, Xiaomi/MIUI, Huawei, and
similar devices, the student must also:

1. Allow Bluetooth and notification permissions.
2. Allow the app to ignore battery optimizations.
3. Enable the app's **Auto-start** or **Allow background activity** setting.
4. Keep the persistent BLE Attendance notification enabled.

The student app shows shortcuts for battery optimization and OEM auto-start
settings. Android still cannot prevent a user from explicitly force-stopping
the app; after force-stop, the student must open the app again.
