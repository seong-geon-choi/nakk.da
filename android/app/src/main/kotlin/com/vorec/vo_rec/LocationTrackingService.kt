package com.nakkda.nakkda

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.location.*
import android.os.*
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Locale

class LocationTrackingService : Service() {

    companion object {
        private const val CHANNEL_ID = "nakkda_tracking_channel"
        private const val NOTIFICATION_ID = 1004
        const val ACTION_STOP = "com.nakkda.nakkda.STOP_TRACKING"
        const val PREFS_NAME = "nakkda_track_prefs"
        const val PREFS_PENDING_KEY = "pending_points"
        const val PREFS_ACTIVE_KEY = "tracking_active"
        const val PREFS_QUICK_LAUNCH_MODE_KEY = "quick_launch_mode"
        private const val EXTRA_INTERVAL = "intervalMeters"
        private const val AUTO_STOP_MS = 12L * 60 * 60 * 1000

        fun getQuickLaunchMode(context: Context): String =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(PREFS_QUICK_LAUNCH_MODE_KEY, "volume") ?: "volume"

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

    private val handler = Handler(Looper.getMainLooper())
    private var locationManager: LocationManager? = null
    private var minDistanceMeters: Float = 100f
    private var lastSavedLocation: Location? = null

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            val last = lastSavedLocation
            if (last != null && last.distanceTo(location) < minDistanceMeters) return
            lastSavedLocation = location
            savePoint(location.latitude, location.longitude, location.time)
        }

        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val dateChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            stopSelf()
        }
    }

    private val autoStopRunnable = Runnable { stopSelf() }

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

        handler.removeCallbacks(autoStopRunnable)
        handler.postDelayed(autoStopRunnable, AUTO_STOP_MS)

        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val hasGps = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true
        val provider = if (hasGps) LocationManager.GPS_PROVIDER else LocationManager.NETWORK_PROVIDER
        try {
            locationManager?.requestLocationUpdates(provider, 0L, intervalMeters, locationListener)
        } catch (_: SecurityException) {
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStopRunnable)
        try { locationManager?.removeUpdates(locationListener) } catch (_: Exception) {}
        try { unregisterReceiver(dateChangedReceiver) } catch (_: Exception) {}
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(PREFS_ACTIVE_KEY, false).apply()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    private val timeFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    private fun savePoint(lat: Double, lng: Double, timeMs: Long) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val arr = try {
            JSONArray(prefs.getString(PREFS_PENDING_KEY, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        arr.put("$lat,$lng,${timeFmt.format(java.util.Date(timeMs))}")
        prefs.edit().putString(PREFS_PENDING_KEY, arr.toString()).apply()
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
