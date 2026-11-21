package com.sgchoisg.nakkda

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import kotlin.math.abs
import kotlin.math.max

/**
 * 손목 제스처 감지(자이로) — 두 손이 낚싯대·릴에 묶여 있을 때 녹화를 켜고 끄기 위함.
 *
 * - 비틀기(MODE_TWIST): 팔뚝 축(워치 x축) 회전. 바깥-안 비틀기 두 번 = 방향이 바뀌는 빠른 회전 4번.
 * - 털기(MODE_SHAKE): 팔뚝과 수직인 축(y 또는 z) 회전. 위-아래 털기 두 번 = 방향 전환 4번.
 *
 * 릴 감기(초당 1~2바퀴)와 구분하려고 각속도가 크고(THRESHOLD), 전환 간격이 짧으며(MAX_GAP_MS),
 * 다른 축보다 뚜렷이 우세한(DOMINANCE) 회전만 센다. 앱이 화면에 있을 때만 켠다.
 */
class WristGesture(context: Context, private val onGesture: () -> Unit) : SensorEventListener {

    private val sm = context.getSystemService(SensorManager::class.java)
    private val gyro = sm?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private var registered = false

    /** 0=끔, 1=비틀기, 2=털기(폰 설정 rec_gesture). 바뀌면 감지 상태를 처음부터. */
    var mode = MODE_TWIST
        set(v) {
            if (field == v) return
            field = v
            if (registered) { stop(); start() }
        }

    private var axis = -1          // 털기: 첫 회전에서 정한 축(1=y, 2=z)
    private var sign = 0           // 직전 회전 방향
    private var turns = 0          // 이번 제스처에서 센 방향 전환 수
    private var firstAt = 0L
    private var lastAt = 0L
    private var cooldownUntil = 0L

    fun start() {
        if (mode == MODE_OFF || registered || gyro == null) return
        reset()
        registered = sm?.registerListener(this, gyro, SAMPLING_US) == true
    }

    fun stop() {
        if (!registered) return
        sm?.unregisterListener(this)
        registered = false
    }

    private fun reset() {
        axis = -1; sign = 0; turns = 0
    }

    override fun onSensorChanged(e: SensorEvent) {
        val t = e.timestamp / 1_000_000L
        if (t < cooldownUntil) return
        // 앞 전환과 너무 멀어지면(느린 동작·릴 감기) 처음부터 다시 센다.
        if (turns > 0 && (t - lastAt > MAX_GAP_MS || t - firstAt > MAX_TOTAL_MS)) reset()
        val x = e.values[0]; val y = e.values[1]; val z = e.values[2]
        val v: Float
        val other: Float
        if (mode == MODE_TWIST) {
            v = x; other = max(abs(y), abs(z))
        } else {
            val a = if (axis >= 0) axis else if (abs(y) >= abs(z)) 1 else 2
            v = if (a == 1) y else z
            other = abs(x)
        }
        if (abs(v) < THRESHOLD || abs(v) < other * DOMINANCE) return
        val s = if (v > 0) 1 else -1
        if (s == sign) return // 같은 방향 회전이 이어지는 중
        if (turns == 0) {
            firstAt = t
            if (mode == MODE_SHAKE) axis = if (abs(y) >= abs(z)) 1 else 2
        }
        sign = s
        turns++
        lastAt = t
        Log.d(TAG, "turn $turns mode=$mode v=%.1f other=%.1f dt=%d".format(v, other, t - firstAt))
        if (turns >= TURNS) {
            Log.d(TAG, "gesture detected (mode=$mode)")
            reset()
            cooldownUntil = t + COOLDOWN_MS
            onGesture()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    companion object {
        const val MODE_OFF = 0
        const val MODE_TWIST = 1
        const val MODE_SHAKE = 2
        private const val TAG = "NakkdaGesture"
        private const val SAMPLING_US = 20_000      // 50Hz
        private const val THRESHOLD = 6f            // rad/s — 빠른 손목 동작만
        private const val DOMINANCE = 1.3f          // 다른 축 대비 우세 비율
        private const val TURNS = 4                 // 두 번 왕복 = 방향 전환 4번
        private const val MAX_GAP_MS = 350L         // 전환 사이 최대 간격
        private const val MAX_TOTAL_MS = 1_200L     // 제스처 전체 최대 길이
        private const val COOLDOWN_MS = 1_500L      // 감지 후 재감지 금지
    }
}
