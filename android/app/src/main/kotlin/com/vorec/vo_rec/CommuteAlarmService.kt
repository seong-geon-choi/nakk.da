package com.sgchoisg.nakkda

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.location.Location
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.*
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONArray
import java.util.Calendar

/**
 * 지하철 출퇴근 알림 감시 서비스.
 * - 활성 동안 계속 떠 있음(포그라운드). 1분 틱으로 감시 시간대를 평가해
 *   창 안에서만 위치 수신(BALANCED + 적응형 주기), 창 밖에선 GPS를 꺼 배터리 절약.
 *   → AlarmManager로 서비스를 재시작할 필요가 없어 백그라운드 FGS 제약을 피함.
 * - 핀 반경 진입 시 알람 발화(서비스가 알람음/진동 재생 + full-screen 알림), 1분 후 자동중지.
 */
class CommuteAlarmService : Service() {

    companion object {
        const val PREFS_NAME = "nakkda_commute_prefs"
        const val KEY_ENABLED = "enabled"
        const val KEY_RADIUS = "radius"
        const val KEY_SOUND = "sound"
        const val KEY_PINS = "pins" // JSON array of "lat,lng"
        const val KEY_AM_START = "amStart"
        const val KEY_AM_END = "amEnd"
        const val KEY_PM_START = "pmStart"
        const val KEY_PM_END = "pmEnd"
        const val KEY_CUSTOM_START = "customStart"
        const val KEY_CUSTOM_END = "customEnd"
        const val KEY_AM_ENABLED = "amEnabled"
        const val KEY_PM_ENABLED = "pmEnabled"
        const val KEY_CUSTOM_ENABLED = "customEnabled"
        const val KEY_WEEKDAYS_ONLY = "weekdaysOnly"

        const val ACTION_STOP_ALARM = "com.sgchoisg.nakkda.STOP_COMMUTE_ALARM"

        private const val CHANNEL_MONITOR = "nakkda_commute_channel"
        private const val CHANNEL_ALARM = "nakkda_commute_alarm_channel"
        private const val NOTIF_MONITOR = 1006
        private const val NOTIF_ALARM = 1007

        private const val NEAR_BAND_METERS = 1500f
        private const val INTERVAL_NEAR_MS = 8000L
        private const val INTERVAL_FAR_MS = 40000L
        private const val HYSTERESIS = 1.3f
        private const val ALARM_DURATION_MS = 60000L // 1분
        private const val TICK_MS = 60000L // 시간대 재평가 주기

        fun start(context: Context) {
            val intent = Intent(context, CommuteAlarmService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CommuteAlarmService::class.java))
        }

        fun isWithinWindow(prefs: SharedPreferences, now: Calendar): Boolean {
            return isWindowActive(prefs, now, "am") ||
                isWindowActive(prefs, now, "pm") ||
                isWindowActive(prefs, now, "custom")
        }

        /** 특정 감시 시간대(am/pm/custom)가 현재 활성인지(평일·켜짐·시각 범위). */
        fun isWindowActive(prefs: SharedPreferences, now: Calendar, window: String): Boolean {
            if (prefs.getBoolean(KEY_WEEKDAYS_ONLY, true)) {
                val dow = now.get(Calendar.DAY_OF_WEEK)
                if (dow == Calendar.SATURDAY || dow == Calendar.SUNDAY) return false
            }
            val minutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            return when (window) {
                "am" -> prefs.getBoolean(KEY_AM_ENABLED, true) &&
                    minutes in prefs.getInt(KEY_AM_START, 480) until prefs.getInt(KEY_AM_END, 540)
                "pm" -> prefs.getBoolean(KEY_PM_ENABLED, true) &&
                    minutes in prefs.getInt(KEY_PM_START, 1140) until prefs.getInt(KEY_PM_END, 1200)
                "custom" -> prefs.getBoolean(KEY_CUSTOM_ENABLED, false) &&
                    minutes in prefs.getInt(KEY_CUSTOM_START, 600) until prefs.getInt(KEY_CUSTOM_END, 720)
                else -> false
            }
        }
    }

    private var fusedClient: FusedLocationProviderClient? = null
    private val pinLats = ArrayList<Double>()
    private val pinLngs = ArrayList<Double>()
    private val pinWindows = ArrayList<String>() // 지점별 할당 시간대(am/pm/custom)
    private var armed = BooleanArray(0)
    private var radius = 700f
    private var soundMode = "systemDefault"
    private var currentIntervalMs = INTERVAL_FAR_MS
    private var monitoring = false // 위치 수신 중인지(창 안)

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var alarming = false
    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            evaluateWindow()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.lastLocation?.let { onLocation(it) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannels()
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_ALARM) {
            stopAlarm()
            return START_STICKY
        }
        startForegroundMonitor()
        loadConfig()
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false) || pinLats.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        // 설정 변경 재적용: 틱 재시작
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    private fun loadConfig() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        radius = prefs.getInt(KEY_RADIUS, 700).toFloat()
        soundMode = prefs.getString(KEY_SOUND, "systemDefault") ?: "systemDefault"
        pinLats.clear(); pinLngs.clear(); pinWindows.clear()
        try {
            val arr = JSONArray(prefs.getString(KEY_PINS, "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val parts = arr.getString(i).split(",")
                if (parts.size >= 2) {
                    val lat = parts[0].toDoubleOrNull()
                    val lng = parts[1].toDoubleOrNull()
                    if (lat != null && lng != null) {
                        pinLats.add(lat)
                        pinLngs.add(lng)
                        pinWindows.add(if (parts.size >= 3) parts[2] else "am")
                    }
                }
            }
        } catch (_: Exception) {}
        armed = BooleanArray(pinLats.size) { true }
    }

    /** 1분마다 감시 시간대를 평가: 창 안이면 GPS 켜고, 밖이면 끈다. */
    private fun evaluateWindow() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val inWindow = isWithinWindow(prefs, Calendar.getInstance())
        if (inWindow && !monitoring) {
            requestUpdates(INTERVAL_FAR_MS)
            monitoring = true
        } else if (!inWindow && monitoring) {
            try { fusedClient?.removeLocationUpdates(locationCallback) } catch (_: Exception) {}
            monitoring = false
        }
    }

    @SuppressWarnings("MissingPermission")
    private fun requestUpdates(intervalMs: Long) {
        currentIntervalMs = intervalMs
        val request = LocationRequest.Builder(
            Priority.PRIORITY_BALANCED_POWER_ACCURACY, intervalMs
        ).setMinUpdateIntervalMillis(intervalMs / 2).build()
        try {
            fusedClient?.removeLocationUpdates(locationCallback)
            fusedClient?.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
        } catch (_: SecurityException) {
            stopSelf()
        }
    }

    private fun onLocation(loc: Location) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = Calendar.getInstance()
        var nearest = Float.MAX_VALUE
        for (i in pinLats.indices) {
            val out = FloatArray(1)
            Location.distanceBetween(loc.latitude, loc.longitude, pinLats[i], pinLngs[i], out)
            val d = out[0]
            if (d < nearest) nearest = d
            // 지점에 할당된 시간대가 현재 활성일 때만 알람 발화
            val pinActive = isWindowActive(prefs, now, pinWindows.getOrElse(i) { "am" })
            if (d <= radius && armed[i] && pinActive) {
                armed[i] = false
                triggerAlarm()
            } else if (d > radius * HYSTERESIS) {
                armed[i] = true
            }
        }
        val desired = if (nearest < NEAR_BAND_METERS) INTERVAL_NEAR_MS else INTERVAL_FAR_MS
        if (monitoring && desired != currentIntervalMs) requestUpdates(desired)
    }

    // ── 알람 발화/중지 ────────────────────────────────────
    private fun triggerAlarm() {
        if (alarming) return
        alarming = true
        val mode = resolveSoundMode()
        if (mode == "bell" || mode == "vibrateBell") startAlarmSound()
        if (mode == "vibrateOnly" || mode == "vibrateBell") startVibration()
        postAlarmNotification()
        handler.postDelayed({ stopAlarm() }, ALARM_DURATION_MS)
    }

    private fun stopAlarm() {
        alarming = false
        try { mediaPlayer?.stop(); mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
        try { vibrator?.cancel() } catch (_: Exception) {}
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ALARM)
    }

    private fun resolveSoundMode(): String {
        if (soundMode != "systemDefault") return soundMode
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return when (am.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "silent"
            AudioManager.RINGER_MODE_VIBRATE -> "vibrateOnly"
            else -> "vibrateBell"
        }
    }

    private fun startAlarmSound() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@CommuteAlarmService, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {}
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 600, 400)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun postAlarmNotification() {
        val fullScreen = Intent(this, AlarmActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val fullScreenPi = PendingIntent.getActivity(this, 0, fullScreen, piFlags)
        val stopPi = PendingIntent.getService(
            this, 1,
            Intent(this, CommuteAlarmService::class.java).apply { action = ACTION_STOP_ALARM },
            piFlags
        )
        val notif = NotificationCompat.Builder(this, CHANNEL_ALARM)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("목적지 접근")
            .setContentText("설정한 지점 반경에 들어왔습니다")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPi, true)
            .setContentIntent(fullScreenPi)
            .addAction(0, "끄기", stopPi)
            .build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ALARM, notif)
    }

    // ── 포그라운드 알림/채널 ───────────────────────────────
    private fun startForegroundMonitor() {
        val notif = NotificationCompat.Builder(this, CHANNEL_MONITOR)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("출퇴근 알림 대기 중")
            .setContentText("감시 시간대에 지점 접근을 확인합니다")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_MONITOR, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIF_MONITOR, notif)
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_MONITOR, "출퇴근 알림 감시",
                NotificationManager.IMPORTANCE_LOW)
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ALARM, "출퇴근 도착 알람",
                NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null) // 소리는 서비스가 직접 재생(USAGE_ALARM)
                enableVibration(false)
                setBypassDnd(true)
            }
        )
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try { fusedClient?.removeLocationUpdates(locationCallback) } catch (_: Exception) {}
        stopAlarm()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
