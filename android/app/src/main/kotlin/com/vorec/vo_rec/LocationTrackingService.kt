package com.sgchoisg.nakkda

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.ApplicationInfo
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
        // 배터리: 속도 구간별 요청 간격(저장 간격이 넓은 순항·고속은 GPS도 덜 자주 켠다).
        //   조업/정지·저속이동 10초, 순항(300m 저장) 20초, 고속(1000m 저장) 30초.
        private val TIER_INTERVAL_MS = longArrayOf(10_000L, 10_000L, 20_000L, 30_000L)
        // 배터리: 위치는 계속 잡되 최대 1분치를 모아 한 번에 전달(그동안 CPU가 잠들 수 있음).
        private const val MAX_BATCH_DELAY_MS = 60_000L
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

        // ── 위치 흔들림(노이즈) 억제 ───────────────────────────────
        // 실내·지하 등 GPS가 약하면 와이파이·기지국 위치(오차 수십~수백 m)가 서로 다른 지점을
        // 오가며 '이동'처럼 보인다. 두 위치의 오차 합 × 이 배수보다 덜 움직였으면 흔들림으로 본다
        // (저장 판정·정지 판정 모두).
        private const val NOISE_FACTOR = 1.5f
        // 지하철·실내처럼 GPS 없이 와이파이·기지국으로 잡힌 '거친' 위치(오차가 이보다 큼).
        // 거친 위치는 역에 설 때만 띄엄띄엄 들어오므로 속도 적응형 간격(300~1000m)을 적용하지 않고
        // 흔들림 기준도 두 오차 중 큰 쪽(1배)으로 낮춰 역 하나 거리 이동이 버려지지 않게 한다.
        // (정지 판정은 기존 기준 유지, 제자리 흔들림은 되돌아오는 점 제거가 거른다.)
        private const val COARSE_ACCURACY_M = 60f
        // 흔들림 기준·정지 반경의 상한. 오차 300~400m 위치가 기준이 되면 다음 역(약 700m+)까지
        // 흔들림으로 버리거나, 열차 이동을 체류로 잘못 잡으므로 역 간격보다 충분히 작게 묶는다.
        private const val NOISE_CAP_M = 200f
        private const val DIAG_KEEP_DAYS = 7 // 디버그 진단 기록 보관 일수
        // 되돌아오는 점(A→B→A) 제거: 새 점이 직전 확정점 근처로 돌아오면 그 사이 점(B)을 버린다.
        private const val BOUNCE_WINDOW_MS = 2 * 60 * 1000L // B~새 점 사이가 이 시간 안일 때만
        private const val BOUNCE_RATIO = 0.5f              // A~새 점 거리 < B까지 거리 × 이 비율

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
            // 실행 중이면 모아 둔 위치를 받아 저장한 뒤 종료(마지막 최대 1분치 손실 방지).
            val svc = instance
            if (svc != null) svc.flushThenStop()
            else context.stopService(Intent(context, LocationTrackingService::class.java))
        }

        @Volatile private var instance: LocationTrackingService? = null

        /** 모아 둔(일괄 전달 대기) 위치를 즉시 받아 처리한다 — 지도 화면 진입 시 최신 경로·현재 위치용.
         *  기록 중이 아니면 바로 done. done은 메인 스레드에서 호출된다. */
        fun flush(done: () -> Unit) {
            val svc = instance
            val task = try { svc?.fusedClient?.flushLocations() } catch (_: Exception) { null }
            if (svc == null || task == null) {
                done()
                return
            }
            // 플러시된 위치 콜백(메인 루퍼)이 처리된 뒤에 done.
            task.addOnCompleteListener { svc.mainHandler.post(done) }
        }
    }

    private var fusedClient: FusedLocationProviderClient? = null
    private var minDistanceMeters: Float = 50f   // 정지·조업 기준 거리(사용자 설정, 기본 50m)
    private var lastSavedLocation: Location? = null  // 마지막으로 받아들인 점(보류 중인 점 포함)
    // 되돌아오는 점 제거: 받아들인 점은 다음 점을 볼 때까지 저장을 보류(held)했다가 확정한다.
    private var heldLocation: Location? = null       // 저장 보류 중인 최신 점
    private var committedLocation: Location? = null  // 마지막으로 저장(확정)된 점

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
    private var anchorSinceWallMs = 0L             // 같은 시각(wall clock) — 체류 시작 시각으로 기록
    private var stillStartWallMs = 0L              // 체류 시작 시각(wall clock, 체류지점 기록용)
    private var sensorManager: SensorManager? = null
    private var significantMotion: Sensor? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    // 기준점에 STILL_ENTER_MS 동안 새 위치가 안 와도 정지로 판정한다.
    // 이동 중 요청은 최소 이동거리(minDistanceMeters) 필터가 있어 가만히 있으면 픽스가 오지 않으므로,
    // 픽스가 올 때만 판정하면 떠나는 순간에야 정지로 들어가 체류 시간이 0분이 된다.
    private val stillCheck = Runnable {
        val enterIfStill = Runnable {
            if (!isStill && anchorLocation != null &&
                SystemClock.elapsedRealtime() - anchorSinceMs >= STILL_ENTER_MS
            ) enterStill()
        }
        val flush = try { fusedClient?.flushLocations() } catch (_: Exception) { null }
        if (flush == null) enterIfStill.run()
        else flush.addOnCompleteListener { mainHandler.post(enterIfStill) }
    }

    // 저전력 모드 중 유의미한 움직임이 감지되면 즉시 이동 모드로 복귀(권한 불필요).
    private val motionListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            mainHandler.post { exitStill() }
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            // 일괄 전달(MAX_BATCH_DELAY_MS)이면 여러 위치가 시간순으로 온다 — 모두 처리.
            for (location in result.locations) onLocation(location)
            // 속도 구간이 바뀌었으면 요청 간격도 바꾼다.
            if (!isStill && requestedTier != speedTier) requestMoving()
        }
    }

    private fun onLocation(location: Location) {
        // 지나치게 부정확한 네트워크 픽스 제외 (지하에서도 합리적인 점만 기록)
        if (location.hasAccuracy() && location.accuracy > MAX_ACCURACY_METERS) {
            diag(location, "drop_accuracy")
            return
        }
        // 속도에 따라 저장 거리 임계값을 조정(고속일수록 크게 → 점 수 감소).
        // (lastFixLocation 갱신 '전에' 호출 — adaptiveThresholdMeters·방위 계산이 직전 픽스를 씀.)
        // 거친 위치(지하철 역 등)는 속도 구간과 무관하게 사용자 설정 간격으로 저장한다.
        val coarse = isCoarse(location)
        val adaptive = adaptiveThresholdMeters(location)
        val threshold = if (coarse) minDistanceMeters else adaptive
        val lf = lastFixLocation
        if (lf != null && lf.distanceTo(location) >= BEARING_MIN_MOVE_M) {
            lastTravelBearing = lf.bearingTo(location)
        }
        lastFixLocation = location
        val last = lastSavedLocation
        val movedFromSaved = last?.distanceTo(location) ?: Float.MAX_VALUE
        // 위치 오차보다 덜 움직였으면 흔들림 — 저장 거리 기준을 넘어도 저장하지 않는다.
        val noise = if (coarse) coarseNoiseMeters(last, location) else noiseMeters(last, location)
        val distanceHit = movedFromSaved >= threshold && movedFromSaved >= noise
        // 변침 보존: 이동 구간(tier≥1)에서 방위가 크게 꺾이면 거리 미달이라도 코너로 저장.
        val cornerHit = !distanceHit && speedTier >= 1 &&
            movedFromSaved >= maxOf(CORNER_MIN_MOVE_M, noise) &&
            lastTravelBearing != null && lastSavedBearing != null &&
            bearingDiff(lastTravelBearing!!, lastSavedBearing!!) >= CORNER_ANGLE_DEG
        diag(location, when {
            distanceHit -> "save"
            cornerHit -> "save_corner"
            movedFromSaved < threshold -> "skip_distance"
            else -> "skip_noise"
        }, threshold, noise, movedFromSaved)
        if (distanceHit || cornerHit) acceptPoint(location, threshold)
        evaluateStillness(location)
    }

    /**
     * 현재 속도로 저장 거리 임계값을 결정한다. 조업/정지(저속)는 사용자 설정 거리,
     * 순항은 300m, 고속은 1000m. 속도는 픽스의 speed(없으면 직전 픽스와의 거리/시간)를
     * 이동평균으로 평활하고, 구간 경계엔 히스테리시스를 둬 떨림을 막는다.
     * (lastFixLocation 갱신 '전에' 호출할 것 — 폴백이 직전 픽스를 쓴다.)
     */
    private fun adaptiveThresholdMeters(location: Location): Float {
        val raw = if (isCoarse(location)) {
            // 거친 위치(지하·실내)는 위치 점프로 속도가 부풀려지므로 속도를 갱신하지 않는다.
            smoothedSpeedMps
        } else if (location.hasSpeed()) {
            location.speed
        } else {
            val lf = lastFixLocation
            if (lf != null && !isCoarse(lf)) {
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

    /** GPS 없이 와이파이·기지국으로 잡힌 거친 위치인지(지하철 역·실내). */
    private fun isCoarse(l: Location): Boolean = l.hasAccuracy() && l.accuracy > COARSE_ACCURACY_M

    /** 거친 위치의 흔들림 거리 — 두 오차 중 큰 쪽. 역 사이 이동(약 1km)이 흔들림으로 버려지지 않게. */
    private fun coarseNoiseMeters(a: Location?, b: Location): Float {
        fun acc(l: Location?) = if (l != null && l.hasAccuracy()) l.accuracy else 0f
        return minOf(maxOf(acc(a), acc(b)), NOISE_CAP_M)
    }

    /** 두 위치의 오차를 감안한 흔들림 거리(m) — 이보다 덜 움직였으면 실제 이동으로 보지 않는다. */
    private fun noiseMeters(a: Location?, b: Location): Float {
        fun acc(l: Location?) = if (l != null && l.hasAccuracy()) l.accuracy else 0f
        return minOf(NOISE_FACTOR * (acc(a) + acc(b)), NOISE_CAP_M)
    }

    /**
     * 저장 대상이 된 점을 받아들인다. 바로 저장하지 않고 보류했다가, 다음 점이 보류점 이전
     * 위치(직전 확정점) 근처로 금방 되돌아오면 보류점을 튄 점(A→B→A의 B)으로 보고 버린다.
     */
    private fun acceptPoint(c: Location, threshold: Float) {
        val h = heldLocation
        val p = committedLocation
        if (h != null && p != null && isBounce(p, h, c)) {
            diag(h, "drop_bounce")
            heldLocation = null
            lastSavedLocation = p
            // 튄 점을 버린 뒤 새 점을 직전 확정점 기준으로 다시 판단(대개 제자리라 버려진다).
            val moved = p.distanceTo(c)
            if (moved < threshold || moved < noiseMeters(p, c)) return
        } else if (h != null) {
            commit(h)
        }
        heldLocation = c
        lastSavedLocation = c
        lastSavedBearing = lastTravelBearing ?: lastSavedBearing
    }

    /** p(확정)→h(보류)→c(새 점)에서 c가 h 직후 p 근처로 돌아왔으면 h는 튄 점. */
    private fun isBounce(p: Location, h: Location, c: Location): Boolean {
        if (c.time - h.time > BOUNCE_WINDOW_MS) return false
        val back = p.distanceTo(c)
        return back < BOUNCE_RATIO * minOf(p.distanceTo(h), h.distanceTo(c))
    }

    private fun commit(l: Location) {
        savePoint(l.latitude, l.longitude, l.time)
        committedLocation = l
    }

    /** 보류 중인 점을 확정 저장(정지 진입·기록 종료 시 — 마지막 위치를 잃지 않게). */
    private fun flushHeld() {
        val h = heldLocation ?: return
        heldLocation = null
        commit(h)
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
            if (anchor == null || anchor.distanceTo(location) > stillRadius(anchor, location)) exitStill()
            return
        }
        val anchor = anchorLocation
        if (anchor == null || anchor.distanceTo(location) > stillRadius(anchor, location)) {
            anchorLocation = location
            anchorSinceMs = location.elapsedRealtimeNanos / 1_000_000L
            anchorSinceWallMs = location.time
            mainHandler.removeCallbacks(stillCheck)
            mainHandler.postDelayed(stillCheck,
                (STILL_ENTER_MS - (SystemClock.elapsedRealtime() - anchorSinceMs)).coerceAtLeast(0L))
            return
        }
        if (location.elapsedRealtimeNanos / 1_000_000L - anchorSinceMs >= STILL_ENTER_MS) enterStill()
    }

    /** 정지 판정 반경 — 실내처럼 위치 오차가 크면 그만큼 넓혀 흔들림을 이동으로 보지 않는다. */
    private fun stillRadius(anchor: Location, location: Location): Float =
        maxOf(STILL_RADIUS_M, noiseMeters(anchor, location))

    @SuppressLint("MissingPermission")
    private fun enterStill() {
        if (isStill) return
        isStill = true
        flushHeld() // 머무는 곳의 마지막 점을 확정
        mainHandler.removeCallbacks(stillCheck)
        // 체류 시작 = 기준점에 도착한 시각(정지 판정까지 기다린 3분 포함).
        stillStartWallMs = if (anchorSinceWallMs > 0L) anchorSinceWallMs else System.currentTimeMillis()
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

    private var requestedTier = -1 // 지금 요청 중인 이동 요청의 속도 구간

    private fun movingRequest(): LocationRequest {
        requestedTier = speedTier
        val interval = TIER_INTERVAL_MS.getOrElse(speedTier) { UPDATE_INTERVAL_MS }
        return LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, interval)
            .setMinUpdateIntervalMillis(FASTEST_INTERVAL_MS)
            .setMinUpdateDistanceMeters(minDistanceMeters)
            .setMaxUpdateDelayMillis(MAX_BATCH_DELAY_MS)
            .setWaitForAccurateLocation(false)
            .build()
    }

    /** 현재 속도 구간에 맞는 이동 요청으로 (다시) 등록. 같은 콜백이면 기존 요청을 대체한다. */
    @SuppressLint("MissingPermission")
    private fun requestMoving() {
        try {
            fusedClient?.requestLocationUpdates(movingRequest(), locationCallback, Looper.getMainLooper())
        } catch (_: SecurityException) {}
    }

    private val dateChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            flushThenStop()
        }
    }

    // 종료 대기 중(모아 둔 위치 받는 중). 그 사이 다시 시작하면 false로 돌려 종료를 취소한다.
    private var stopping = false
    private val stopNow = Runnable { if (stopping) stopSelf() }

    /** 모아 둔(일괄 전달 대기) 위치를 먼저 받아 처리한 뒤 종료. 응답이 없으면 3초 뒤 그냥 종료. */
    private fun flushThenStop() {
        if (stopping) return
        stopping = true
        mainHandler.postDelayed(stopNow, 3_000L)
        val task = try { fusedClient?.flushLocations() } catch (_: Exception) { null }
        if (task == null) {
            mainHandler.removeCallbacks(stopNow)
            stopSelf()
            return
        }
        task.addOnCompleteListener {
            mainHandler.post {
                mainHandler.removeCallbacks(stopNow)
                if (stopping) stopSelf()
            }
        }
    }

    // 기록을 시작한 날짜 — 자정 자동 종료 시 '어제' 메모에 조과 요약을 넣기 위해 보관.
    private var trackDate = CatchSummary.today()

    override fun onCreate() {
        super.onCreate()
        instance = this
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
        pruneDiag()

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
            flushThenStop()
            return START_NOT_STICKY
        }
        // 종료 대기 중에 다시 시작되면 종료를 취소한다.
        if (stopping) {
            stopping = false
            mainHandler.removeCallbacks(stopNow)
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
        if (instance === this) instance = null
        mainHandler.removeCallbacks(stillCheck)
        if (isStill) { try { finalizeStay() } catch (_: Exception) {} }
        try { flushHeld() } catch (_: Exception) {}
        try { fusedClient?.removeLocationUpdates(locationCallback) } catch (_: Exception) {}
        try { significantMotion?.let { sensorManager?.cancelTriggerSensor(motionListener, it) } } catch (_: Exception) {}
        try { unregisterReceiver(dateChangedReceiver) } catch (_: Exception) {}
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(PREFS_ACTIVE_KEY, false).apply()
        // 경로 기록 종료 = 낚시 종료로 보고 그날 메모에 조과 요약 기록(조과 0이면 생략).
        val ctx = applicationContext
        val date = trackDate
        Thread { try { CatchSummary.write(ctx, date) } catch (_: Exception) {} }.start()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    private val timeFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    // ── 경로 진단 기록(디버그 빌드에서 경로 저장 중에만) ──────────────────
    // 받은 위치마다 한 줄: 시각,위도,경도,오차,속도,속도구간,거친위치,판정,임계,흔들림,이동거리.
    // 파일: <외부 앱 폴더>/track_diag/track_diag_yyyyMMdd.csv (7일 지난 파일은 시작 시 삭제).
    private val diagEnabled by lazy { (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0 }
    private val diagDir by lazy { getExternalFilesDir("track_diag") }
    private val diagDayFmt = SimpleDateFormat("yyyyMMdd", Locale.US)

    private fun diag(l: Location, decision: String, threshold: Float = 0f, noise: Float = 0f, moved: Float = -1f) {
        if (!diagEnabled) return
        try {
            val dir = diagDir ?: return
            val f = java.io.File(dir, "track_diag_${diagDayFmt.format(java.util.Date())}.csv")
            val header = !f.exists()
            f.appendText(buildString {
                if (header) append("time,lat,lng,acc,speed,tier,coarse,decision,threshold,noise,moved\n")
                append(timeFmt.format(java.util.Date(l.time))).append(',')
                append(l.latitude).append(',').append(l.longitude).append(',')
                append(if (l.hasAccuracy()) l.accuracy.toInt() else -1).append(',')
                append(if (l.hasSpeed()) "%.1f".format(Locale.US, l.speed) else "").append(',')
                append(speedTier).append(',').append(isCoarse(l)).append(',').append(decision).append(',')
                append(threshold.toInt()).append(',').append(noise.toInt()).append(',')
                append(if (moved == Float.MAX_VALUE || moved < 0f) "" else moved.toInt().toString())
                append('\n')
            })
        } catch (_: Exception) {}
    }

    private fun pruneDiag() {
        if (!diagEnabled) return
        try {
            val cutoff = System.currentTimeMillis() - DIAG_KEEP_DAYS * 24 * 60 * 60 * 1000L
            diagDir?.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
        } catch (_: Exception) {}
    }

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
