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
        "cam_keep_sec" to 120, // 카메라 화면 켜짐 유지(조작 없을 때, 초)
        "rec_leave" to 0,      // 녹화 중 워치 앱/카메라 화면을 벗어나면(0=정지·저장, 1=계속 녹화)
        "rec_gesture" to 1,    // 손목 제스처 녹화 시작/정지(0=끔, 1=두 번 비틀기, 2=두 번 털기)
        "video_mode" to 0,     // 폰 동영상 모드(0=일반, 1=블랙박스) — 블랙박스면 워치 손목 제스처 끔
        "bb_min" to 2,         // 블랙박스 저장 길이(분)
    )
    private val BOOL_DEFAULTS = linkedMapOf(
        "keep_on" to false,    // 화면 항상 켜두기(기본 끔 — 켜두면 시간당 약 30% 배터리 소모)
        "vibrate" to false,    // 카운트 시 진동
        "show_clock" to true,  // 요약 화면에 시계 표시
        "show_elapsed" to true, // 요약 화면에 마지막 조과 경과 시간 표시
        "eco_colors" to false, // 카운터 절전 색상(배경 어둡게)
        "cam_preview" to true, // 워치에 폰 카메라 미리보기 전송
    )
    private val COLOR_KEYS = listOf("color_0", "color_1")

    /** 워치 카운터 팔레트(워치 PALETTE·폰 워치설정 화면과 순서·색 동일). */
    val PALETTE = intArrayOf(
        0xFF1565C0.toInt(), 0xFF1E88E5.toInt(), 0xFF00838F.toInt(), 0xFF00897B.toInt(),
        0xFF2E7D32.toInt(), 0xFF7CB342.toInt(), 0xFFF9A825.toInt(), 0xFFEF6C00.toInt(),
        0xFFD84315.toInt(), 0xFFC62828.toInt(), 0xFFAD1457.toInt(), 0xFF6A1B9A.toInt(),
        0xFF4527A0.toInt(), 0xFF455A64.toInt(), 0xFF37474F.toInt(), 0xFF263238.toInt(),
    )

    /** 카운터에 없는 어종 색(폰 CatchTideChart.palette와 동일). */
    val OTHER_COLORS = intArrayOf(
        0xFFE53935.toInt(), 0xFF2E7D32.toInt(), 0xFFEC407A.toInt(), 0xFFFFA000.toInt(),
    )

    /** 카운터 좌/우 어종 → 카운터 색(ARGB). 폰 차트·지도·조과 요약이 워치와 같은 색을 쓰게 한다.
     *  색은 워치·폰 어디서 바꿔도 color_0/1로 동기화되므로 여기 한 곳에서 읽는다. */
    fun counterColors(ctx: Context): Map<String, Int> {
        val species = CatchLogService.loadSpecies(ctx)
        val p = prefs(ctx)
        val defaults = intArrayOf(0, 4) // 워치 기본값과 동일
        val m = LinkedHashMap<String, Int>()
        for (i in 0 until minOf(2, species.size)) {
            val idx = p.getInt("color_$i", defaults[i]).coerceIn(0, PALETTE.size - 1)
            m.putIfAbsent(species[i], PALETTE[idx])
        }
        return m
    }

    /** 어종 이름 목록(표시 순서)의 색 — 카운터 어종은 카운터 색, 나머지는 OTHER_COLORS 차례로. */
    fun speciesColors(ctx: Context, names: List<String>): IntArray {
        val fixed = counterColors(ctx)
        val others = names.filter { it !in fixed }
        return IntArray(names.size) { i ->
            fixed[names[i]] ?: OTHER_COLORS[others.indexOf(names[i]) % OTHER_COLORS.size]
        }
    }

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
