package com.example.ble_attendance_mobile

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ble_attendance/native_advertiser",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val serviceUuid = call.argument<String>("serviceUuid")
                    val payload = call.argument<ByteArray>("payload")
                    if (serviceUuid.isNullOrBlank() || payload == null) {
                        result.error("INVALID_ARGS", "serviceUuid and payload are required", null)
                    } else {
                        BleAdvertiserService.start(this, serviceUuid, payload)
                        result.success(null)
                    }
                }
                "stopAdvertising" -> {
                    BleAdvertiserService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
