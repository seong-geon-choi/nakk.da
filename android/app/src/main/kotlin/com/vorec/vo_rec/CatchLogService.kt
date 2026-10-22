package com.sgchoisg.nakkda

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.*
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.documentfile.provider.DocumentFile
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * 조과(어획) 기록 서비스.
 * - 알림의 '+1' 버튼과 잠금화면 카운터가 보내는 ADD/REMOVE를 받아 **즉시 MD 파일을 수정**한다.
 *   (별도 캐시/flush 없음 — 카운트는 항상 그날 MD 파일의 '- 🎣 어종' 줄 수로 집계.)
 * - +1: 현재 위치(lastLocation) + 시각으로 조과 항목을 파일에 추가.
 * - −1: 그날 파일에서 해당 어종의 마지막 조과 항목 1건을 제거.
 * 파일 I/O는 백그라운드 스레드에서 수행한다.
 */
class CatchLogService : Service() {

    companion object {
        const val PREFS_NAME = "nakkda_catch_prefs"
        const val PREFS_ACTIVE_KEY = "catch_active"
        const val PREFS_SPECIES_KEY = "catch_species"    // JSON array of 어종 라벨
        const val PREFS_STYLES_KEY = "catch_counter_styles" // 카운터별 숫자판 스킨
        const val PREFS_SAVEPATH_KEY = "catch_savepath"  // SAF URI 또는 일반 경로

        const val ACTION_ADD = "com.sgchoisg.nakkda.ADD_CATCH"
        const val ACTION_REMOVE = "com.sgchoisg.nakkda.REMOVE_CATCH"
        const val ACTION_STOP = "com.sgchoisg.nakkda.STOP_CATCH"
        const val EXTRA_SPECIES_INDEX = "speciesIndex"
        const val EXTRA_SPECIES_LIST = "speciesList"

        private const val CHANNEL_ID = "nakkda_catch_channel_v2"
        private const val CHANNEL_ID_OLD = "nakkda_catch_channel"
        private const val NOTIFICATION_ID = 1008

        fun prefsOf(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        private fun strArray(json: String?): List<String> = try {
            val a = JSONArray(json ?: "[]")
            (0 until a.length()).map { a.getString(it) }
        } catch (_: Exception) { emptyList() }

        /** 어종 목록(빈칸 제외 → 1개만 지정 시 1개). */
        fun loadSpecies(context: Context): List<String> =
            strArray(prefsOf(context).getString(PREFS_SPECIES_KEY, "[]"))
                .map { it.trim() }.filter { it.isNotEmpty() }

        /** 카운터별 스킨 목록(저장된 것). 부족분은 호출측에서 기본값으로 채운다. */
        fun loadStyles(context: Context): List<String> =
            strArray(prefsOf(context).getString(PREFS_STYLES_KEY, "[]"))

        // ── MD 파일 입출력(SAF/일반 경로 공용) ──────────────────
        private fun savePath(context: Context): String =
            prefsOf(context).getString(PREFS_SAVEPATH_KEY, "") ?: ""

        private fun isSaf(p: String) = p.startsWith("content://")
        private fun todayStr() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        private fun filename() = "${todayStr()}.md"
        private fun fileHeader() = "# ${todayStr()}\n"
        private fun fmtCoord(v: Double) = String.format(Locale.US, "%.4f", v)

        /** Dart MdSerializer.serializeEntry와 동일 형식의 조과 항목(🎣). */
        private fun catchEntry(species: String, lat: Double?, lng: Double?): String {
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            val header = if (lat != null && lng != null)
                "### $ts | 🛰 ${fmtCoord(lat)}, ${fmtCoord(lng)}" else "### $ts"
            return "\n---\n\n$header\n- 🎣 $species\n"
        }

        private fun safTree(context: Context, uri: String): DocumentFile? =
            try { DocumentFile.fromTreeUri(context, Uri.parse(uri)) } catch (_: Exception) { null }

        private fun readMd(context: Context): String? {
            val sp = savePath(context)
            if (sp.isEmpty()) return null
            return try {
                if (isSaf(sp)) {
                    val f = safTree(context, sp)?.findFile(filename()) ?: return null
                    context.contentResolver.openInputStream(f.uri)
                        ?.use { it.bufferedReader(Charsets.UTF_8).readText() }
                } else {
                    val f = File("$sp/${filename()}")
                    if (f.exists()) f.readText(Charsets.UTF_8) else null
                }
            } catch (_: Exception) { null }
        }

        private fun writeMd(context: Context, content: String) {
            val sp = savePath(context)
            if (sp.isEmpty()) return
            try {
                if (isSaf(sp)) {
                    val tree = safTree(context, sp) ?: return
                    val f = tree.findFile(filename())
                        ?: tree.createFile("text/markdown", filename()) ?: return
                    context.contentResolver.openOutputStream(f.uri, "wt")
                        ?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                } else {
                    File("$sp/${filename()}").writeText(content, Charsets.UTF_8)
                }
            } catch (_: Exception) {}
        }

        /** 조과 항목 추가(파일 없으면 헤더부터 생성). */
        fun appendCatchToFile(context: Context, species: String, lat: Double?, lng: Double?) {
            val existing = readMd(context) ?: fileHeader()
            writeMd(context, existing + catchEntry(species, lat, lng))
        }

        /** 그날 파일에서 해당 어종의 마지막 조과 항목 1건 제거. */
        fun removeLastCatchFromFile(context: Context, species: String) {
            val txt = readMd(context) ?: return
            val segs = txt.split("\n---\n").toMutableList()
            var removeAt = -1
            for (i in 1 until segs.size) {
                if (segs[i].lineSequence().any { it.trim() == "- 🎣 $species" }) removeAt = i
            }
            if (removeAt >= 0) {
                segs.removeAt(removeAt)
                writeMd(context, segs.joinToString("\n---\n"))
            }
        }

        /** 그날 파일의 어종별 조과 수(- 🎣 어종 줄 집계). */
        fun loadCountsFromFile(context: Context): Map<String, Int> {
            val txt = readMd(context) ?: return emptyMap()
            val m = HashMap<String, Int>()
            for (line in txt.lineSequence()) {
                val t = line.trim()
                if (t.startsWith("- 🎣 ")) {
                    val sp = t.removePrefix("- 🎣 ").trim()
                    if (sp.isNotEmpty()) m[sp] = (m[sp] ?: 0) + 1
                }
            }
            return m
        }

        fun loadCount(context: Context, species: String): Int =
            loadCountsFromFile(context)[species] ?: 0

        fun start(context: Context, speciesJson: String) {
            val intent = Intent(context, CatchLogService::class.java)
                .apply { putExtra(EXTRA_SPECIES_LIST, speciesJson) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CatchLogService::class.java))
        }
    }

    private val io = Executors.newSingleThreadExecutor()

    // 날짜가 바뀌면(자정) 경로 기록처럼 세션을 종료한다.
    private val dateChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            setActive(false)
            stopSelf()
        }
    }

    private fun prefs(): SharedPreferences = prefsOf(this)
    private fun setActive(active: Boolean) =
        prefs().edit().putBoolean(PREFS_ACTIVE_KEY, active).apply()
    private fun speciesList(): List<String> = loadSpecies(this)

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // 서비스가 떠 있으면(=알림이 보이면) 활성으로 간주 → 메모화면 FAB 상태와 일치.
        setActive(true)
        try {
            // 초기 알림은 파일을 읽지 않는 가벼운 형태로 띄우고(메인 스레드 I/O 회피),
            // 곧바로 백그라운드에서 카운트를 읽어 갱신한다.
            val notif = buildNotification(countsPlaceholder())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notif)
            }
        } catch (e: SecurityException) {
            stopSelf()
        }
        // 자정(날짜 변경) 시 자동 종료 — 경로 기록 서비스와 동일.
        val filter = IntentFilter(Intent.ACTION_DATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dateChangedReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(dateChangedReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                setActive(false)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_ADD -> {
                addCatch(intent.getIntExtra(EXTRA_SPECIES_INDEX, -1))
                return START_STICKY
            }
            ACTION_REMOVE -> {
                removeCatch(intent.getIntExtra(EXTRA_SPECIES_INDEX, -1))
                return START_STICKY
            }
            else -> {
                val speciesJson = intent?.getStringExtra(EXTRA_SPECIES_LIST) ?: "[]"
                prefs().edit()
                    .putString(PREFS_SPECIES_KEY, speciesJson)
                    .putBoolean(PREFS_ACTIVE_KEY, true)
                    .apply()
                io.execute { updateNotification() }
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        setActive(false)
        try { unregisterReceiver(dateChangedReceiver) } catch (_: Exception) {}
        io.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** +1: 현재 위치를 얻어 파일에 조과 항목을 추가하고 알림 갱신(모두 백그라운드). */
    @SuppressLint("MissingPermission")
    private fun addCatch(index: Int) {
        val species = speciesList().getOrNull(index) ?: return
        fun commit(lat: Double?, lng: Double?) = io.execute {
            appendCatchToFile(this, species, lat, lng)
            updateNotification()
        }
        try {
            LocationServices.getFusedLocationProviderClient(this).lastLocation
                .addOnSuccessListener { loc -> commit(loc?.latitude, loc?.longitude) }
                .addOnFailureListener { commit(null, null) }
        } catch (_: Exception) {
            commit(null, null)
        }
    }

    /** −1: 파일에서 해당 어종 마지막 항목 제거 + 알림 갱신(백그라운드). */
    private fun removeCatch(index: Int) {
        val species = speciesList().getOrNull(index) ?: return
        io.execute {
            removeLastCatchFromFile(this, species)
            updateNotification()
        }
    }

    // ── 알림 ───────────────────────────────────────────────
    private fun countsPlaceholder(): String {
        val species = speciesList()
        if (species.isEmpty()) return "기록을 시작하세요"
        return species.joinToString("  ·  ") { "$it …" }
    }

    /** "주꾸미 7 · 갑오징어 3" — 파일에서 집계(백그라운드에서만 호출). */
    private fun countsSummary(): String {
        val species = speciesList()
        if (species.isEmpty()) return "기록을 시작하세요"
        val counts = loadCountsFromFile(this)
        return species.joinToString("  ·  ") { "$it ${counts[it] ?: 0}" }
    }

    private fun updateNotification() {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification(countsSummary()))
    }

    private fun buildRemote(showCounts: Boolean, summary: String): RemoteViews {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val species = speciesList()
        val rv = RemoteViews(packageName, R.layout.catch_notification)
        if (showCounts) {
            rv.setViewVisibility(R.id.catch_counts, View.VISIBLE)
            rv.setTextViewText(R.id.catch_counts, summary)
        } else {
            rv.setViewVisibility(R.id.catch_counts, View.GONE)
        }
        val btnIds = intArrayOf(R.id.catch_btn0, R.id.catch_btn1)
        for (i in btnIds.indices) {
            if (i < species.size) {
                rv.setViewVisibility(btnIds[i], View.VISIBLE)
                rv.setTextViewText(btnIds[i], "${species[i]} +1")
                val addPi = PendingIntent.getService(
                    this, 100 + i,
                    Intent(this, CatchLogService::class.java).apply {
                        action = ACTION_ADD
                        putExtra(EXTRA_SPECIES_INDEX, i)
                    },
                    piFlags
                )
                rv.setOnClickPendingIntent(btnIds[i], addPi)
            } else {
                rv.setViewVisibility(btnIds[i], View.GONE)
            }
        }
        return rv
    }

    private fun buildNotification(summary: String): Notification {
        val stopPi = PendingIntent.getService(
            this, 201,
            Intent(this, CatchLogService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openPi = PendingIntent.getActivity(
            this, 202,
            Intent(this, CatchCounterActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("조과 기록 중")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setOngoing(false).setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(buildRemote(false, summary)) // 접힘: 버튼만
            .setCustomBigContentView(buildRemote(true, summary)) // 펼침: 카운트 + 버튼
            .setContentIntent(openPi) // 본문 탭 → 큰 카운터 화면
            .setDeleteIntent(stopPi) // 스와이프로 닫으면 세션 중지
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            try { nm.deleteNotificationChannel(CHANNEL_ID_OLD) } catch (_: Exception) {}
            val channel = NotificationChannel(
                CHANNEL_ID, "조과 기록", NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "어획 기록 세션"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }
    }
}
