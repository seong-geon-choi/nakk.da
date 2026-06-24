package com.sgchoisg.nakkda

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.*
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Locale

class LocationTrackingService : Service() {

    companion object {
        private const val CHANNEL_ID = "nakkda_tracking_channel"
        private const val NOTIFICATION_ID = 1004
        const val ACTION_STOP = "com.sgchoisg.nakkda.STOP_TRACKING"
        const val PREFS_NAME = "nakkda_track_prefs"
        const val PREFS_PENDING_KEY = "pending_points"
        const val PREFS_ACTIVE_KEY = "tracking_active"
        const val PREFS_QUICK_LAUNCH_MODE_KEY = "quick_launch_mode"
        const val PREFS_SHAKE_THRESHOLD_KEY = "shake_threshold_g"
        @JvmField val pendingLock = Any()
        private const val EXTRA_INTERVAL = "intervalMeters"
        private const val UPDATE_INTERVAL_MS = 5000L   // 위치 갱신 주기
        private const val FASTEST_INTERVAL_MS = 2000L  // 최소 갱신 간격
        private const val MAX_ACCURACY_METERS = 1000f  // 이보다 부정확한 픽스는 제외

        fun getQuickLaunchMode(context: Context): String =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(PREFS_QUICK_LAUNCH_MODE_KEY, "volume") ?: "volume"

        fun getShakeThresholdG(context: Context): Float =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getFloat(PREFS_SHAKE_THRESHOLD_KEY, 3.5f)

        fun start(context: Context, intervalMeters: Int) {
            val intent = Intent(context, LocationTrackingService::class.java)
                .apply { putExtra(EXTRA_INTERVAL, intervalMeters) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }

    private var fusedClient: FusedLocationProviderClient? = null
    private var minDistanceMeters: Float = 100f
    private var lastSavedLocation: Location? = null

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            // 지나치게 부정확한 네트워크 픽스 제외 (지하에서도 합리적인 점만 기록)
            if (location.hasAccuracy() && location.accuracy > MAX_ACCURACY_METERS) return
            val last = lastSavedLocation
            if (last != null && last.distanceTo(location) < minDistanceMeters) return
            lastSavedLocation = location
            savePoint(location.latitude, location.longitude, location.time)
        }
    }

    private val dateChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            val notif = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notif)
            }
        } catch (e: SecurityException) {
            stopSelf()
            return
        }
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(PREFS_ACTIVE_KEY, true).apply()

        val filter = IntentFilter(Intent.ACTION_DATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dateChangedReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(dateChangedReceiver, filter)
        }
    }

    @SuppressLint("MissingPermission")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val intervalMeters = (intent?.getIntExtra(EXTRA_INTERVAL, 100) ?: 100).toFloat()
        minDistanceMeters = intervalMeters

        // FusedLocationProvider: GPS+WiFi+기지국을 융합.
        // setWaitForAccurateLocation(false) → GPS 신호를 기다리지 않고 네트워크 위치도 즉시 수신
        // (지하철 등 GPS 음영에서도 WiFi/기지국 기반 위치 기록 가능)
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(FASTEST_INTERVAL_MS)
            .setMinUpdateDistanceMeters(minDistanceMeters)
            .setWaitForAccurateLocation(false)
            .build()
        try {
            fusedClient?.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
        } catch (_: SecurityException) {
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        try { fusedClient?.removeLocationUpdates(locationCallback) } catch (_: Exception) {}
        try { unregisterReceiver(dateChangedReceiver) } catch (_: Exception) {}
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(PREFS_ACTIVE_KEY, false).apply()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    private val timeFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    private fun savePoint(lat: Double, lng: Double, timeMs: Long) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        synchronized(pendingLock) {
            val arr = try {
                JSONArray(prefs.getString(PREFS_PENDING_KEY, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            arr.put("$lat,$lng,${timeFmt.format(java.util.Date(timeMs))}")
            prefs.edit().putString(PREFS_PENDING_KEY, arr.toString()).commit()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "위치 트래킹", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "이동 경로 기록 중"
                setShowBadge(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val stopPi = PendingIntent.getService(
            this, 1,
            Intent(this, LocationTrackingService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("이동 경로 기록 중")
            .setContentText("위치 정보를 기록하고 있습니다")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true).setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_delete, "중지", stopPi)
            .build()
    }
}
