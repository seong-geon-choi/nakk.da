package com.sgchoisg.nakkda

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

/**
 * 폰에서 관리하는 워치 앱 설정. 폰 prefs에 저장하고 Data Layer DataItem(/nakkda/settings)으로
 * 워치에 동기화한다(워치가 꺼져 있어도 다시 연결되면 전달됨).
 *
 * 색상(color_0/1)은 워치에서도 길게 눌러 바꿀 수 있어 양방향이다. 폰이 아직 색을 모르면
 * DataItem에 색 키를 넣지 않아, 워치에서 고른 기존 색을 기본값으로 덮어쓰지 않는다.
 */
object WatchSettings {
    const val PATH = "/nakkda/settings"
    private const val PREFS = "watch_settings"

    // 워치와 동일한 기본값.
    private val INT_DEFAULTS = linkedMapOf(
        "bright_on" to 0,      // 켜짐 밝기 %(0=시스템 밝기 따름, 10~100)
        "dim_level" to 30,     // 어두울 때 밝기 %(1~50, 체감 기준)
        "dim_idle_sec" to 15,  // 어둡게 되기까지 초(0=어둡게 안 함)
        "start_page" to 1,     // 시작 화면(0=그래프, 1=카운터, 2=카메라)
    )
    private val BOOL_DEFAULTS = linkedMapOf(
        "keep_on" to false,    // 화면 항상 켜두기(기본 끔 — 켜두면 시간당 약 30% 배터리 소모)
        "vibrate" to false,    // 카운트 시 진동
        "show_clock" to true,  // 요약 화면에 시계 표시
        "show_elapsed" to true, // 요약 화면에 마지막 조과 경과 시간 표시
        "eco_colors" to false, // 카운터 절전 색상(배경 어둡게)
    )
    private val COLOR_KEYS = listOf("color_0", "color_1")

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 현재 설정(기본값 적용). 색은 알고 있을 때만 포함. */
    fun get(ctx: Context): Map<String, Any> {
        val p = prefs(ctx)
        val m = LinkedHashMap<String, Any>()
        for ((k, d) in INT_DEFAULTS) m[k] = p.getInt(k, d)
        for ((k, d) in BOOL_DEFAULTS) m[k] = p.getBoolean(k, d)
        for (k in COLOR_KEYS) if (p.contains(k)) m[k] = p.getInt(k, 0)
        return m
    }

    /** Flutter에서 받은 값들을 저장하고 워치로 전송. */
    fun set(ctx: Context, values: Map<String, Any?>) {
        val e = prefs(ctx).edit()
        for ((k, v) in values) {
            when {
                (k in INT_DEFAULTS || k in COLOR_KEYS) && v is Number -> e.putInt(k, v.toInt())
                k in BOOL_DEFAULTS && v is Boolean -> e.putBoolean(k, v)
            }
        }
        e.apply()
        push(ctx)
    }

    /** 워치에서 색을 바꿨다는 알림(payload "side,idx")을 반영. */
    fun setColorFromWatch(ctx: Context, payload: ByteArray) {
        val parts = String(payload).split(",")
        val side = parts.getOrNull(0)?.toIntOrNull() ?: return
        val idx = parts.getOrNull(1)?.toIntOrNull() ?: return
        if (side !in 0..1) return
        prefs(ctx).edit().putInt("color_$side", idx).apply()
        push(ctx)
    }

    fun push(ctx: Context) {
        try {
            val values = get(ctx)
            val req = PutDataMapRequest.create(PATH).apply {
                for ((k, v) in values) {
                    when (v) {
                        is Int -> dataMap.putInt(k, v)
                        is Boolean -> dataMap.putBoolean(k, v)
                    }
                }
            }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(ctx).putDataItem(req)
        } catch (_: Exception) {
            // 워치/Play 서비스 미지원 기기 — 무시.
        }
    }
}
