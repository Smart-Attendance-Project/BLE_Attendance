import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Android BLE advertising owned by a native foreground service.
///
/// Keeping the advertiser out of the Flutter UI isolate is important on OEM
/// Android builds that suspend or reclaim the Flutter process after the screen
/// is locked. The native service persists the latest payload and restarts the
/// Android BluetoothLeAdvertiser when the service is recreated.
class NativeBleAdvertiser {
  static const MethodChannel _channel =
      MethodChannel('ble_attendance/native_advertiser');

  static Future<void> start({
    required String serviceUuid,
    required List<int> payload,
  }) async {
    await _channel.invokeMethod<void>('startAdvertising', {
      'serviceUuid': serviceUuid,
      'payload': Uint8List.fromList(payload),
    });
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stopAdvertising');
  }
}
