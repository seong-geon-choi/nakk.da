package com.sgchoisg.nakkda

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
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
        const val PREFS_STAY_KEY = "pending_stays"
        const val PREFS_ACTIVE_KEY = "tracking_active"
        const val PREFS_QUICK_LAUNCH_MODE_KEY = "quick_launch_mode"
        const val PREFS_SHAKE_THRESHOLD_KEY = "shake_threshold_g"
        const val PREFS_SHAKE_ACTION_KEY = "shake_action"
        @JvmField val pendingLock = Any()
        private const val EXTRA_INTERVAL = "intervalMeters"
        private const val UPDATE_INTERVAL_MS = 10000L  // 이동 중 위치 갱신 주기
        private const val FASTEST_INTERVAL_MS = 2000L  // 최소 갱신 간격
        private const val MAX_ACCURACY_METERS = 1000f  // 이보다 부정확한 픽스는 제외
        // 정지 감지(배터리 절감): 반경 안에서 이 시간 이상 머물면 저전력 모드로 전환
        private const val STILL_ENTER_MS = 3 * 60 * 1000L   // 3분 이상 정지 시 진입
        private const val STILL_RADIUS_M = 40f              // 정지로 간주할 반경
        private const val STILL_INTERVAL_MS = 3 * 60 * 1000L // 정지 중 위치 확인 주기(저전력)

        // ── 속도 적응형 저장(4단계) ────────────────────────────────
        // 정지·조업은 사용자 설정 거리, 그 이상은 속도 구간별 고정 거리로 저장해 고속
        // 구간의 과도한 점 생성을 줄인다.
        //   조업/정지  ( < 2.0 m/s, ~7km/h)  → 사용자 설정(minDistanceMeters)
        //   저속이동   (2.0~5.6,  ~7–20km/h) → 100m
        //   순항       (5.6~11,  ~20–40km/h) → 300m
        //   고속       ( ≥ 11,    ~40km/h+)  → 1000m
        private const val SPEED_FISHING_MAX_MPS = 2.0f   // 조업↔저속이동 경계
        private const val SPEED_SLOW_MAX_MPS = 5.6f      // 저속이동↔순항 경계
        private const val SPEED_FAST_MIN_MPS = 11.0f     // 순항↔고속 경계
        private const val THRESHOLD_SLOW_M = 100f        // 저속이동
        private const val THRESHOLD_CRUISE_M = 300f      // 순항
        private const val THRESHOLD_FAST_M = 1000f       // 고속
        private const val SPEED_HYSTERESIS_MPS = 1.0f    // 구간 경계 떨림 방지 여유
        private const val SPEED_EMA_ALPHA = 0.4f         // 속도 이동평균 가중치

        // ── 변침(코너) 보존 ───────────────────────────────────────
        // 큰 거리 임계값(이동 구간)에서 급선회가 직선으로 뭉개지지 않도록, 진행
        // 방향이 크게 꺾이면 거리 미달이라도 해당 지점을 저장해 항로 모양을 지킨다.
        private const val CORNER_ANGLE_DEG = 30f    // 직전 저장 방위 대비 이만큼 꺾이면 코너
        private const val CORNER_MIN_MOVE_M = 20f   // 직전 저장점 대비 최소 이동(지터 방지)
        private const val BEARING_MIN_MOVE_M = 8f   // 이 거리 이상 이동해야 방위 신뢰

        fun getQuickLaunchMode(context: Context): String =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(PREFS_QUICK_LAUNCH_MODE_KEY, "shake") ?: "shake"

        fun getShakeThresholdG(context: Context): Float =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getFloat(PREFS_SHAKE_THRESHOLD_KEY, 3.5f)

        fun getShakeAction(context: Context): String =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(PREFS_SHAKE_ACTION_KEY, "voice") ?: "voice"

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
    private var minDistanceMeters: Float = 50f   // 정지·조업 기준 거리(사용자 설정, 기본 50m)
    private var lastSavedLocation: Location? = null

    // 속도 적응형 저장: 직전 픽스(속도 폴백용) + 평활 속도 + 현재 속도 구간(히스테리시스).
    private var lastFixLocation: Location? = null
    private var smoothedSpeedMps = 0f
    private var speedTier = 0  // 0=조업/정지, 1=저속이동, 2=순항, 3=고속
    // 구간 상향 경계(tier i→i+1 기준 속도). 하향은 각 경계 − 히스테리시스.
    private val speedBounds = floatArrayOf(
        SPEED_FISHING_MAX_MPS, SPEED_SLOW_MAX_MPS, SPEED_FAST_MIN_MPS)

    // 변침 보존: 신뢰 가능한 최근 진행 방위 + 마지막 저장 시점의 진행 방위.
    private var lastTravelBearing: Float? = null
    private var lastSavedBearing: Float? = null

    // 정지 감지 상태
    private var isStill = false
    private var anchorLocation: Location? = null  // 정지 판정 기준점
    private var anchorSinceMs = 0L                 // 기준점에 머물기 시작한 시각(elapsedRealtime)
    private var stillStartWallMs = 0L              // 체류 시작 시각(wall clock, 체류지점 기록용)
    private var sensorManager: SensorManager? = null
    private var significantMotion: Sensor? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    // 저전력 모드 중 유의미한 움직임이 감지되면 즉시 이동 모드로 복귀(권한 불필요).
    private val motionListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            mainHandler.post { exitStill() }
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            // 지나치게 부정확한 네트워크 픽스 제외 (지하에서도 합리적인 점만 기록)
            if (location.hasAccuracy() && location.accuracy > MAX_ACCURACY_METERS) return
            // 속도에 따라 저장 거리 임계값을 조정(고속일수록 크게 → 점 수 감소).
            // (lastFixLocation 갱신 '전에' 호출 — adaptiveThresholdMeters·방위 계산이 직전 픽스를 씀.)
            val threshold = adaptiveThresholdMeters(location)
            val lf = lastFixLocation
            if (lf != null && lf.distanceTo(location) >= BEARING_MIN_MOVE_M) {
                lastTravelBearing = lf.bearingTo(location)
            }
            lastFixLocation = location
            val last = lastSavedLocation
            val movedFromSaved = last?.distanceTo(location) ?: Float.MAX_VALUE
            val distanceHit = movedFromSaved >= threshold
            // 변침 보존: 이동 구간(tier≥1)에서 방위가 크게 꺾이면 거리 미달이라도 코너로 저장.
            val cornerHit = !distanceHit && speedTier >= 1 &&
                movedFromSaved >= CORNER_MIN_MOVE_M &&
                lastTravelBearing != null && lastSavedBearing != null &&
                bearingDiff(lastTravelBearing!!, lastSavedBearing!!) >= CORNER_ANGLE_DEG
            if (distanceHit || cornerHit) {
                lastSavedLocation = location
                lastSavedBearing = lastTravelBearing ?: lastSavedBearing
                savePoint(location.latitude, location.longitude, location.time)
            }
            evaluateStillness(location)
        }
    }

    /**
     * 현재 속도로 저장 거리 임계값을 결정한다. 조업/정지(저속)는 사용자 설정 거리,
     * 순항은 300m, 고속은 1000m. 속도는 픽스의 speed(없으면 직전 픽스와의 거리/시간)를
     * 이동평균으로 평활하고, 구간 경계엔 히스테리시스를 둬 떨림을 막는다.
     * (lastFixLocation 갱신 '전에' 호출할 것 — 폴백이 직전 픽스를 쓴다.)
     */
    private fun adaptiveThresholdMeters(location: Location): Float {
        val raw = if (location.hasSpeed()) {
            location.speed
        } else {
            val lf = lastFixLocation
            if (lf != null) {
                val dt = (location.time - lf.time) / 1000f
                if (dt > 0.5f) lf.distanceTo(location) / dt else smoothedSpeedMps
            } else 0f
        }.coerceAtLeast(0f)
        smoothedSpeedMps = SPEED_EMA_ALPHA * raw + (1f - SPEED_EMA_ALPHA) * smoothedSpeedMps
        val v = smoothedSpeedMps
        val h = SPEED_HYSTERESIS_MPS
        // 상향: 현재 구간 상단 경계+h 초과 시 올림 / 하향: 하단 경계−h 미만 시 내림(여러 단계 허용).
        while (speedTier < speedBounds.size && v >= speedBounds[speedTier] + h) speedTier++
        while (speedTier > 0 && v < speedBounds[speedTier - 1] - h) speedTier--
        return when (speedTier) {
            0 -> minDistanceMeters   // 조업/정지: 사용자 설정
            1 -> THRESHOLD_SLOW_M    // 저속이동: 100m
            2 -> THRESHOLD_CRUISE_M  // 순항: 300m
            else -> THRESHOLD_FAST_M // 고속: 1000m
        }
    }

    /** 두 방위(도)의 최소 사잇각(0~180). bearingTo는 −180~180을 반환하므로 360 보정. */
    private fun bearingDiff(a: Float, b: Float): Float {
        val d = Math.abs(a - b) % 360f
        return if (d > 180f) 360f - d else d
    }

    // 연속 픽스로 정지/이동을 판정하고 모드를 전환한다.
    private fun evaluateStillness(location: Location) {
        if (isStill) {
            // 저전력 폴링 중에도 반경을 벗어나면 이동 모드로 복귀
            val anchor = anchorLocation
            if (anchor == null || anchor.distanceTo(location) > STILL_RADIUS_M) exitStill()
            return
        }
        val anchor = anchorLocation
        if (anchor == null || anchor.distanceTo(location) > STILL_RADIUS_M) {
            anchorLocation = location
            anchorSinceMs = SystemClock.elapsedRealtime()
            return
        }
        if (SystemClock.elapsedRealtime() - anchorSinceMs >= STILL_ENTER_MS) enterStill()
    }

    @SuppressLint("MissingPermission")
    private fun enterStill() {
        if (isStill) return
        isStill = true
        stillStartWallMs = System.currentTimeMillis()
        // 정지 진입 — 속도 구간을 조업(저속)으로 리셋(복귀 시 저속부터 다시 평가).
        smoothedSpeedMps = 0f
        speedTier = 0
        // 방위 상태도 리셋 — 정지 후 복귀 첫 구간을 새 방위로 다시 추적.
        lastTravelBearing = null
        lastSavedBearing = null
        // 저전력·장주기 요청으로 교체
        val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, STILL_INTERVAL_MS)
            .setMinUpdateDistanceMeters(STILL_RADIUS_M)
            .setWaitForAccurateLocation(false)
            .build()
        try {
            fusedClient?.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
        } catch (_: SecurityException) {}
        // 움직임 감지 센서로 즉시 복귀(일회성 트리거)
        significantMotion?.let { sensorManager?.requestTriggerSensor(motionListener, it) }
    }

    @SuppressLint("MissingPermission")
    private fun exitStill() {
        if (!isStill) return
        finalizeStay()
        isStill = false
        significantMotion?.let { sensorManager?.cancelTriggerSensor(motionListener, it) }
        anchorLocation = null
        try {
            fusedClient?.requestLocationUpdates(movingRequest(), locationCallback, Looper.getMainLooper())
        } catch (_: SecurityException) {}
    }

    // 체류(정지) 구간을 종료 시점에 기록한다: 기준점 좌표 + 시작~종료 시각.
    private fun finalizeStay() {
        val anchor = anchorLocation ?: return
        if (stillStartWallMs <= 0L) return
        saveStay(anchor.latitude, anchor.longitude, stillStartWallMs, System.currentTimeMillis())
        stillStartWallMs = 0L
    }

    private fun movingRequest(): LocationRequest =
        LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(FASTEST_INTERVAL_MS)
            .setMinUpdateDistanceMeters(minDistanceMeters)
            .setWaitForAccurateLocation(false)
            .build()

    private val dateChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(SENSOR_SERVICE) as? SensorManager
        significantMotion = sensorManager?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
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
        isStill = false
        anchorLocation = null
        try {
            fusedClient?.requestLocationUpdates(movingRequest(), locationCallback, Looper.getMainLooper())
        } catch (_: SecurityException) {
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        if (isStill) { try { finalizeStay() } catch (_: Exception) {} }
        try { fusedClient?.removeLocationUpdates(locationCallback) } catch (_: Exception) {}
        try { significantMotion?.let { sensorManager?.cancelTriggerSensor(motionListener, it) } } catch (_: Exception) {}
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

    private fun saveStay(lat: Double, lng: Double, startMs: Long, endMs: Long) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        synchronized(pendingLock) {
            val arr = try {
                JSONArray(prefs.getString(PREFS_STAY_KEY, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            arr.put("$lat,$lng,${timeFmt.format(java.util.Date(startMs))},${timeFmt.format(java.util.Date(endMs))}")
            prefs.edit().putString(PREFS_STAY_KEY, arr.toString()).commit()
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
