package com.sgchoisg.nakkda

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.media.MediaScannerConnection
import android.os.Environment
import android.provider.MediaStore
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.cos

/**
 * 낚시 종료 시 그날 메모 끝에 '조과 요약'(어종별 수 + 시간대별 조과·조위 그래프 이미지)을 넣는다.
 *
 * 호출 시점: 이동 경로 기록 종료(사용자 종료·자정 자동 종료), 워치 메뉴 '낚시 종료'.
 * - 조과가 0이면 아무것도 저장하지 않는다.
 * - 여러 번 종료해도 요약은 하나만 남는다(기존 요약 항목과 이미지를 지우고 새로 추가).
 * - 요약 항목은 본문 첫 줄 "🏁 조과 요약"으로 식별한다(메모 앱이 파일을 다시 써도 유지되는 본문 텍스트).
 * - 워치 '낚시 종료'는 카운터 화면 캡처도 함께 보낸다 → "🏁 워치 카운터" 항목(역시 1개만 유지).
 * 파일 I/O를 하므로 백그라운드 스레드에서 호출할 것.
 */
object CatchSummary {
    private const val MARK = "🏁 조과 요약"
    private const val MARK_COUNTER = "🏁 워치 카운터"
    // 워치 카운터 팔레트(워치 PALETTE·폰 워치설정 화면과 동일) — 좌/우 어종 색을 워치와 맞춘다.
    private val WATCH_PALETTE = intArrayOf(
        0xFF1565C0.toInt(), 0xFF1E88E5.toInt(), 0xFF00838F.toInt(), 0xFF00897B.toInt(),
        0xFF2E7D32.toInt(), 0xFF7CB342.toInt(), 0xFFF9A825.toInt(), 0xFFEF6C00.toInt(),
        0xFFD84315.toInt(), 0xFFC62828.toInt(), 0xFFAD1457.toInt(), 0xFF6A1B9A.toInt(),
        0xFF4527A0.toInt(), 0xFF455A64.toInt(), 0xFF37474F.toInt(), 0xFF263238.toInt(),
    )
    private val SERIES_COLORS = intArrayOf(
        0xFF1E88E5.toInt(), 0xFF43A047.toInt(), 0xFFEF6C00.toInt(),
        0xFF8E24AA.toInt(), 0xFFC62828.toInt(), 0xFF00897B.toInt(),
    )

    fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /**
     * 그날(date=yyyy-MM-dd) 조과 요약을 메모에 기록. 기록했으면 true(조과 0·파일 없음이면 false).
     * counterImage: 워치 카운터 화면 캡처(있으면 요약 앞에 별도 항목으로 첨부).
     */
    @Synchronized
    fun write(context: Context, date: String, counterImage: ByteArray? = null): Boolean {
        val txt = CatchLogService.readMd(context, date) ?: return false
        val hourly = CatchLogService.loadHourlyBySpecies(context, date)
        // 카운터 어종 순서를 먼저, 그 외(도중에 바뀐 어종 등)는 뒤에.
        val species = CatchLogService.loadSpecies(context)
        val names = species.filter { hourly.containsKey(it) } +
            hourly.keys.filter { it !in species }.sorted()
        val counts = names.map { n -> hourly[n]?.sum() ?: 0 }
        val total = counts.sum()
        if (total <= 0) return false

        val (firstAt, lastAt) = catchTimeRange(txt) ?: return false
        val tide = CatchLogService.loadTidePoints(context, date)
        val colors = seriesColors(context, names.size)
        val chart = renderChart(date, names, names.map { hourly[it] ?: IntArray(24) }, counts,
            tide, firstAt, lastAt, colors)
        val path = saveToGallery(context, chart, "NAKKDA_SUMMARY_${date.replace("-", "")}") ?: return false

        // 새 카운터 캡처가 있으면 저장(실패해도 요약은 진행).
        val counterPath = counterImage?.takeIf { it.isNotEmpty() }?.let { bytes ->
            val isPng = bytes.size > 4 && bytes[0] == 0x89.toByte() && bytes[1] == 'P'.code.toByte()
            val hms = SimpleDateFormat("HHmmss", Locale.US).format(Date())
            saveImageToGallery(context, bytes, if (isPng) "image/png" else "image/jpeg",
                "NAKKDA_COUNTER_${date.replace("-", "")}_$hms${if (isPng) ".png" else ".jpg"}")
        }

        // 기존 요약 항목(카운터 캡처는 새 캡처가 있을 때만) 제거(이미지도 삭제) 후 끝에 새로 추가.
        val segs = txt.split("\n---\n").toMutableList()
        val iter = segs.listIterator()
        iter.next() // 파일 헤더 영역은 유지
        while (iter.hasNext()) {
            val seg = iter.next()
            val isOld = seg.lineSequence().any { l ->
                val t = l.trim()
                t.startsWith(MARK) || (counterPath != null && t.startsWith(MARK_COUNTER))
            }
            if (isOld) {
                Regex("""^!\[\]\((.+)\)$""", RegexOption.MULTILINE).find(seg)
                    ?.let { m -> deleteImage(context, m.groupValues[1]) }
                iter.remove()
            }
        }
        // 오늘이면 지금, 지난 날짜(자정 종료)면 마지막 조과 시각을 항목 시각으로.
        val ts = if (date == today())
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        else "$date $lastAt:59"
        val countLine = names.indices.joinToString(" · ") { "${names[it]} ${counts[it]}" } +
            " (총 ${total}마리)"
        var entry = "\n---\n\n### $ts\n![]($path)\n$MARK $firstAt~$lastAt\n$countLine\n"
        if (counterPath != null) {
            // 같은 시각이면 메모 정렬 순서가 흔들릴 수 있어 카운터 항목을 1초 앞에 둔다.
            val cts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                .format(Date(System.currentTimeMillis() - 1000))
            entry = "\n---\n\n### $cts\n![]($counterPath)\n$MARK_COUNTER\n" + entry
        }
        CatchLogService.writeMd(context, segs.joinToString("\n---\n") + entry, date)

        // 메모·지도 등 열린 화면이 파일을 다시 읽도록.
        try {
            context.sendBroadcast(
                Intent(CatchLogService.ACTION_COUNTS_CHANGED).setPackage(context.packageName))
        } catch (_: Exception) {}
        return true
    }

    /** 어종 i의 색 — 좌/우(0,1)는 워치 카운터 색, 그 외는 기본 색. */
    private fun seriesColors(context: Context, n: Int): IntArray {
        val ws = WatchSettings.get(context)
        val idx = intArrayOf((ws["color_0"] as? Int) ?: 0, (ws["color_1"] as? Int) ?: 4)
        return IntArray(n) { i ->
            if (i < 2) WATCH_PALETTE[idx[i].coerceIn(0, WATCH_PALETTE.size - 1)]
            else SERIES_COLORS[i % SERIES_COLORS.size]
        }
    }

    /** 🎣 항목 헤더 시각 중 처음/마지막 (HH:mm). */
    private fun catchTimeRange(txt: String): Pair<String, String>? {
        val header = Regex("""^###\s+\d{4}-\d{2}-\d{2}\s+(\d{2}:\d{2}):\d{2}""")
        var first: String? = null
        var last: String? = null
        for (seg in txt.split("\n---\n")) {
            var hm: String? = null
            var hasCatch = false
            for (line in seg.lineSequence()) {
                val t = line.trim()
                val m = header.find(t)
                if (m != null) hm = m.groupValues[1]
                else if (t.startsWith("- 🎣 ")) hasCatch = true
            }
            if (hasCatch && hm != null) {
                if (first == null || hm < first) first = hm
                if (last == null || hm > last) last = hm
            }
        }
        return if (first != null && last != null) first to last else null
    }

    // ── 그래프 이미지 ───────────────────────────────────────

    private fun renderChart(
        date: String,
        names: List<String>,
        hours: List<IntArray>,
        counts: List<Int>,
        tide: List<Pair<Int, Int>>,
        firstAt: String,
        lastAt: String,
        colors: IntArray,
    ): Bitmap {
        val w = 1080; val h = 760
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(0xFF000000.toInt()) // 워치·폰 카운터처럼 어두운 배경
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFEEEEEE.toInt() }
        val sub = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF9E9E9E.toInt(); textSize = 32f }

        text.textSize = 46f; text.isFakeBoldText = true
        c.drawText("$date 조과", 48f, 78f, text)
        c.drawText("총 ${counts.sum()}마리", w - 48f - text.measureText("총 ${counts.sum()}마리"), 78f, text)
        c.drawText("$firstAt ~ $lastAt", 48f, 124f, sub)

        // 범례(어종 색 + 수).
        text.textSize = 34f; text.isFakeBoldText = false
        var lx = 48f
        val dot = Paint(Paint.ANTI_ALIAS_FLAG)
        for (i in names.indices) {
            dot.color = colors[i]
            c.drawCircle(lx + 12f, 170f, 12f, dot)
            val label = "${names[i]} ${counts[i]}"
            c.drawText(label, lx + 32f, 182f, text)
            lx += 32f + text.measureText(label) + 36f
        }

        drawCatchTide(c, RectF(90f, 230f, w - 40f, h - 70f), hours, tide, colors)
        return bmp
    }

    /** 조위(코사인 보간 곡선)+시간당 어종별 막대 — 워치 그래프와 같은 방식. */
    private fun drawCatchTide(
        c: Canvas, area: RectF, hours: List<IntArray>, tide: List<Pair<Int, Int>>, colors: IntArray,
    ) {
        val mins = ArrayList<Int>()
        for (p in tide) mins.add(p.first)
        for (arr in hours) for (hh in 0..23) if (arr[hh] > 0) { mins.add(hh * 60); mins.add(hh * 60 + 60) }
        var startMin = ((mins.minOrNull() ?: 300) / 60) * 60
        var endMin = (((mins.maxOrNull() ?: 960) + 59) / 60) * 60
        if (endMin - startMin < 180) endMin = startMin + 180
        startMin = startMin.coerceIn(0, 1440); endMin = endMin.coerceIn(0, 1440)
        val span = endMin - startMin
        if (span <= 0) return
        val plotW = area.width(); val plotH = area.height(); val base = area.bottom
        fun xOf(m: Int) = area.left + plotW * (m - startMin) / span

        val grid = Paint().apply { color = 0x1FFFFFFF; strokeWidth = 2f }
        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF9E9E9E.toInt(); textSize = 28f; textAlign = Paint.Align.CENTER
        }
        val rightLabel = Paint(label).apply { textAlign = Paint.Align.RIGHT }

        var hr = (startMin + 59) / 60
        while (hr * 60 <= endMin) {
            val x = xOf(hr * 60)
            c.drawLine(x, area.top, x, base, grid)
            if (span <= 12 * 60 || hr % 3 == 0) c.drawText("${hr}시", x, base + 40f, label)
            hr++
        }
        c.drawLine(area.left, base, area.right, base, grid)

        var maxCount = 1
        for (arr in hours) for (v in arr) if (v > maxCount) maxCount = v
        val bar = Paint(Paint.ANTI_ALIAS_FLAG)
        val n = hours.size
        var hh = startMin / 60
        while (hh * 60 < endMin && n > 0) {
            val x0 = xOf(hh * 60); val x1 = xOf(hh * 60 + 60)
            val bw = (x1 - x0 - 12f) / n
            for (i in 0 until n) {
                val cnt = hours[i].getOrElse(hh) { 0 }
                if (cnt <= 0 || bw <= 1f) continue
                val left = x0 + 6f + i * bw + 1f
                val top = base - plotH * cnt / maxCount
                bar.color = colors[i]
                c.drawRoundRect(RectF(left, top, left + bw - 2f, base), 4f, 4f, bar)
                if (bw >= 22f) c.drawText("$cnt", left + (bw - 2f) / 2, top - 8f, label)
            }
            hh++
        }
        c.drawText("0", area.left - 12f, base, rightLabel)
        c.drawText("$maxCount", area.left - 12f, area.top + 24f, rightLabel)

        if (tide.size < 2) return
        var minL = tide.minOf { it.second }
        var maxL = tide.maxOf { it.second }
        if (maxL == minL) maxL = minL + 1
        fun levelAt(m: Int): Float {
            if (m <= tide.first().first) return tide.first().second.toFloat()
            if (m >= tide.last().first) return tide.last().second.toFloat()
            for (i in 0 until tide.size - 1) {
                val a = tide[i]; val b = tide[i + 1]
                if (m in a.first..b.first) {
                    val f = (m - a.first).toFloat() / (b.first - a.first)
                    return a.second + (b.second - a.second) * ((1 - cos(Math.PI * f)) / 2).toFloat()
                }
            }
            return tide.last().second.toFloat()
        }
        fun yOf(lv: Float) = area.top + plotH * (1 - (lv - minL) / (maxL - minL))
        val line = Path(); val fill = Path()
        var x = 0f
        while (x <= plotW) {
            val px = area.left + x
            val y = yOf(levelAt((startMin + span * (x / plotW)).toInt()))
            if (x == 0f) { line.moveTo(px, y); fill.moveTo(px, base); fill.lineTo(px, y) }
            else { line.lineTo(px, y); fill.lineTo(px, y) }
            x += 3f
        }
        fill.lineTo(area.right, base); fill.close()
        val tideColor = 0xFF4FC3F7.toInt() // 워치 그래프와 같은 조위 색
        c.drawPath(fill, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = tideColor; alpha = 40 })
        c.drawPath(line, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = tideColor; style = Paint.Style.STROKE; strokeWidth = 4f
        })
        val pt = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = tideColor }
        val tl = Paint(label).apply { color = tideColor }
        for (p in tide) {
            if (p.first < startMin || p.first > endMin) continue
            val cx = xOf(p.first); val cy = yOf(p.second.toFloat())
            c.drawCircle(cx, cy, 6f, pt)
            c.drawText("${p.second}cm", cx, (cy - 14f).coerceAtLeast(area.top + 24f), tl)
        }
    }

    // ── 갤러리 저장/삭제 ─────────────────────────────────────

    private fun saveToGallery(context: Context, bmp: Bitmap, baseName: String): String? {
        val bytes = ByteArrayOutputStream().also {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
        }.toByteArray()
        val ts = SimpleDateFormat("HHmmss", Locale.US).format(Date())
        return saveImageToGallery(context, bytes, "image/png", "${baseName}_$ts.png")
    }

    /** 이미지를 갤러리(DCIM/nakkda)에 저장하고 파일 경로를 반환(메모 ![](경로)용). 실패 시 null. */
    fun saveImageToGallery(context: Context, bytes: ByteArray, mime: String, displayName: String): String? {
        val relativePath = "DCIM/nakkda"
        val cr = context.contentResolver
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, mime)
                put(MediaStore.Images.Media.RELATIVE_PATH, "$relativePath/")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = cr.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
            cr.openOutputStream(uri)?.use { it.write(bytes) } ?: run {
                cr.delete(uri, null, null); return null
            }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            cr.update(uri, values, null, null)
            var filePath: String? = null
            @Suppress("DEPRECATION")
            cr.query(uri, arrayOf(MediaStore.Images.Media.DATA), null, null, null)
                ?.use { c -> if (c.moveToFirst()) filePath = c.getString(0) }
            if (filePath.isNullOrEmpty()) {
                @Suppress("DEPRECATION")
                filePath = "${Environment.getExternalStorageDirectory().absolutePath}/$relativePath/$displayName"
            }
            MediaScannerConnection.scanFile(context.applicationContext, arrayOf(filePath), arrayOf(mime), null)
            filePath
        } catch (_: Exception) {
            null
        }
    }

    /** 이전 요약 이미지 삭제(앱이 만든 파일이라 권한 없이 가능). 실패해도 무시. */
    private fun deleteImage(context: Context, path: String) {
        try {
            @Suppress("DEPRECATION")
            val n = context.contentResolver.delete(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                "${MediaStore.Images.Media.DATA}=?", arrayOf(path))
            if (n == 0) File(path).delete()
        } catch (_: Exception) {}
    }
}
