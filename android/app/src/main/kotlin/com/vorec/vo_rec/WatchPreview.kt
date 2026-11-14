package com.sgchoisg.nakkda

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

/**
 * 워치 카메라 미리보기: 카메라 YUV 프레임을 작게 줄여(정사각 240px, JPEG 보통 화질)
 * 워치로 보낸다. Dart가 초당 약 4장으로 제한해 호출한다. 백그라운드 스레드에서 호출할 것.
 */
object WatchPreview {
    const val PATH_FRAME = "/nakkda/camera/frame"
    private const val OUT_SIZE = 240
    private const val QUALITY = 60
    private var nodes: List<String> = emptyList()
    private var nodesAt = 0L

    /**
     * YUV_420_888 평면 → 축소 NV21 → JPEG → 회전·(셀카)좌우반전·정사각 크롭 → 워치 전송.
     * rotation: 센서 방향(도). front: 전면이면 거울처럼 좌우 반전(셀카 화면과 동일하게).
     */
    fun send(
        context: Context,
        width: Int, height: Int,
        y: ByteArray, u: ByteArray, v: ByteArray,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        rotation: Int, front: Boolean,
    ) {
        // 1) 정수 배율로 샘플링해 약 320px 폭의 NV21을 만든다(전체 해상도 인코딩 회피).
        val f = maxOf(1, width / 320)
        val sw = (width / f) and 1.inv()
        val sh = (height / f) and 1.inv()
        if (sw <= 0 || sh <= 0) return
        val nv21 = ByteArray(sw * sh * 3 / 2)
        var o = 0
        for (r in 0 until sh) {
            val row = r * f * yRowStride
            for (c in 0 until sw) nv21[o++] = y[row + c * f]
        }
        for (r in 0 until sh / 2) {
            val row = r * f * uvRowStride
            for (c in 0 until sw / 2) {
                val i = row + c * f * uvPixelStride
                nv21[o++] = v.getOrElse(i) { 128.toByte() }
                nv21[o++] = u.getOrElse(i) { 128.toByte() }
            }
        }
        val small = ByteArrayOutputStream().also {
            YuvImage(nv21, ImageFormat.NV21, sw, sh, null).compressToJpeg(Rect(0, 0, sw, sh), 80, it)
        }.toByteArray()
        val bmp = BitmapFactory.decodeByteArray(small, 0, small.size) ?: return

        // 2) 회전 + 셀카 좌우 반전 + 가운데 정사각 크롭 + 축소.
        val m = Matrix().apply {
            postRotate(rotation.toFloat())
            if (front) postScale(-1f, 1f)
        }
        val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        val side = minOf(rotated.width, rotated.height)
        val square = Bitmap.createBitmap(
            rotated, (rotated.width - side) / 2, (rotated.height - side) / 2, side, side)
        val out = Bitmap.createScaledBitmap(square, OUT_SIZE, OUT_SIZE, true)
        val jpeg = ByteArrayOutputStream().also {
            out.compress(Bitmap.CompressFormat.JPEG, QUALITY, it)
        }.toByteArray()

        // 3) 연결된 워치로 전송(노드 목록은 10초 캐시).
        val now = System.currentTimeMillis()
        if (nodes.isEmpty() || now - nodesAt > 10_000) {
            nodes = try {
                Tasks.await(Wearable.getNodeClient(context).connectedNodes, 2, TimeUnit.SECONDS)
                    .map { it.id }
            } catch (_: Exception) { emptyList() }
            nodesAt = now
        }
        val mc = Wearable.getMessageClient(context)
        for (id in nodes) mc.sendMessage(id, PATH_FRAME, jpeg)
    }
}
