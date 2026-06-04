package com.nakkda.nakkda

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.view.View
import kotlin.math.sin

class ArPointCloudView(context: Context) : View(context) {

    private var points: List<Pair<Float, Float>> = emptyList()
    private val startTime = System.currentTimeMillis()

    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val dotPaint  = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val rimPaint  = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f
        color = Color.WHITE
    }

    private val handler = Handler(Looper.getMainLooper())
    private val animRunnable = object : Runnable {
        override fun run() {
            invalidate()
            if (points.isNotEmpty()) handler.postDelayed(this, 50)
        }
    }

    fun updatePoints(pts: List<Pair<Float, Float>>) {
        points = pts
        handler.removeCallbacks(animRunnable)
        if (pts.isNotEmpty()) handler.post(animRunnable) else invalidate()
    }

    fun clear() {
        handler.removeCallbacks(animRunnable)
        points = emptyList()
        invalidate()
    }

    override fun onDetachedFromWindow() {
        handler.removeCallbacks(animRunnable)
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        if (points.isEmpty()) return
        val t = (System.currentTimeMillis() - startTime) / 700f
        for ((x, y) in points) {
            val phase = (x * 0.03f + y * 0.02f) % (2f * Math.PI.toFloat())
            val pulse = (sin(t + phase) + 1f) / 2f          // 0.0 ~ 1.0

            // 바깥 글로우 (반투명 큰 원)
            glowPaint.color = Color.argb((pulse * 80 + 20).toInt(), 255, 220, 50)
            canvas.drawCircle(x, y, 14f, glowPaint)

            // 중심 점
            dotPaint.color = Color.argb((pulse * 120 + 135).toInt(), 255, 230, 60)
            canvas.drawCircle(x, y, 7f, dotPaint)

            // 흰 테두리
            rimPaint.alpha = (pulse * 100 + 155).toInt()
            canvas.drawCircle(x, y, 7f, rimPaint)
        }
    }
}
