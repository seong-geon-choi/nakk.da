package com.sgchoisg.nakkda

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.GestureDetector
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import org.json.JSONArray
import kotlin.math.abs

/**
 * 잠금화면 위 조과 카운터 화면.
 * - 어종별 3자리 숫자판(6가지 스킨). 각 카운터를 좌/우로 쓸면 그 카운터의 스킨만 바뀐다(prefs 저장).
 * - 어종은 빈칸 제외(1개만 지정 시 1개, 둘 다면 2개). 카운트는 오늘 기록으로 시드됨.
 * - 방향: 가로=좌우 배열, 세로=상하 배열(회전 시 재생성으로 반영).
 * 기록 적재·알림 갱신은 CatchLogService(ADD/REMOVE)에 위임한다.
 */
class CatchCounterActivity : Activity() {

    private val styles = listOf("odometer", "clicker", "led", "neon", "nixie", "pill")

    private val species = ArrayList<String>()
    private val styleOf = ArrayList<String>() // 카운터별 스킨
    private val counts = ArrayList<Int>()
    private val digitCells = ArrayList<List<TextView>>()

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun prefs() = getSharedPreferences(CatchLogService.PREFS_NAME, MODE_PRIVATE)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // 엣지투엣지로 두고 아래에서 시스템 바 인셋만큼 패딩 → 가로모드에서도 내비바에 안 가림.
        WindowCompat.setDecorFitsSystemWindows(window, false)

        species.clear(); counts.clear(); digitCells.clear(); styleOf.clear()
        species.addAll(CatchLogService.loadSpecies(this))
        val saved = CatchLogService.loadStyles(this)
        val fileCounts = CatchLogService.loadCountsFromFile(this)
        for (i in species.indices) {
            counts.add(fileCounts[species[i]] ?: 0)
            val st = saved.getOrNull(i)
            styleOf.add(if (st != null && st in styles) st else "odometer")
        }

        setContentView(buildRoot())
    }

    // 화면 버튼으로 마지막으로 ± 한 시각(ms). 자기 변경의 파일 기록이 연타를
    // 못 따라잡아 과거값을 되읽는 깜빡임(2→1→2)을 막는 데 쓴다.
    private var lastLocalChangeMs = 0L

    // 리모컨/알림으로 집계가 바뀌면(서비스가 브로드캐스트) 화면을 즉시 다시 그린다.
    // 단, 방금 화면 버튼으로 누른 직후(연타)엔 파일 기록이 아직 못 따라잡아
    // 로컬값보다 작게 읽힐 수 있다 → 그때의 '하향'만 무시해 깜빡임(2→1→2)을 막고,
    // 외부(리모컨)로 늘어난 '상향'은 그대로 반영한다.
    private val countsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val fileCounts = CatchLogService.loadCountsFromFile(this@CatchCounterActivity)
            val recentLocal = System.currentTimeMillis() - lastLocalChangeMs < 800
            for (i in species.indices) {
                val f = fileCounts[species[i]] ?: 0
                if (recentLocal && f < counts[i]) continue // 기록 지연에 의한 일시적 하향 무시
                counts[i] = f
                updateDigits(i)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 파일에서 최신 집계를 다시 읽어 동기화(네이티브가 즉시 MD를 수정하므로 이게 정답값).
        refreshCounts()
        val filter = IntentFilter(CatchLogService.ACTION_COUNTS_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(countsReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(countsReceiver, filter)
        }
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(countsReceiver) } catch (_: Exception) {}
    }

    /** 파일 집계를 다시 읽어 모든 숫자판을 갱신. */
    private fun refreshCounts() {
        val fileCounts = CatchLogService.loadCountsFromFile(this)
        for (i in species.indices) {
            counts[i] = fileCounts[species[i]] ?: 0
            updateDigits(i)
        }
    }

    /**
     * 화면이 떠 있을 때 매핑된 **비미디어 키**(볼륨 등)를 ±로 처리.
     * 미디어 키는 서비스의 MediaSession으로 라우팅되므로 여기서 받지 않는다(중복 방지).
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!CatchLogService.isMediaKey(keyCode)) {
            val action = CatchLogService.actionForKey(this, keyCode)
            if (action != null) {
                val idx = action.substringAfter(':', "").toIntOrNull()
                if (idx != null && idx < species.size) {
                    change(idx, if (action.startsWith("add:")) +1 else -1)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    /** 회전 시 방향에 맞게 레이아웃을 다시 구성(가로=좌우/세로=상하). */
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        val fileCounts = CatchLogService.loadCountsFromFile(this)
        for (i in species.indices) counts[i] = fileCounts[species[i]] ?: 0
        digitCells.clear()
        setContentView(buildRoot())
    }

    // ── 스와이프로 스킨 순환(카운터별) ──────────────────────
    private fun saveStyles() {
        val arr = JSONArray(); for (s in styleOf) arr.put(s)
        prefs().edit().putString(CatchLogService.PREFS_STYLES_KEY, arr.toString()).apply()
    }

    private fun cycleStyle(index: Int, forward: Boolean) {
        val i = styles.indexOf(styleOf[index])
        styleOf[index] = styles[((i + if (forward) 1 else -1) + styles.size) % styles.size]
        saveStyles()
        recreate()
    }

    private fun unitSwipeDetector(index: Int): GestureDetector =
        GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onFling(
                e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float
            ): Boolean {
                val dx = e2.x - (e1?.x ?: e2.x)
                if (abs(dx) > dp(50) && abs(dx) > abs(e2.y - (e1?.y ?: e2.y))) {
                    cycleStyle(index, dx < 0) // 왼쪽으로 쓸면 다음 스킨
                    return true
                }
                return false
            }
        })

    // ── 레이아웃 ───────────────────────────────────────────
    private fun buildRoot(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0B1119"))
        }
        // 시스템 바(상태/내비) 인셋만큼 패딩을 더해 어떤 방향에서도 가리지 않게 한다.
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val b = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(dp(16) + b.left, dp(16) + b.top, dp(16) + b.right, dp(12) + b.bottom)
            insets
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(TextView(this).apply {
            text = "조과 기록"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            typeface = Typeface.DEFAULT_BOLD
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(smallButton("✕") { finish() })
        root.addView(header)

        if (species.isEmpty()) {
            root.addView(TextView(this).apply {
                text = "기록할 어종이 없습니다\n설정 > 조과 기록 어종에서 지정하세요"
                setTextColor(Color.parseColor("#B0BEC5"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                gravity = Gravity.CENTER
                setPadding(0, dp(40), 0, 0)
            })
            return root
        }

        val landscape =
            resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val box = LinearLayout(this).apply {
            orientation = if (landscape) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        for (i in species.indices) {
            val lp = if (landscape)
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            else
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.gravity = Gravity.CENTER
            box.addView(buildUnit(i), lp)
        }
        root.addView(box,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        root.addView(TextView(this).apply {
            text = "← 좌우로 쓸어 숫자판 바꾸기 →"
            setTextColor(Color.parseColor("#5A6b7a"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
        })
        return root
    }

    /** 어종 1개 단위: 이름 + 숫자판 + [−][+]. 이 영역을 좌/우로 쓸면 이 카운터의 스킨만 바뀜. */
    private fun buildUnit(index: Int): View {
        val gd = unitSwipeDetector(index)
        val unit = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(14), dp(8), dp(14))
            @Suppress("ClickableViewAccessibility")
            setOnTouchListener { _, e -> gd.onTouchEvent(e) }
        }
        unit.addView(TextView(this).apply {
            text = species[index]
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(10))
        })

        val digitsStr = String.format("%03d", counts[index].coerceIn(0, 999))
        val cells = ArrayList<TextView>()
        unit.addView(buildDigits(styleOf[index], digitsStr, cells))
        while (digitCells.size <= index) digitCells.add(emptyList())
        digitCells[index] = cells

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, 0)
        }
        controls.addView(circleButton("−", "#37475A", "#263241") { change(index, -1) })
        controls.addView(View(this), LinearLayout.LayoutParams(dp(22), 1))
        controls.addView(circleButton("+", "#D8673F", "#A6401F") { change(index, +1) })
        unit.addView(controls)
        return unit
    }

    // ── 숫자판(스킨별) ─────────────────────────────────────
    private fun buildDigits(style: String, digits: String, out: ArrayList<TextView>): View {
        if (style == "clicker") return buildClicker(digits, out)
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        when (style) {
            "led" -> row.background = roundRect("#140707", dp(10)).also { row.setPadding(dp(14), dp(12), dp(14), dp(12)) }
            "neon" -> row.background = roundRect("#090D13", dp(12)).also { row.setPadding(dp(16), dp(14), dp(16), dp(14)) }
            "nixie" -> row.background = roundRect("#0D0906", dp(12)).also { row.setPadding(dp(8), dp(10), dp(8), dp(10)) }
        }
        for (c in digits) {
            val tv = makeCell(style, c.toString())
            out.add(tv)
            row.addView(tv, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { marginStart = dp(3); marginEnd = dp(3) })
        }
        return row
    }

    private fun makeCell(style: String, ch: String): TextView {
        val tv = TextView(this).apply {
            text = ch
            gravity = Gravity.CENTER
            setPadding(dp(6), dp(2), dp(6), dp(2))
        }
        val condensed = Typeface.create("sans-serif-condensed", Typeface.BOLD)
        val mono = Typeface.MONOSPACE
        when (style) {
            "odometer" -> {
                tv.setTextColor(Color.parseColor("#F6F4EF"))
                tv.typeface = condensed
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 34f)
                tv.width = dp(44); tv.height = dp(64)
                tv.background = GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    intArrayOf(Color.parseColor("#2A2A2A"), Color.parseColor("#050505"),
                        Color.parseColor("#1D1D1D"), Color.parseColor("#000000"))
                ).apply { cornerRadius = dp(5).toFloat() }
            }
            "led" -> {
                tv.setTextColor(Color.parseColor("#FF382E"))
                tv.typeface = mono
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
                tv.setShadowLayer(dp(10).toFloat(), 0f, 0f, Color.parseColor("#FF382E"))
            }
            "neon" -> {
                tv.setTextColor(Color.parseColor("#EAFCFF"))
                tv.typeface = mono
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
                tv.setShadowLayer(dp(16).toFloat(), 0f, 0f, Color.parseColor("#43E8FF"))
            }
            "nixie" -> {
                tv.setTextColor(Color.parseColor("#FF932A"))
                tv.typeface = mono
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 38f)
                tv.setShadowLayer(dp(14).toFloat(), 0f, 0f, Color.parseColor("#FF7A1A"))
                tv.width = dp(46); tv.height = dp(66)
                tv.background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(16).toFloat()
                    setColor(Color.parseColor("#1A120A"))
                    setStroke(dp(1), Color.parseColor("#4DFFB478"))
                }
            }
            "pill" -> {
                tv.setTextColor(Color.WHITE)
                tv.typeface = Typeface.create("sans-serif", Typeface.BOLD)
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
                tv.width = dp(48); tv.height = dp(64)
                tv.background = GradientDrawable(
                    GradientDrawable.Orientation.TL_BR,
                    intArrayOf(Color.parseColor("#C75B39"), Color.parseColor("#9C3F22"))
                ).apply { cornerRadius = dp(14).toFloat() }
            }
            else -> {
                tv.setTextColor(Color.WHITE)
                tv.typeface = mono
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 38f)
            }
        }
        return tv
    }

    /** 탈리 클리커: 크롬 원형 케이스 안의 작은 숫자창. */
    private fun buildClicker(digits: String, out: ArrayList<TextView>): View {
        val casing = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                gradientType = GradientDrawable.RADIAL_GRADIENT
                gradientRadius = dp(90).toFloat()
                colors = intArrayOf(
                    Color.parseColor("#FBFBFB"), Color.parseColor("#C9CCD1"),
                    Color.parseColor("#8A9099"), Color.parseColor("#6A7078"))
            }
        }
        val window = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundRect("#F4F3EE", dp(7))
        }
        for (c in digits) {
            val tv = TextView(this).apply {
                text = c.toString()
                gravity = Gravity.CENTER
                setTextColor(Color.parseColor("#1A1A1A"))
                typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
                width = dp(26)
            }
            out.add(tv)
            window.addView(tv)
        }
        casing.addView(window, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        val wrap = FrameLayout(this)
        wrap.addView(casing, FrameLayout.LayoutParams(dp(150), dp(150), Gravity.CENTER))
        return wrap
    }

    private fun roundRect(color: String, radius: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius.toFloat()
            setColor(Color.parseColor(color))
        }

    // ── 동작 ───────────────────────────────────────────────
    private fun updateDigits(index: Int) {
        val cells = digitCells.getOrNull(index) ?: return
        val s = String.format("%03d", counts[index].coerceIn(0, 999))
        for (j in cells.indices) cells[j].text = s[j].toString()
    }

    private fun change(index: Int, delta: Int) {
        if (delta < 0 && counts[index] <= 0) return
        lastLocalChangeMs = System.currentTimeMillis()
        counts[index] = (counts[index] + delta).coerceIn(0, 999)
        updateDigits(index)
        val action = if (delta > 0) CatchLogService.ACTION_ADD else CatchLogService.ACTION_REMOVE
        try {
            startService(Intent(this, CatchLogService::class.java).apply {
                this.action = action
                putExtra(CatchLogService.EXTRA_SPECIES_INDEX, index)
            })
        } catch (_: Exception) {}
    }

    // ── 버튼 ───────────────────────────────────────────────
    /** 원형 +/− 버튼: 위→아래 그라데이션 + 흰 글리프. */
    private fun circleButton(glyph: String, top: String, bottom: String, onClick: () -> Unit): TextView =
        TextView(this).apply {
            text = glyph
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 34f)
            typeface = Typeface.DEFAULT_BOLD
            width = dp(76); height = dp(76)
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor(top), Color.parseColor(bottom))
            ).apply {
                shape = GradientDrawable.OVAL
                setStroke(dp(1), Color.parseColor("#33FFFFFF"))
            }
            isClickable = true
            setOnClickListener { onClick() }
        }

    private fun smallButton(label: String, onClick: () -> Unit): Button =
        Button(this).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setOnClickListener { onClick() }
        }
}
