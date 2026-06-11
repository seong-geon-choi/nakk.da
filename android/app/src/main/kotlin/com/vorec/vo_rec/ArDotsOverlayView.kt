package com.sgchoisg.nakkda

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.sqrt

class ArDotsOverlayView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    var point1: Pair<Float, Float>? = null
        set(value) { field = value; invalidate() }

    var point2: Pair<Float, Float>? = null
        set(value) { field = value; invalidate() }

    var livePoint: Pair<Float, Float>? = null
        set(value) { field = value; invalidate() }

    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF4081")
        style = Paint.Style.FILL
    }
    private val ghostPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#99FF4081")
        style = Paint.Style.FILL
    }
    private val dotBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 5f
    }
    private val ghostBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x99FFFFFF.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 5f
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f
        pathEffect = DashPathEffect(floatArrayOf(20f, 10f), 0f)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val p1 = point1 ?: return
        val p2 = point2
        val live = livePoint

        if (p2 != null) {
            canvas.drawLine(p1.first, p1.second, p2.first, p2.second, linePaint)
            drawDot(canvas, p1.first, p1.second)
            drawDot(canvas, p2.first, p2.second)
        } else {
            if (live != null) {
                canvas.drawLine(p1.first, p1.second, live.first, live.second, linePaint)
            }
            drawDot(canvas, p1.first, p1.second)
            if (live != null) drawGhostDot(canvas, live.first, live.second)
        }
    }

    private fun drawDot(canvas: Canvas, x: Float, y: Float) {
        val r = 22f
        canvas.drawCircle(x, y, r, dotPaint)
        canvas.drawCircle(x, y, r, dotBorderPaint)
    }

    private fun drawGhostDot(canvas: Canvas, x: Float, y: Float) {
        val r = 22f
        canvas.drawCircle(x, y, r, ghostPaint)
        canvas.drawCircle(x, y, r, ghostBorderPaint)
    }

    fun distancePx(): Float? {
        val p1 = point1 ?: return null
        val p2 = point2 ?: return null
        val dx = p2.first - p1.first
        val dy = p2.second - p1.second
        return sqrt(dx * dx + dy * dy)
    }

    fun reset() {
        point1 = null
        point2 = null
        livePoint = null
    }
}
