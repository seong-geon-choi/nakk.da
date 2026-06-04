package com.nakkda.nakkda

import android.app.Activity
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.View
import android.content.res.ColorStateList
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.SeekBar
import android.widget.Toast
import com.google.ar.core.*
import com.google.ar.core.ArCoreApk.InstallStatus
import com.google.ar.core.exceptions.*
import java.io.File
import java.io.FileOutputStream
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.sqrt

class ArMeasureActivity : Activity(), GLSurfaceView.Renderer {

    companion object {
        const val EXTRA_PHOTO_PATH       = "photoPath"
        const val EXTRA_DISTANCE_CM      = "distanceCm"
        const val EXTRA_WATERMARK_ENABLED = "watermarkEnabled"
        const val EXTRA_APPLY_WATERMARK  = "applyWatermark"
        private const val TAG = "ArMeasureActivity"
    }

    private lateinit var glSurfaceView: GLSurfaceView
    private lateinit var dotsView: ArDotsOverlayView
    private lateinit var statusText: TextView
    private lateinit var distanceText: TextView
    private lateinit var distanceCard: View
    private lateinit var shutterView: View
    private lateinit var bottomArea: FrameLayout
    private lateinit var closeBtn: TextView
    private lateinit var watermarkBtn: ImageButton
    private lateinit var includeLengthBtn: ImageButton
    private lateinit var sideButtons: LinearLayout
    private lateinit var msgText: TextView
    private val msgHandler = Handler(Looper.getMainLooper())
    private val msgHideRunnable = Runnable { hideMsg() }

    private val backgroundRenderer = BackgroundRenderer()
    private lateinit var displayRotationHelper: DisplayRotationHelper

    private var session: Session? = null
    private var installRequested = false
    private var includeLength = true
    private var applyWatermark = false

    // 워터마크 오버레이
    private var wmPosition = "bottomRight"
    private var wmDateFmt = ""
    private var wmTimeFmt = ""
    private var wmCustomText = ""
    private var wmFontSize = 32
    private var wmBold = false
    private var wmBoxOpacity = 0.67f
    private var wmAlignment = "right"
    private lateinit var wmOverlay: TextView
    private val wmHandler = Handler(Looper.getMainLooper())
    private val wmRunnable = object : Runnable {
        override fun run() { updateWmOverlay(); wmHandler.postDelayed(this, 1000) }
    }

    @Volatile private var currentFrame: Frame? = null

    private var worldPoint1: FloatArray? = null
    private var worldPoint2: FloatArray? = null
    private var measuredCm: Double? = null
    private var planeFound = false
    @Volatile private var canMeasure = false
    private var surfaceWidth = 0
    private var surfaceHeight = 0
    private lateinit var statusBg: GradientDrawable
    private lateinit var pointCloudView: ArPointCloudView
    private var pcFrameCount = 0
    @Volatile private var confThreshold = 0.005f

    // ── Drag/tap gesture ────────────────────────────────────────────
    private var dragStart: Pair<Float, Float>? = null
    private var isDragging = false
    private val dragThresholdPx by lazy { 20 * resources.displayMetrics.density }

    // ── Lifecycle ───────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        actionBar?.hide()
        // 모든 API에서 콘텐츠가 시스템 바 뒤까지 확장되도록 설정 → 인셋 콜백이 정확한 값을 받음
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )
        }
        applyWatermark = intent.getBooleanExtra(EXTRA_WATERMARK_ENABLED, false)
        wmPosition    = intent.getStringExtra("wmPosition")  ?: "bottomRight"
        wmDateFmt     = intent.getStringExtra("wmDateFmt")   ?: ""
        wmTimeFmt     = intent.getStringExtra("wmTimeFmt")   ?: ""
        wmCustomText  = intent.getStringExtra("wmCustomText") ?: ""
        wmFontSize    = intent.getIntExtra("wmFontSize", 32)
        wmBold        = intent.getBooleanExtra("wmBold", false)
        wmBoxOpacity  = intent.getFloatExtra("wmBoxOpacity", 0.67f)
        wmAlignment   = intent.getStringExtra("wmAlignment") ?: "right"
        displayRotationHelper = DisplayRotationHelper(this)
        setupLayout()
    }

    override fun onResume() {
        super.onResume()
        if (!initSession()) return
        displayRotationHelper.onResume()
        session?.resume()
        glSurfaceView.onResume()
        if (applyWatermark) wmHandler.post(wmRunnable)
    }

    override fun onPause() {
        wmHandler.removeCallbacks(wmRunnable)
        glSurfaceView.onPause()
        session?.pause()
        displayRotationHelper.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        msgHandler.removeCallbacksAndMessages(null)
        wmHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
        session?.close()
        session = null
    }

    // ── ARCore ──────────────────────────────────────────────────────

    private fun initSession(): Boolean {
        when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
            InstallStatus.INSTALL_REQUESTED -> { installRequested = true; return false }
            InstallStatus.INSTALLED -> Unit
        }
        if (session == null) {
            try {
                session = Session(this).apply {
                    configure(Config(this).apply {
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                        updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    })
                }
            } catch (e: UnavailableArcoreNotInstalledException) {
                toast("ARCore를 설치해 주세요"); finish(); return false
            } catch (e: UnavailableDeviceNotCompatibleException) {
                toast("이 기기는 AR을 지원하지 않습니다"); finish(); return false
            } catch (e: Exception) {
                toast("AR 초기화 실패: ${e.message}"); finish(); return false
            }
        }
        return true
    }

    // ── Renderer ────────────────────────────────────────────────────

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        backgroundRenderer.createOnGlThread(this)
        session?.setCameraTextureName(backgroundRenderer.getTextureId())
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        displayRotationHelper.onSurfaceChanged(width, height)
        GLES20.glViewport(0, 0, width, height)
        surfaceWidth = width
        surfaceHeight = height
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session ?: return
        displayRotationHelper.updateSessionIfNeeded(s)
        try {
            val frame = s.update()
            currentFrame = frame
            backgroundRenderer.draw(frame)
            val hasPlane = s.getAllTrackables(Plane::class.java)
                .any { it.trackingState == TrackingState.TRACKING }
            if (hasPlane != planeFound) {
                planeFound = hasPlane
                runOnUiThread { updateStatus() }
            }
            if (worldPoint1 == null && worldPoint2 == null && surfaceWidth > 0) {
                val hit = frame.hitTest(surfaceWidth / 2f, surfaceHeight / 2f).any { r ->
                    when (val t = r.trackable) {
                        is Plane -> t.trackingState == TrackingState.TRACKING
                        is com.google.ar.core.Point ->
                            t.orientationMode == com.google.ar.core.Point.OrientationMode.ESTIMATED_SURFACE_NORMAL
                        else -> false
                    }
                }
                if (hit != canMeasure) {
                    canMeasure = hit
                    runOnUiThread { updateStatus() }
                }
                if (++pcFrameCount % 3 == 0) {
                    val pointCloud = frame.acquirePointCloud()
                    val buf = pointCloud.points
                    val proj = FloatArray(16); val view = FloatArray(16); val mvp = FloatArray(16)
                    val cam = frame.camera
                    cam.getProjectionMatrix(proj, 0, 0.1f, 100f)
                    cam.getViewMatrix(view, 0)
                    android.opengl.Matrix.multiplyMM(mvp, 0, proj, 0, view, 0)
                    val vec = FloatArray(4); val clip = FloatArray(4)
                    val pts = mutableListOf<Pair<Float, Float>>()
                    var i = 0
                    while (i + 3 < buf.limit()) {
                        val x = buf[i]; val y = buf[i + 1]; val z = buf[i + 2]; val conf = buf[i + 3]
                        i += 4
                        if (conf < confThreshold) continue
                        vec[0] = x; vec[1] = y; vec[2] = z; vec[3] = 1f
                        android.opengl.Matrix.multiplyMV(clip, 0, mvp, 0, vec, 0)
                        if (clip[3] <= 0f) continue
                        val nx = clip[0] / clip[3]; val ny = clip[1] / clip[3]
                        if (nx < -1f || nx > 1f || ny < -1f || ny > 1f) continue
                        pts.add(Pair((nx + 1f) / 2f * surfaceWidth, (1f - ny) / 2f * surfaceHeight))
                    }
                    pointCloud.release()
                    runOnUiThread { if (::pointCloudView.isInitialized) pointCloudView.updatePoints(pts) }
                }
            }
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "Camera not available", e)
        }
    }

    // ── Touch ────────────────────────────────────────────────────────

    private fun onOverlayTouch(event: MotionEvent): Boolean {
        if (worldPoint2 != null) return true

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                dragStart = Pair(event.x, event.y)
                isDragging = false
                if (worldPoint1 == null) dotsView.point1 = Pair(event.x, event.y)
                dotsView.livePoint = Pair(event.x, event.y)
            }
            MotionEvent.ACTION_MOVE -> {
                val start = dragStart ?: return true
                val dx = event.x - start.first
                val dy = event.y - start.second
                if (!isDragging && sqrt(dx * dx + dy * dy) > dragThresholdPx) isDragging = true
                if (isDragging) dotsView.livePoint = Pair(event.x, event.y)
            }
            MotionEvent.ACTION_UP -> {
                val start = dragStart ?: return true
                dragStart = null
                dotsView.livePoint = null

                if (isDragging) {
                    isDragging = false
                    if (worldPoint1 == null) {
                        val p1 = hitTest(start.first, start.second)
                        val p2 = hitTest(event.x, event.y)
                        if (p1 == null || p2 == null) {
                            dotsView.point1 = null
                            showMsg("평면을 인식하지 못했습니다. 다시 시도해 주세요")
                            runOnUiThread { updateStatus() }
                            return true
                        }
                        worldPoint1 = p1; worldPoint2 = p2
                        dotsView.point1 = start
                        dotsView.point2 = Pair(event.x, event.y)
                    } else {
                        val p2 = hitTest(event.x, event.y) ?: run {
                            showMsg("평면을 인식하지 못했습니다. 다시 시도해 주세요"); return true
                        }
                        worldPoint2 = p2
                        dotsView.point2 = Pair(event.x, event.y)
                    }
                    measuredCm = distance3d(worldPoint1!!, worldPoint2!!) * 100.0
                    runOnUiThread { showDistance(measuredCm!!) }
                } else {
                    val hit = hitTest(event.x, event.y) ?: run {
                        if (worldPoint1 == null) dotsView.point1 = null
                        showMsg("평면을 인식하지 못했습니다. 다시 시도해 주세요")
                        runOnUiThread { updateStatus() }
                        return true
                    }
                    if (worldPoint1 == null) {
                        worldPoint1 = hit
                        dotsView.point1 = Pair(event.x, event.y)
                        runOnUiThread { updateStatus() }
                    } else {
                        worldPoint2 = hit
                        dotsView.point2 = Pair(event.x, event.y)
                        measuredCm = distance3d(worldPoint1!!, worldPoint2!!) * 100.0
                        runOnUiThread { showDistance(measuredCm!!) }
                    }
                }
            }
        }
        return true
    }

    private fun hitTest(x: Float, y: Float): FloatArray? {
        val frame = currentFrame ?: return null

        fun tryAt(tx: Float, ty: Float, relaxed: Boolean): FloatArray? =
            frame.hitTest(tx, ty).firstOrNull { r ->
                when (val t = r.trackable) {
                    is Plane -> t.trackingState == TrackingState.TRACKING
                    is com.google.ar.core.Point -> relaxed ||
                        t.orientationMode == com.google.ar.core.Point.OrientationMode.ESTIMATED_SURFACE_NORMAL
                    else -> false
                }
            }?.hitPose?.translation?.clone()

        // 1차: 정확한 위치 (엄격한 필터)
        tryAt(x, y, false)?.let { return it }

        // 2차: 주변 8방향 (엄격한 필터)
        val s = 30f
        for ((dx, dy) in listOf(s to 0f, -s to 0f, 0f to s, 0f to -s,
                                 s to s, -s to s, s to -s, -s to -s)) {
            tryAt(x + dx, y + dy, false)?.let { return it }
        }

        // 3차: 주변 8방향 (완화된 필터 — Point 방향 조건 제거)
        for ((dx, dy) in listOf(0f to 0f, s to 0f, -s to 0f, 0f to s, 0f to -s,
                                 s to s, -s to s, s to -s, -s to -s)) {
            tryAt(x + dx, y + dy, true)?.let { return it }
        }

        return null
    }

    // ── UI ───────────────────────────────────────────────────────────

    private fun updateStatus() {
        val (txt, bgColor) = when {
            worldPoint2 != null -> "✓ 측정 완료  아래 촬영 버튼을 누르세요" to 0xCC000000.toInt()
            worldPoint1 != null -> "② 끝점을 터치하세요"                    to 0xCC1565C0.toInt()
            canMeasure          -> "● 측정 가능  시작점을 터치하거나 드래그" to 0xCC2E7D32.toInt()
            else                -> "⏳ 평면 인식 중..."                      to 0xCCE65100.toInt()
        }
        statusText.text = txt
        statusBg.setColor(bgColor)
        val measured = measuredCm != null
        shutterView.alpha = if (measured) 1f else 0.35f
        shutterView.isClickable = measured
        if (::pointCloudView.isInitialized) {
            val showCloud = worldPoint1 == null && worldPoint2 == null
            pointCloudView.visibility = if (showCloud) View.VISIBLE else View.GONE
            if (!showCloud) pointCloudView.clear()
        }
    }

    private fun showDistance(cm: Double) {
        distanceCard.visibility = View.VISIBLE
        distanceText.text = "%.1f cm".format(cm)
        updateStatus()
    }

    private fun resetMeasurement() {
        worldPoint1 = null; worldPoint2 = null; measuredCm = null
        dragStart = null; isDragging = false; canMeasure = false
        dotsView.reset()
        distanceCard.visibility = View.GONE
        updateStatus()
    }

    private fun updateWatermarkBtn() {
        watermarkBtn.imageTintList = ColorStateList.valueOf(
            if (applyWatermark) 0xFF40C4FF.toInt() else 0x80FFFFFF.toInt()
        )
    }

    private fun updateIncludeLengthBtn() {
        includeLengthBtn.imageTintList = ColorStateList.valueOf(
            if (includeLength) 0xFF40C4FF.toInt() else 0x80FFFFFF.toInt()
        )
    }

    private fun showMsg(text: String) {
        msgHandler.removeCallbacks(msgHideRunnable)
        msgText.text = text
        msgText.visibility = View.VISIBLE
        msgText.animate().cancel()
        msgText.alpha = 0f
        msgText.animate()
            .alpha(1f)
            .setDuration(200)
            .withEndAction { msgHandler.postDelayed(msgHideRunnable, 1500) }
            .start()
    }

    private fun hideMsg() {
        msgText.animate()
            .alpha(0f)
            .setDuration(300)
            .withEndAction { msgText.visibility = View.GONE }
            .start()
    }

    private fun updateWmOverlay() {
        if (!::wmOverlay.isInitialized) return
        val cal = java.util.Calendar.getInstance()
        val lines = mutableListOf<String>()
        if (wmDateFmt.isNotEmpty()) {
            val y  = cal.get(java.util.Calendar.YEAR)
            val yy = (y % 100).toString().padStart(2, '0')
            val mm = (cal.get(java.util.Calendar.MONTH) + 1).toString().padStart(2, '0')
            val dd = cal.get(java.util.Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
            lines.add(when (wmDateFmt) {
                "yy/MM/dd" -> "$yy/$mm/$dd"
                "MM/dd"    -> "$mm/$dd"
                else       -> "$y-$mm-$dd"
            })
        }
        if (wmTimeFmt.isNotEmpty()) {
            val hh  = cal.get(java.util.Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
            val min = cal.get(java.util.Calendar.MINUTE).toString().padStart(2, '0')
            val sec = cal.get(java.util.Calendar.SECOND).toString().padStart(2, '0')
            lines.add(if (wmTimeFmt == "HH:mm:ss") "$hh:$min:$sec" else "$hh:$min")
        }
        if (wmCustomText.isNotEmpty()) lines.add(wmCustomText)
        wmOverlay.text = lines.joinToString("\n")
    }

    // ── Capture ──────────────────────────────────────────────────────

    private fun captureAndReturn() {
        shutterView.isClickable = false
        shutterView.alpha = 0.5f
        val bmp = Bitmap.createBitmap(glSurfaceView.width, glSurfaceView.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(glSurfaceView, bmp, { result ->
            if (result == PixelCopy.SUCCESS) {
                val final = if (includeLength) applyMeasurementToPhoto(bmp) else bmp
                val f = File(cacheDir, "ar_${System.currentTimeMillis()}.jpg")
                FileOutputStream(f).use { final.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                setResult(RESULT_OK, Intent().apply {
                    putExtra(EXTRA_PHOTO_PATH, f.absolutePath)
                    measuredCm?.let { putExtra(EXTRA_DISTANCE_CM, it) }
                    putExtra(EXTRA_APPLY_WATERMARK, applyWatermark)
                })
                finish()
            } else {
                runOnUiThread {
                    toast("캡처 실패, 다시 시도해 주세요")
                    shutterView.isClickable = true; shutterView.alpha = 1f
                }
            }
        }, Handler(Looper.getMainLooper()))
    }

    private fun applyMeasurementToPhoto(src: Bitmap): Bitmap {
        val out = src.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(out)
        val p1 = dotsView.point1 ?: return out
        val p2 = dotsView.point2 ?: return out
        val cm = measuredCm ?: return out

        // 비트맵 크기 기준으로 모든 수치 스케일 — 해상도/화면 크기 무관
        val sw = src.width.toFloat()
        val stroke  = sw * 0.005f
        val dotR    = sw * 0.025f
        val textSz  = sw * 0.065f
        val labelOY = sw * 0.055f
        val ph      = sw * 0.026f
        val pv      = sw * 0.016f
        val corner  = sw * 0.020f
        val dashOn  = sw * 0.022f
        val dashOff = sw * 0.011f

        canvas.drawLine(p1.first, p1.second, p2.first, p2.second,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE; strokeWidth = stroke; style = Paint.Style.STROKE
                pathEffect = DashPathEffect(floatArrayOf(dashOn, dashOff), 0f)
            })

        for (pt in listOf(p1, p2)) {
            canvas.drawCircle(pt.first, pt.second, dotR,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#FF4081") })
            canvas.drawCircle(pt.first, pt.second, dotR,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = stroke
                })
        }

        val mx = (p1.first + p2.first) / 2f
        val my = (p1.second + p2.second) / 2f - labelOY
        val label = "%.1f cm".format(cm)
        val tp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = textSz; textAlign = Paint.Align.CENTER
            typeface = Typeface.DEFAULT_BOLD
        }
        val tb = Rect(); tp.getTextBounds(label, 0, label.length, tb)
        canvas.drawRoundRect(
            RectF(mx - tb.width()/2f - ph, my - tb.height() - pv, mx + tb.width()/2f + ph, my + pv),
            corner, corner, Paint().apply { color = 0xCC000000.toInt() })
        canvas.drawText(label, mx, my, tp)
        return out
    }

    // ── Layout ───────────────────────────────────────────────────────

    private fun setupLayout() {
        glSurfaceView = GLSurfaceView(this).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            setRenderer(this@ArMeasureActivity)
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        }

        dotsView = ArDotsOverlayView(this).apply {
            setOnTouchListener { _, e -> onOverlayTouch(e) }
        }

        pointCloudView = ArPointCloudView(this).apply {
            isClickable = false
            isFocusable = false
        }

        // ── Status text ───────────────────────────────────
        statusBg = GradientDrawable().apply {
            setColor(0xCCE65100.toInt()); cornerRadius = dpToPx(24).toFloat()
        }
        statusText = TextView(this).apply {
            text = "카메라를 측정 대상에 가까이 향해 주세요"
            setTextColor(Color.WHITE); textSize = 16f; typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dpToPx(20), dpToPx(12), dpToPx(20), dpToPx(12))
            background = statusBg
        }
        val statusParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dpToPx(60); leftMargin = dpToPx(48); rightMargin = dpToPx(48)
        }

        // ── Distance card (draggable) ─────────────────────
        distanceText = TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 22f; typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER; setPadding(dpToPx(20), dpToPx(10), dpToPx(20), dpToPx(10))
        }
        distanceCard = FrameLayout(this).apply {
            visibility = View.GONE
            background = GradientDrawable().apply {
                setColor(0xDD000000.toInt()); cornerRadius = dpToPx(11).toFloat()
            }
            (this as FrameLayout).addView(distanceText)
            var dX = 0f; var dY = 0f
            setOnTouchListener { v, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> { dX = v.translationX - event.rawX; dY = v.translationY - event.rawY; true }
                    MotionEvent.ACTION_MOVE -> { v.translationX = event.rawX + dX; v.translationY = event.rawY + dY; true }
                    else -> false
                }
            }
        }
        val distParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER }

        // ── Close button ──────────────────────────────────
        closeBtn = TextView(this).apply {
            text = "✕"; setTextColor(Color.WHITE); textSize = 20f; gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(0x99000000.toInt()); cornerRadius = dpToPx(24).toFloat()
            }
            setOnClickListener { finish() }
        }
        val closeParams = FrameLayout.LayoutParams(dpToPx(48), dpToPx(48)).apply {
            gravity = Gravity.TOP or Gravity.START
            topMargin = dpToPx(52); leftMargin = dpToPx(12)
        }

        // ── Bottom area ───────────────────────────────────
        val resetBtn = TextView(this).apply {
            text = "↺  다시 측정"; setTextColor(Color.WHITE); textSize = 14f; gravity = Gravity.CENTER
            setPadding(dpToPx(14), dpToPx(10), dpToPx(14), dpToPx(10))
            background = GradientDrawable().apply {
                setColor(0x88000000.toInt()); cornerRadius = dpToPx(18).toFloat()
            }
            setOnClickListener { resetMeasurement() }
        }
        val resetParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL }

        shutterView = View(this).apply {
            background = buildShutterDrawable(); isClickable = false; alpha = 0.35f
            setOnClickListener { captureAndReturn() }
        }
        val shutterSize = dpToPx(72)
        val shutterParams = FrameLayout.LayoutParams(shutterSize, shutterSize).apply {
            gravity = Gravity.CENTER
        }

        // 워터마크 오버레이 뷰
        val isTop  = wmPosition == "topLeft"  || wmPosition == "topRight"
        val isLeft = wmPosition == "topLeft"  || wmPosition == "bottomLeft"
        // Flutter와 동일한 공식으로 화면 크기 기준 폰트 크기 계산
        val dm = resources.displayMetrics
        val screenWDp = dm.widthPixels / dm.density
        val screenHDp = dm.heightPixels / dm.density
        val photoAspect = screenHDp / screenWDp  // 세로 화면: height > width
        val fontDp = minOf(
            wmFontSize * screenWDp / 480f,
            wmFontSize * screenHDp / (480f * photoAspect)
        ).coerceIn(8f, screenWDp * 0.09f)
        wmOverlay = TextView(this).apply {
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, fontDp)
            setTextColor(Color.WHITE)
            typeface = if (wmBold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            gravity = when (wmAlignment) {
                "left"   -> Gravity.START
                "center" -> Gravity.CENTER_HORIZONTAL
                else     -> Gravity.END
            }
            setPadding(dpToPx(10), dpToPx(5), dpToPx(10), dpToPx(5))
            background = GradientDrawable().apply {
                val a = (wmBoxOpacity * 255).toInt().coerceIn(0, 255)
                setColor(Color.argb(a, 0, 0, 0))
                cornerRadius = dpToPx(4).toFloat()
            }
            visibility = if (applyWatermark) View.VISIBLE else View.GONE
        }
        val wmGravity = (if (isTop) Gravity.TOP else Gravity.BOTTOM) or
                        (if (isLeft) Gravity.START else Gravity.END)
        val wmParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = wmGravity; setMargins(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16)) }
        updateWmOverlay()

        // Icon toggle buttons — right-center of screen (outside bottom area)
        watermarkBtn = makeIconToggleBtn(R.drawable.ic_wm_toggle) {
            applyWatermark = !applyWatermark
            updateWatermarkBtn()
            wmOverlay.visibility = if (applyWatermark) View.VISIBLE else View.GONE
            if (applyWatermark) { updateWmOverlay(); wmHandler.post(wmRunnable) }
            else wmHandler.removeCallbacks(wmRunnable)
            showMsg(if (applyWatermark) "워터마크 표시 ON" else "워터마크 표시 OFF")
        }
        includeLengthBtn = makeIconToggleBtn(R.drawable.ic_ruler_toggle) {
            includeLength = !includeLength
            updateIncludeLengthBtn()
            showMsg(if (includeLength) "측정 결과 포함 저장 ON" else "측정 결과 포함 저장 OFF")
        }
        updateWatermarkBtn()
        updateIncludeLengthBtn()

        val iconSize = dpToPx(48)
        sideButtons = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            clipChildren = false
            clipToPadding = false
        }
        sideButtons.addView(watermarkBtn,
            LinearLayout.LayoutParams(iconSize, iconSize).apply { bottomMargin = dpToPx(12) })
        sideButtons.addView(includeLengthBtn,
            LinearLayout.LayoutParams(iconSize, iconSize).apply { bottomMargin = dpToPx(12) })
        sideButtons.addView(TextView(this).apply {
            text = "감도"; setTextColor(Color.WHITE); textSize = 10f; gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(iconSize, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dpToPx(4)
        })
        // 세로 SeekBar: layout은 130×32, rotation=270 → 시각적으로 32×130
        val sliderWrapper = FrameLayout(this).apply { clipChildren = false; clipToPadding = false }
        sliderWrapper.addView(SeekBar(this).apply {
            max = 100
            progress = 90  // 기본 감도 높음 (threshold ≈ 0.005)
            rotation = 270f
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(sb: SeekBar, p: Int, user: Boolean) {
                    // 비선형: 높은 감도 영역에서 세밀한 조정
                    val r = (100 - p) / 100f
                    confThreshold = r * r * 0.5f  // 0→0.5(적음), 100→0.0(많음)
                }
                override fun onStartTrackingTouch(sb: SeekBar) {}
                override fun onStopTrackingTouch(sb: SeekBar) {}
            })
        }, FrameLayout.LayoutParams(dpToPx(130), dpToPx(32)).apply { gravity = Gravity.CENTER })
        sideButtons.addView(sliderWrapper, LinearLayout.LayoutParams(iconSize, dpToPx(130)))

        val sideParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER_VERTICAL or Gravity.END; rightMargin = dpToPx(8) }

        // 옵션 변경 알림 메시지 오버레이
        msgText = TextView(this).apply {
            textSize = 14f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            setPadding(dpToPx(20), dpToPx(10), dpToPx(20), dpToPx(10))
            background = GradientDrawable().apply {
                setColor(0xDD000000.toInt()); cornerRadius = dpToPx(24).toFloat()
            }
            visibility = View.GONE
        }
        val msgParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = dpToPx(120)
        }

        bottomArea = FrameLayout(this).apply {
            setPadding(dpToPx(24), dpToPx(20), dpToPx(24), dpToPx(20))
            addView(resetBtn, resetParams)
            addView(shutterView, shutterParams)
        }
        val bottomParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.BOTTOM }

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(glSurfaceView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            addView(pointCloudView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            addView(dotsView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            addView(wmOverlay, wmParams)
            addView(closeBtn, closeParams)
            addView(statusText, statusParams)
            addView(distanceCard, distParams)
            addView(bottomArea, bottomParams)
            addView(sideButtons, sideParams)
            addView(msgText, msgParams)
        }
        setContentView(root)

        // System bar insets — handle all 4 sides for portrait & landscape
        root.setOnApplyWindowInsetsListener { _, insets ->
            val l: Int; val t: Int; val r: Int; val b: Int
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val sys = insets.getInsets(android.view.WindowInsets.Type.systemBars())
                l = sys.left; t = sys.top; r = sys.right; b = sys.bottom
            } else {
                @Suppress("DEPRECATION")
                l = insets.systemWindowInsetLeft
                @Suppress("DEPRECATION")
                t = insets.systemWindowInsetTop
                @Suppress("DEPRECATION")
                r = insets.systemWindowInsetRight
                @Suppress("DEPRECATION")
                b = insets.systemWindowInsetBottom
            }
            (closeBtn.layoutParams as FrameLayout.LayoutParams).apply {
                topMargin = t + dpToPx(8); leftMargin = l + dpToPx(12)
            }
            closeBtn.requestLayout()
            (statusText.layoutParams as FrameLayout.LayoutParams).apply {
                topMargin = t + dpToPx(16); leftMargin = l + dpToPx(48); rightMargin = r + dpToPx(48)
            }
            statusText.requestLayout()
            // bottomArea padding accounts for nav bar on all sides
            bottomArea.setPadding(dpToPx(24) + l, dpToPx(20), dpToPx(24) + r, dpToPx(20) + b)
            (sideButtons.layoutParams as FrameLayout.LayoutParams).apply {
                rightMargin = r + dpToPx(8)
                bottomMargin = b  // 네비게이션 바 위로 수직 중앙 보정
            }
            sideButtons.requestLayout()
            (wmOverlay.layoutParams as FrameLayout.LayoutParams).apply {
                val m = dpToPx(16)
                leftMargin   = if (isLeft) l + m else m
                rightMargin  = if (!isLeft) r + m else m
                topMargin    = if (isTop) t + m else m
                bottomMargin = if (!isTop) b + m else m
            }
            wmOverlay.requestLayout()
            (msgText.layoutParams as FrameLayout.LayoutParams).apply {
                bottomMargin = b + dpToPx(120)
            }
            msgText.requestLayout()
            insets
        }
        root.requestApplyInsets()
    }

    private fun makeIconToggleBtn(iconRes: Int, onClick: () -> Unit): ImageButton =
        ImageButton(this).apply {
            setImageResource(iconRes)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dpToPx(10), dpToPx(10), dpToPx(10), dpToPx(10))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x99000000.toInt())
            }
            setOnClickListener { onClick() }
        }

    private fun buildShutterDrawable(): android.graphics.drawable.Drawable {
        val ring = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setStroke(dpToPx(4), Color.WHITE); setColor(Color.TRANSPARENT)
        }
        val inner = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(Color.WHITE)
        }
        return object : android.graphics.drawable.Drawable() {
            override fun draw(c: Canvas) {
                val b = bounds
                ring.bounds = b; ring.draw(c)
                val inset = (b.width() * 0.12f).toInt()
                inner.setBounds(b.left + inset, b.top + inset, b.right - inset, b.bottom - inset)
                inner.draw(c)
            }
            override fun setAlpha(a: Int) {}
            override fun setColorFilter(cf: ColorFilter?) {}
            @Suppress("OVERRIDE_DEPRECATION")
            override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    // ── Utils ─────────────────────────────────────────────────────────

    private fun distance3d(a: FloatArray, b: FloatArray): Float {
        val dx = b[0]-a[0]; val dy = b[1]-a[1]; val dz = b[2]-a[2]
        return sqrt(dx*dx + dy*dy + dz*dz)
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private fun dpToPx(dp: Int) = (dp * resources.displayMetrics.density).toInt()
}
