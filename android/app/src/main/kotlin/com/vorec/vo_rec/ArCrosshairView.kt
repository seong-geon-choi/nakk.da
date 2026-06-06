package com.nakkda.nakkda

import android.content.Context
import android.graphics.*
import android.view.View

class ArCrosshairView(context: Context) : View(context) {

    var isStable: Boolean = false
        set(value) { if (field != value) { field = value; invalidate() } }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = 3f }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val color = if (isStable) Color.parseColor("#66BB6A") else Color.WHITE
        paint.color = color

        val outerR = 36f
        val gap = 10f
        val armLen = 20f

        paint.style = Paint.Style.STROKE
        canvas.drawCircle(cx, cy, outerR, paint)
        canvas.drawLine(cx - outerR - armLen, cy, cx - gap, cy, paint)
        canvas.drawLine(cx + gap, cy, cx + outerR + armLen, cy, paint)
        canvas.drawLine(cx, cy - outerR - armLen, cx, cy - gap, paint)
        canvas.drawLine(cx, cy + gap, cx, cy + outerR + armLen, paint)

        paint.style = Paint.Style.FILL
        canvas.drawCircle(cx, cy, 4f, paint)
    }
}
