package com.example.ble_attendance_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BleAdvertiserBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED ->
                BleAdvertiserService.restoreAfterBoot(context)
        }
    }
}
