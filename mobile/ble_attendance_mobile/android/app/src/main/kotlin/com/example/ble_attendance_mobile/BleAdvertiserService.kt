package com.example.ble_attendance_mobile

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothLeAdvertiser
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import android.os.PowerManager
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.UUID

/**
 * Process-independent BLE advertiser for Android.
 *
 * The payload is persisted before the service starts. If an OEM recreates the
 * service after locking the phone, onStartCommand restores the last payload
 * and starts BluetoothLeAdvertiser again without needing the Flutter UI.
 */
class BleAdvertiserService : Service() {
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothLeAdvertiser = try {
            bluetoothManager?.adapter?.bluetoothLeAdvertiser
        } catch (_: SecurityException) {
            null
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, notification())
        acquireWakeLock()

        when (intent?.action) {
            ACTION_STOP -> {
                preferences().edit().putBoolean(KEY_ACTIVE, false).apply()
                stopAdvertising()
                stopSelf()
            }
            else -> startAdvertisingFromPreferences()
        }

        // Ask Android to recreate the service after a process reclaim. OEM
        // battery managers can still override this, hence the separate
        // autostart/battery-optimization guidance shown by the Flutter UI.
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (preferences().getBoolean(KEY_ACTIVE, false)) {
            scheduleRestart()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopAdvertising()
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startAdvertisingFromPreferences() {
        val prefs = preferences()
        val serviceUuid = prefs.getString(KEY_SERVICE_UUID, null) ?: return
        val encodedPayload = prefs.getString(KEY_PAYLOAD, null) ?: return
        val payload = try {
            Base64.decode(encodedPayload, Base64.NO_WRAP)
        } catch (_: IllegalArgumentException) {
            return
        }

        if (!hasAdvertisePermission()) {
            Log.e(TAG, "BLE advertising skipped: BLUETOOTH_ADVERTISE permission missing")
            return
        }
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        if (adapter == null || !hasBluetoothPermission() || !adapter.isEnabled) {
            Log.e(TAG, "BLE advertising skipped: adapter unavailable, disabled, or permission missing")
            return
        }

        val advertiser = bluetoothLeAdvertiser ?: adapter.bluetoothLeAdvertiser ?: return
        stopAdvertising()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = try {
            AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(UUID.fromString(serviceUuid)))
                .addManufacturerData(MANUFACTURER_ID, payload)
                .build()
        } catch (_: IllegalArgumentException) {
            return
        }

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.i(TAG, "BLE advertising started; payloadBytes=${payload.size}")
            }

            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "BLE advertising failed; errorCode=$errorCode")
            }
        }
        advertiseCallback = callback
        try {
            advertiser.startAdvertising(settings, data, callback)
            bluetoothLeAdvertiser = advertiser
        } catch (_: SecurityException) {
            Log.e(TAG, "BLE advertising failed: SecurityException")
            advertiseCallback = null
        }
    }

    private fun stopAdvertising() {
        val advertiser = bluetoothLeAdvertiser
        val callback = advertiseCallback
        if (advertiser != null && callback != null && hasBluetoothPermission()) {
            try {
                advertiser.stopAdvertising(callback)
            } catch (_: SecurityException) {
                // Permission may have been revoked while the service stopped.
            }
        }
        advertiseCallback = null
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:ble-advertiser",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun scheduleRestart() {
        val restartIntent = Intent(this, BleAdvertiserService::class.java)
            .setAction(ACTION_START)
        val pendingIntent = PendingIntent.getService(
            this,
            REQUEST_CODE,
            restartIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val triggerAt = android.os.SystemClock.elapsedRealtime() + RESTART_DELAY_MS
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent,
            )
        } else {
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent,
            )
        }
    }

    private fun hasBluetoothPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            ) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_CONNECT,
                ) == PackageManager.PERMISSION_GRANTED)

    private fun hasAdvertisePermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            ) == PackageManager.PERMISSION_GRANTED

    private fun preferences() =
        getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun notification(): Notification =
        NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("BLE Attendance")
            .setContentText("BLE attendance advertising is active")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "BLE Attendance advertising",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    companion object {
        private const val TAG = "BleAdvertiserService"
        private const val PREFERENCES = "ble_advertiser"
        private const val KEY_ACTIVE = "active"
        private const val KEY_SERVICE_UUID = "service_uuid"
        private const val KEY_PAYLOAD = "payload"
        private const val NOTIFICATION_CHANNEL = "ble_advertiser"
        private const val NOTIFICATION_ID = 4101
        private const val REQUEST_CODE = 4102
        private const val RESTART_DELAY_MS = 1500L
        private const val MANUFACTURER_ID = 0x004C

        const val ACTION_START = "com.example.ble_attendance_mobile.START_ADVERTISING"
        const val ACTION_STOP = "com.example.ble_attendance_mobile.STOP_ADVERTISING"

        fun start(context: Context, serviceUuid: String, payload: ByteArray) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ACTIVE, true)
                .putString(KEY_SERVICE_UUID, serviceUuid)
                .putString(KEY_PAYLOAD, Base64.encodeToString(payload, Base64.NO_WRAP))
                .apply()
            val intent = Intent(context, BleAdvertiserService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ACTIVE, false)
                .remove(KEY_SERVICE_UUID)
                .remove(KEY_PAYLOAD)
                .apply()
            context.stopService(Intent(context, BleAdvertiserService::class.java))
        }

        fun restoreAfterBoot(context: Context) {
            val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_ACTIVE, false)) return
            val intent = Intent(context, BleAdvertiserService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
