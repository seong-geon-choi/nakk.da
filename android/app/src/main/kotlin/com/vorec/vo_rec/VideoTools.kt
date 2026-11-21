package com.sgchoisg.nakkda

import android.app.Activity
import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.BatteryManager
import android.os.StatFs
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * 동영상 도구 채널(nakkda/video) — 메인 앱과 잠금 카메라 엔진 양쪽에서 쓴다.
 *
 * - 블랙박스: 조각 파일들의 '마지막 N초'만 이어 붙여 저장(trimTail).
 * - 자르기: 한 파일의 [시작, 끝] 구간 저장(trim).
 * 둘 다 재인코딩 없이 MediaExtractor→MediaMuxer로 복사한다(빠르고 화질 손실 없음).
 * 시작점은 그 직전 키프레임으로 맞춰지므로 최대 키프레임 간격(약 1초)만큼 앞당겨질 수 있다.
 */
object VideoTools {
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var app: Context

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        app = activity.applicationContext
        MethodChannel(messenger, "nakkda/video").setMethodCallHandler { call, result ->
            when (call.method) {
                "getSettings" -> {
                    val s = WatchSettings.get(activity)
                    result.success(mapOf("video_mode" to s["video_mode"], "bb_min" to s["bb_min"]))
                }
                "setSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    WatchSettings.set(activity, (call.arguments as? Map<String, Any?>) ?: emptyMap())
                    result.success(null)
                }
                // 녹화 중 화면 유지 + 창 밝기(0~1, 음수=시스템 밝기 따름). 시스템 설정은 바꾸지 않는다.
                "screen" -> {
                    val on = call.argument<Boolean>("keepOn") ?: false
                    val b = call.argument<Double>("brightness") ?: -1.0
                    activity.runOnUiThread {
                        val w = activity.window
                        if (on) w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else w.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        val lp = w.attributes
                        lp.screenBrightness = if (b < 0) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else b.toFloat()
                        w.attributes = lp
                    }
                    result.success(null)
                }
                "status" -> {
                    val bm = activity.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    result.success(mapOf(
                        "battery" to bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                        "freeBytes" to StatFs(activity.cacheDir.path).availableBytes))
                }
                "trimTail" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val keepMs = (call.argument<Number>("keepMs") ?: 0).toLong()
                    val out = call.argument<String>("out")!!
                    run(activity, result) {
                        val total = paths.sumOf { durationUs(it) }
                        concat(paths, maxOf(0L, total - keepMs * 1000), total, out)
                    }
                }
                "trim" -> {
                    val path = call.argument<String>("path")!!
                    val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
                    val endMs = (call.argument<Number>("endMs") ?: 0).toLong()
                    val out = call.argument<String>("out")!!
                    run(activity, result) { concat(listOf(path), startMs * 1000, endMs * 1000, out) }
                }
                "duration" -> {
                    val path = call.argument<String>("path")!!
                    run(activity, result) { durationUs(path) }
                }
                // 자른 파일(src)로 원본(target: 파일 경로 또는 content://)을 덮어쓴다 — 메모의 경로는 그대로.
                "replace" -> {
                    val src = call.argument<String>("src")!!
                    val target = call.argument<String>("target")!!
                    run(activity, result) {
                        if (target.startsWith("content://")) {
                            app.contentResolver.openOutputStream(Uri.parse(target), "wt")!!.use { o ->
                                File(src).inputStream().use { it.copyTo(o) }
                            }
                        } else {
                            File(src).copyTo(File(target), overwrite = true)
                            MediaScannerConnection.scanFile(app, arrayOf(target), null, null)
                        }
                        File(src).delete()
                        0L
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(activity: Activity, result: MethodChannel.Result, job: () -> Long) {
        executor.execute {
            try {
                val ms = job() / 1000
                activity.runOnUiThread { result.success(ms) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("video", e.message, null) }
            }
        }
    }

    private fun durationUs(path: String): Long {
        val ex = MediaExtractor()
        try {
            ex.open(path)
            var d = 0L
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if (f.containsKey(MediaFormat.KEY_DURATION)) d = maxOf(d, f.getLong(MediaFormat.KEY_DURATION))
            }
            return d
        } finally { ex.release() }
    }

    /**
     * [paths]를 하나의 타임라인으로 보고 [fromUs, toUs] 구간을 [out]에 쓴다. 저장 길이(µs) 반환.
     * 첫 조각은 fromUs 직전 키프레임부터, 이후 조각은 처음부터 이어 붙인다.
     */
    private fun concat(paths: List<String>, fromUs: Long, toUs: Long, out: String): Long {
        require(paths.isNotEmpty() && toUs > fromUs) { "empty range" }
        File(out).delete()
        val muxer = MediaMuxer(out, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        var written = 0L
        try {
            MediaMetadataRetriever().apply {
                try {
                    val first = paths.first()
                    if (first.startsWith("content://")) setDataSource(app, Uri.parse(first))
                    else setDataSource(first)
                    extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()
                        ?.let { muxer.setOrientationHint(it) }
                    parseLocation(extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION))
                        ?.let { muxer.setLocation(it.first, it.second) }
                } finally { release() }
            }
            var segStartUs = 0L      // 이 조각의 전체 타임라인상 시작
            var acc = 0L              // 출력 타임라인에 이미 쓴 길이
            val buf = ByteBuffer.allocate(8 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            val lastOut = HashMap<Int, Long>() // 출력 트랙별 마지막 pts(단조 증가 보장)
            var outTracks: Map<String, Int>? = null
            for (p in paths) {
                val segDur = durationUs(p)
                val segEnd = segStartUs + segDur
                if (segEnd <= fromUs || segStartUs >= toUs) { segStartUs = segEnd; continue }
                val localFrom = maxOf(0L, fromUs - segStartUs)
                val localTo = minOf(segDur, toUs - segStartUs)
                // 트랙별 추출기(영상·소리를 시간순으로 섞어 쓰기 위해 따로 읽는다).
                val exs = ArrayList<Pair<String, MediaExtractor>>()
                val formats = HashMap<String, MediaFormat>()
                val probe = MediaExtractor().apply { open(p) }
                for (i in 0 until probe.trackCount) {
                    val mime = probe.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
                    val kind = when {
                        mime.startsWith("video/") -> "v"
                        mime.startsWith("audio/") -> "a"
                        else -> continue
                    }
                    if (exs.any { it.first == kind }) continue
                    val ex = MediaExtractor().apply { open(p); selectTrack(i) }
                    exs.add(kind to ex)
                    formats[kind] = probe.getTrackFormat(i)
                }
                if (outTracks == null) {
                    val m = HashMap<String, Int>()
                    for ((kind, f) in formats) m[kind] = muxer.addTrack(f)
                    muxer.start(); started = true
                    outTracks = m
                }
                probe.release()
                // 기준점: 영상 키프레임(localFrom 이하 가장 가까운 것).
                val video = exs.firstOrNull { it.first == "v" }?.second
                video?.seekTo(localFrom, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                val base = video?.sampleTime?.takeIf { it >= 0 } ?: localFrom
                for ((kind, ex) in exs) if (kind != "v") ex.seekTo(base, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                var segMax = 0L
                while (true) {
                    // 남은 트랙 중 가장 이른 샘플부터.
                    var pick: Pair<String, MediaExtractor>? = null
                    for (e in exs) {
                        val t = e.second.sampleTime
                        if (t < 0 || t > localTo) continue
                        if (pick == null || t < pick.second.sampleTime) pick = e
                    }
                    val (kind, ex) = pick ?: break
                    val t = ex.sampleTime
                    val size = ex.readSampleData(buf, 0)
                    if (size < 0) { ex.advance(); continue }
                    val track = outTracks!![kind]
                    if (track != null && t >= base) {
                        var outPts = t - base + acc
                        val prev = lastOut[track]
                        if (prev != null && outPts <= prev) outPts = prev + 1
                        info.set(0, size, outPts, if ((ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                        muxer.writeSampleData(track, buf, info)
                        lastOut[track] = outPts
                        segMax = maxOf(segMax, t - base)
                    }
                    ex.advance()
                }
                exs.forEach { it.second.release() }
                acc += segMax + 33_333 // 다음 조각은 마지막 프레임 한 칸 뒤부터
                written = acc
                segStartUs = segEnd
            }
            require(started) { "no samples" }
            return written
        } finally {
            try { if (started) muxer.stop() } catch (_: Exception) {}
            muxer.release()
            if (!started) File(out).delete()
        }
    }

    private fun MediaExtractor.open(path: String) {
        if (path.startsWith("content://")) setDataSource(app, Uri.parse(path), null)
        else setDataSource(path)
    }

    /** ISO-6709 "+37.5665+126.9780/" → (lat, lng). */
    private fun parseLocation(s: String?): Pair<Float, Float>? {
        if (s == null) return null
        val m = Regex("([+-]\\d+(?:\\.\\d+)?)([+-]\\d+(?:\\.\\d+)?)").find(s) ?: return null
        return m.groupValues[1].toFloat() to m.groupValues[2].toFloat()
    }
}
