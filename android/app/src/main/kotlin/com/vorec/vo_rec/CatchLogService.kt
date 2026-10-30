package com.sgchoisg.nakkda

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.*
import android.speech.tts.TextToSpeech
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.documentfile.provider.DocumentFile
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * 추임새/삭제 멘트 1개. 텍스트(TTS) 또는 오디오 파일 중 하나.
 * - [type] "text"면 [value]가 발화할 문구, "audio"면 [value]가 내부 저장 파일명.
 * - [label] 오디오일 때 표시용 원본 파일명.
 */
data class SoundItem(val type: String, val value: String, val label: String = "") {
    val isAudio: Boolean get() = type == TYPE_AUDIO
    companion object {
        const val TYPE_TEXT = "text"
        const val TYPE_AUDIO = "audio"
    }
}

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

        // 조과 효과음(TTS 음성) 사용 여부. 기본 켜짐.
        const val PREFS_SOUND_ENABLED_KEY = "catch_sound_enabled"
        // +1 때 랜덤 재생할 추임새 멘트(JSON array). 비면 DEFAULT_SOUND_PHRASES.
        const val PREFS_SOUND_PHRASES_KEY = "catch_sound_phrases"
        val DEFAULT_SOUND_PHRASES =
            listOf("한 마리!", "오이예예예애애", "좋오오오았어!", "나이쓰!", "힛트으!")
        // 삭제(−1) 때 랜덤 재생할 멘트(JSON array). 비면 DEFAULT_SOUND_DEL_PHRASES.
        const val PREFS_SOUND_DEL_PHRASES_KEY = "catch_sound_del_phrases"
        val DEFAULT_SOUND_DEL_PHRASES = listOf("취소", "뺐다", "아이고")
        // +1 안내 모드: "phrase"(추임새만) / "count"(마릿수만) / "both"(추임새+10단위). 기본 both.
        const val PREFS_SOUND_MODE_KEY = "catch_sound_mode"
        const val SOUND_MODE_DEFAULT = "both"
        // TTS 톤(pitch)·속도(rate)·음성(voice 이름). 기본 1.0 / 1.0 / 엔진 기본.
        const val PREFS_SOUND_PITCH_KEY = "catch_sound_pitch"
        const val PREFS_SOUND_RATE_KEY = "catch_sound_rate"
        const val PREFS_SOUND_VOICE_KEY = "catch_sound_voice"
        // 카운트 진동 알림 사용 여부(효과음·볼륨과 독립). 기본 꺼짐.
        const val PREFS_VIBRATE_ENABLED_KEY = "catch_vibrate_enabled"

        const val ACTION_ADD = "com.sgchoisg.nakkda.ADD_CATCH"
        const val ACTION_REMOVE = "com.sgchoisg.nakkda.REMOVE_CATCH"
        // 어종 무관: 그날 가장 최근에 추가된 조과 1건을 제거.
        const val ACTION_REMOVE_LAST = "com.sgchoisg.nakkda.REMOVE_LAST_CATCH"
        const val ACTION_STOP = "com.sgchoisg.nakkda.STOP_CATCH"
        const val EXTRA_SPECIES_INDEX = "speciesIndex"
        const val EXTRA_SPECIES_LIST = "speciesList"

        // 블루투스 리모컨 키 매핑: JSON { "add:0": keyCode, "rem:0": keyCode, ... }
        const val PREFS_BTMAP_KEY = "catch_btmap"
        // 어종 무관 '최근 1개 삭제' 매핑 액션 키.
        const val ACTION_REM_LAST = "rem:last"
        // 블루투스 버튼 연동 사용 여부(사용자가 켠 경우만 작동). 기본 꺼짐.
        const val PREFS_BTMAP_ENABLED_KEY = "catch_btmap_enabled"
        // 볼륨 버튼으로 카운트(원격 볼륨 후킹). 켜면 볼륨 키가 백그라운드에서도 들어오나
        // 그동안 하드웨어 볼륨으로 음악 볼륨 조절은 안 된다. 기본 꺼짐.
        const val PREFS_BTVOL_ENABLED_KEY = "catch_btvol_enabled"
        // 집계 변동(리모컨으로 ±) 시 카운터 화면이 즉시 다시 그리도록 알리는 로컬 브로드캐스트.
        const val ACTION_COUNTS_CHANGED = "com.sgchoisg.nakkda.COUNTS_CHANGED"
        // 설정에서 연동 on/off를 바꿨을 때 실행 중인 서비스가 세션을 즉시 재동기화하도록 하는 액션.
        const val ACTION_SYNC_BT = "com.sgchoisg.nakkda.SYNC_BT"

        /** 블루투스 버튼 연동이 사용자에 의해 켜져 있는지(기본 꺼짐). */
        fun isBtEnabled(context: Context): Boolean =
            prefsOf(context).getBoolean(PREFS_BTMAP_ENABLED_KEY, false)

        /** 볼륨 버튼 후킹(원격 볼륨)이 켜져 있는지(기본 꺼짐). */
        fun isBtVolEnabled(context: Context): Boolean =
            prefsOf(context).getBoolean(PREFS_BTVOL_ENABLED_KEY, false)

        /** 매핑(action→keyCode)을 읽는다. 값이 없거나 깨지면 빈 맵. */
        fun loadKeyMap(context: Context): Map<String, Int> {
            val raw = prefsOf(context).getString(PREFS_BTMAP_KEY, "{}") ?: "{}"
            return try {
                val obj = org.json.JSONObject(raw)
                val m = HashMap<String, Int>()
                for (k in obj.keys()) {
                    val v = obj.optInt(k, -1)
                    if (v >= 0) m[k] = v
                }
                m
            } catch (_: Exception) { emptyMap() }
        }

        /**
         * 재생/정지 계열 키를 하나로 정규화.
         * 많은 블루투스 이어폰이 같은 버튼을 재생 상태에 따라 PLAY(126)/PAUSE(127)로
         * 번갈아 보내므로, 이들(+PLAY_PAUSE/HEADSETHOOK)을 PLAY_PAUSE로 합쳐 매칭한다.
         * 다음곡/이전곡 등은 그대로 두어 +1/−1을 구분할 수 있게 한다.
         */
        fun canonicalKey(keyCode: Int): Int = when (keyCode) {
            android.view.KeyEvent.KEYCODE_MEDIA_PLAY,
            android.view.KeyEvent.KEYCODE_MEDIA_PAUSE,
            android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            android.view.KeyEvent.KEYCODE_HEADSETHOOK ->
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            else -> keyCode
        }

        /**
         * 눌린 keyCode에 매핑된 action("add:0"/"rem:1" 등)을 역조회(정규화 비교).
         * 연동 스위치가 꺼져 있으면 매핑이 있어도 무시한다(화면 켜짐/꺼짐 공통 게이트).
         */
        fun actionForKey(context: Context, keyCode: Int): String? {
            if (!isBtEnabled(context)) return null
            val target = canonicalKey(keyCode)
            return loadKeyMap(context).entries
                .firstOrNull { canonicalKey(it.value) == target }?.key
        }

        /** 화면 꺼짐 상태에서 전역 수신 가능한 미디어 키인지. */
        fun isMediaKey(keyCode: Int): Boolean = when (keyCode) {
            android.view.KeyEvent.KEYCODE_MEDIA_PLAY,
            android.view.KeyEvent.KEYCODE_MEDIA_PAUSE,
            android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            android.view.KeyEvent.KEYCODE_MEDIA_NEXT,
            android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS,
            android.view.KeyEvent.KEYCODE_MEDIA_STOP,
            android.view.KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
            android.view.KeyEvent.KEYCODE_MEDIA_REWIND,
            android.view.KeyEvent.KEYCODE_HEADSETHOOK -> true
            else -> false
        }

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

        /** 조과 효과음(TTS) 사용 여부. 기본 켜짐. */
        fun isSoundEnabled(context: Context): Boolean =
            prefsOf(context).getBoolean(PREFS_SOUND_ENABLED_KEY, true)

        /** +1 추임새 항목(텍스트·오디오 혼합). 비면 기본 텍스트 세트로 폴백(무음 방지). */
        fun loadAddItems(context: Context): List<SoundItem> =
            loadSoundItems(context, PREFS_SOUND_PHRASES_KEY, DEFAULT_SOUND_PHRASES)

        /** 삭제(−1) 멘트 항목(텍스트·오디오 혼합). 비면 기본 세트로 폴백. */
        fun loadDelItems(context: Context): List<SoundItem> =
            loadSoundItems(context, PREFS_SOUND_DEL_PHRASES_KEY, DEFAULT_SOUND_DEL_PHRASES)

        /**
         * 저장된 사운드 항목을 파싱한다. 하위호환:
         * 요소가 문자열이면 텍스트 추임새로(구형식), 객체면 {t,v,label}로 해석.
         */
        fun loadSoundItems(
            context: Context, key: String, defaults: List<String>): List<SoundItem> {
            val items = parseItems(prefsOf(context).getString(key, "[]"))
            return items.ifEmpty { defaults.map { SoundItem(SoundItem.TYPE_TEXT, it) } }
        }

        private fun parseItems(json: String?): List<SoundItem> = try {
            val a = JSONArray(json ?: "[]")
            val out = ArrayList<SoundItem>()
            for (i in 0 until a.length()) {
                val e = a.opt(i)
                if (e is JSONObject) {
                    val v = e.optString("v", "").trim()
                    if (v.isNotEmpty()) {
                        out.add(SoundItem(
                            e.optString("t", SoundItem.TYPE_TEXT),
                            v,
                            e.optString("label", "")))
                    }
                } else {
                    val s = e?.toString()?.trim() ?: ""
                    if (s.isNotEmpty()) out.add(SoundItem(SoundItem.TYPE_TEXT, s))
                }
            }
            out
        } catch (_: Exception) { emptyList() }

        // ── 오디오 추임새 파일 저장(앱 내부: filesDir/catch_sounds) ──
        private fun soundsDir(context: Context): File {
            val d = File(context.filesDir, "catch_sounds")
            if (!d.exists()) d.mkdirs()
            return d
        }

        fun soundFile(context: Context, name: String): File = File(soundsDir(context), name)

        /** [srcPath]의 오디오를 내부 저장소로 복사하고 저장 파일명을 돌려준다(실패 시 null). */
        fun importSoundFile(context: Context, srcPath: String, origName: String?): String? =
            try {
                val ext = (origName ?: srcPath).substringAfterLast('.', "").lowercase()
                val suffix = if (ext.isNotEmpty() && ext.length <= 5) ".$ext" else ""
                val name = "snd_${System.currentTimeMillis()}$suffix"
                File(srcPath).inputStream().use { input ->
                    soundFile(context, name).outputStream().use { input.copyTo(it) }
                }
                name
            } catch (_: Exception) { null }

        fun deleteSoundFile(context: Context, name: String) {
            try { soundFile(context, name).delete() } catch (_: Exception) {}
        }

        /** 목록에서 참조되지 않는 오디오 파일을 정리(목록 저장 후 호출). */
        fun pruneSoundFiles(context: Context) {
            try {
                val used = (loadAddItems(context) + loadDelItems(context))
                    .filter { it.isAudio }.map { it.value }.toSet()
                soundsDir(context).listFiles()?.forEach { if (it.name !in used) it.delete() }
            } catch (_: Exception) {}
        }

        /** 복사된 오디오 파일 전체 삭제(초기화 시). */
        fun clearAllSoundFiles(context: Context) {
            try { soundsDir(context).listFiles()?.forEach { it.delete() } } catch (_: Exception) {}
        }

        /** +1 안내 모드. */
        fun soundMode(context: Context): String =
            prefsOf(context).getString(PREFS_SOUND_MODE_KEY, SOUND_MODE_DEFAULT)
                ?: SOUND_MODE_DEFAULT

        /** TTS 톤(0.5~2.0, 기본 1.0). */
        fun soundPitch(context: Context): Float =
            prefsOf(context).getFloat(PREFS_SOUND_PITCH_KEY, 1.0f).coerceIn(0.5f, 2.0f)

        /** TTS 속도(0.5~2.0, 기본 1.0). */
        fun soundRate(context: Context): Float =
            prefsOf(context).getFloat(PREFS_SOUND_RATE_KEY, 1.0f).coerceIn(0.5f, 2.0f)

        /** 선택한 음성 이름(빈 문자열이면 엔진 기본). */
        fun soundVoice(context: Context): String =
            prefsOf(context).getString(PREFS_SOUND_VOICE_KEY, "") ?: ""

        /** 카운트 진동 알림 사용 여부(효과음·볼륨과 독립). 기본 꺼짐(필요 시 켬). */
        fun isVibrateEnabled(context: Context): Boolean =
            prefsOf(context).getBoolean(PREFS_VIBRATE_ENABLED_KEY, false)

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

        /** 어종 무관: 그날 파일에서 가장 최근 조과 항목 1건(🎣 포함 블록) 제거. */
        fun removeLastAnyCatchFromFile(context: Context) {
            val txt = readMd(context) ?: return
            val segs = txt.split("\n---\n").toMutableList()
            var removeAt = -1
            for (i in 1 until segs.size) {
                if (segs[i].lineSequence().any { it.trim().startsWith("- 🎣 ") }) removeAt = i
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

    // 블루투스 리모컨/이어폰 미디어 버튼 수신용 무음 세션(포커스 미요청).
    private var mediaButton: MediaButtonSession? = null
    // 현재 세션이 볼륨 후킹 상태로 떠 있는지(토글 변경 시 재생성 판단용).
    private var mediaButtonVol = false

    // 조과 효과음용 TTS(한국어). onCreate에서 초기화, onDestroy에서 종료.
    private var tts: TextToSpeech? = null
    @Volatile private var ttsReady = false
    @Volatile private var player: MediaPlayer? = null
    // 마지막으로 적용한 음성 이름(바뀔 때만 setVoice 조회).
    private var appliedVoice: String? = null
    // 알림 post 시각을 세션 동안 고정 — +1 갱신 때마다 현재 시각으로 찍히면
    // 알림창에서 맨 위로 재정렬되므로, 한 번 정해 유지해 위치를 보존한다.
    private val notifWhen = System.currentTimeMillis()

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
            val notif = buildNotification(null)
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
        // 리모컨 미디어 버튼 수신(화면 꺼짐 포함).
        syncMediaButton()
        // 조과 효과음(TTS) 초기화 — 첫 발화 지연을 줄이려 서비스 시작 때 엔진을 띄운다.
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                try { tts?.language = Locale.KOREAN } catch (_: Exception) {}
                ttsReady = true
            }
        }
    }

    /**
     * 카운트 피드백: 효과음과 진동은 서로 독립이다.
     * - 효과음 켜짐 + 미디어 볼륨 ≥1: TTS([textIfSound]) — 미디어 스트림이라 들린다.
     * - 진동 켜짐: 미디어 볼륨·효과음과 무관하게 항상 짧은 진동(동시 발생 가능).
     */
    private fun countFeedback(itemIfSound: () -> SoundItem?) {
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager
        val mediaVol = am?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
        if (isSoundEnabled(this) && mediaVol > 0) {
            val item = itemIfSound()
            if (item != null) playItem(item)
        }
        if (isVibrateEnabled(this)) vibrateShort()
    }

    /** 진행 중인 효과음(TTS·오디오)을 모두 중단 — 새 카운트 시작 전 flush. */
    private fun stopPlayback() {
        try { tts?.stop() } catch (_: Exception) {}
        val p = player
        player = null
        try { p?.stop(); p?.release() } catch (_: Exception) {}
    }

    /** 추임새 1개 재생: 텍스트는 TTS, 오디오는 내부 저장 파일을 미디어 스트림으로. */
    private fun playItem(item: SoundItem) {
        stopPlayback()
        if (item.isAudio) playAudio(item.value) else speak(item.value, flush = true)
    }

    /** 내부 저장 오디오 파일을 재생(미디어 스트림 → 음악과 공존·미디어 볼륨 기준). */
    private fun playAudio(fileName: String) {
        val f = soundFile(this, fileName)
        if (!f.exists()) return
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build())
            mp.setDataSource(f.absolutePath)
            mp.setOnCompletionListener {
                try { it.release() } catch (_: Exception) {}
                if (player === it) player = null
            }
            mp.setOnErrorListener { p, _, _ ->
                try { p.release() } catch (_: Exception) {}
                if (player === p) player = null
                true
            }
            mp.prepare() // 로컬 짧은 클립이라 즉시 준비(io 스레드에서 호출됨).
            player = mp
            mp.start()
        } catch (_: Exception) {}
    }

    /** 짧은 진동(약 40ms). */
    private fun vibrateShort() {
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }
            vib.vibrate(
                VibrationEffect.createOneShot(40, VibrationEffect.DEFAULT_AMPLITUDE))
        } catch (_: Exception) {}
    }

    /** +1 안내 항목을 모드에 맞게 생성. 마릿수 안내는 항상 텍스트(TTS). */
    private fun catchAnnounce(species: String): SoundItem? = when (soundMode(this)) {
        "phrase" -> loadAddItems(this).randomOrNull()
        "count" -> SoundItem(SoundItem.TYPE_TEXT, "$species ${loadCount(this, species)}마리")
        else -> { // both: 10·20…500마리는 마릿수, 그 외는 추임새
            val n = loadCount(this, species)
            if (n in 1..500 && n % 10 == 0) SoundItem(SoundItem.TYPE_TEXT, "$species ${n}마리")
            else loadAddItems(this).randomOrNull()
        }
    }

    /** TTS 발화. flush=true면 기존 큐를 끊고 즉시, false면 뒤에 이어서. */
    private fun speak(text: String, flush: Boolean) {
        if (!ttsReady) return
        val t = tts ?: return
        try {
            t.setPitch(soundPitch(this))
            t.setSpeechRate(soundRate(this))
            val vname = soundVoice(this)
            if (vname != appliedVoice) {
                appliedVoice = vname
                val v = if (vname.isEmpty()) t.defaultVoice
                        else t.voices?.firstOrNull { it.name == vname }
                if (v != null) t.voice = v
            }
        } catch (_: Exception) {}
        val mode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        try {
            t.speak(text, mode, null, "nakkda_catch_${System.currentTimeMillis()}")
        } catch (_: Exception) {}
    }

    /**
     * 연동 사용 여부 + 매핑 존재 여부에 맞춰 무음 미디어 세션을 켜고 끈다.
     * 스위치가 꺼져 있거나 매핑이 하나도 없으면 세션을 띄우지 않는다 —
     * 리모컨을 안 쓰는 사용자의 이어폰 음악 버튼 제어권을 뺏지 않기 위함.
     */
    private fun syncMediaButton() {
        val has = isBtEnabled(this) && loadKeyMap(this).isNotEmpty()
        val wantVol = has && isBtVolEnabled(this)
        if (has && (mediaButton == null || mediaButtonVol != wantVol)) {
            // 볼륨 후킹 on/off가 바뀌면 세션을 재생성해야 원격 볼륨 선언이 반영된다.
            mediaButton?.stop()
            mediaButtonVol = wantVol
            mediaButton = MediaButtonSession(this, "nakkda_catch", hookVolume = wantVol) { keyCode ->
                onRemoteKey(keyCode)
            }.also { it.start() }
        } else if (!has && mediaButton != null) {
            mediaButton?.stop()
            mediaButton = null
            mediaButtonVol = false
        }
    }

    /** 리모컨 키 → 매핑된 액션 실행(화면 꺼짐/백그라운드 경로). */
    private fun onRemoteKey(keyCode: Int) {
        val action = actionForKey(this, keyCode) ?: return
        if (action == ACTION_REM_LAST) { removeLastAnyCatch(); return }
        val idx = action.substringAfter(':', "").toIntOrNull() ?: return
        when {
            action.startsWith("add:") -> addCatch(idx)
            action.startsWith("rem:") -> removeCatch(idx)
        }
    }

    private fun sendCountsChanged() {
        try {
            sendBroadcast(Intent(ACTION_COUNTS_CHANGED).setPackage(packageName))
        } catch (_: Exception) {}
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
            ACTION_REMOVE_LAST -> {
                removeLastAnyCatch()
                return START_STICKY
            }
            ACTION_SYNC_BT -> {
                // 설정에서 연동 on/off가 바뀌면 세션을 즉시 반영(어종 목록은 건드리지 않음).
                syncMediaButton()
                return START_STICKY
            }
            else -> {
                val speciesJson = intent?.getStringExtra(EXTRA_SPECIES_LIST) ?: "[]"
                prefs().edit()
                    .putString(PREFS_SPECIES_KEY, speciesJson)
                    .putBoolean(PREFS_ACTIVE_KEY, true)
                    .apply()
                syncMediaButton()
                io.execute { updateNotification() }
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        setActive(false)
        try { unregisterReceiver(dateChangedReceiver) } catch (_: Exception) {}
        mediaButton?.stop()
        mediaButton = null
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        tts = null
        try { player?.release() } catch (_: Exception) {}
        player = null
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
            // 음성 문구는 안내 모드에 따름(진동은 countFeedback 내부에서 별도 처리).
            countFeedback { catchAnnounce(species) }
            updateNotification()
            sendCountsChanged()
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
            val had = loadCount(this, species) > 0
            removeLastCatchFromFile(this, species)
            // 실제로 지워진 경우에만 삭제 피드백(멘트/오디오 / 진동).
            if (had) countFeedback { loadDelItems(this).randomOrNull() }
            updateNotification()
            sendCountsChanged()
        }
    }

    /** 어종 무관: 가장 최근 조과 1건 제거 + 알림 갱신(백그라운드). */
    private fun removeLastAnyCatch() {
        io.execute {
            val had = loadCountsFromFile(this).values.any { it > 0 }
            removeLastAnyCatchFromFile(this)
            if (had) countFeedback { loadDelItems(this).randomOrNull() }
            updateNotification()
            sendCountsChanged()
        }
    }

    // ── 알림 ───────────────────────────────────────────────
    /** 어종별 현재 집계(어종 인덱스 순). 파일 읽기이므로 백그라운드에서만 호출. */
    private fun currentCounts(): List<Int> {
        val counts = loadCountsFromFile(this)
        return speciesList().map { counts[it] ?: 0 }
    }

    private fun updateNotification() {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification(currentCounts()))
    }

    /** counts=null이면 집계 미상(초기 알림) — 버튼에 수를 표시하지 않는다. */
    private fun buildRemote(counts: List<Int>?): RemoteViews {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val species = speciesList()
        val rv = RemoteViews(packageName, R.layout.catch_notification)
        val btnIds = intArrayOf(R.id.catch_btn0, R.id.catch_btn1)
        for (i in btnIds.indices) {
            if (i < species.size) {
                rv.setViewVisibility(btnIds[i], View.VISIBLE)
                // 버튼에 "어종 +1"과 현재 누적 수를 함께 표시(본문 카운트줄 제거).
                val label = if (counts != null)
                    "${species[i]} +1\n${counts.getOrElse(i) { 0 }}마리"
                else "${species[i]} +1"
                rv.setTextViewText(btnIds[i], label)
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

    private fun buildNotification(counts: List<Int>?): Notification {
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
            .setWhen(notifWhen).setShowWhen(false) // post 시각 고정 → 재정렬 방지
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            // 접힘·펼침 모두 동일: 버튼에 누적 수까지 표시하므로 펼칠 필요가 없다.
            .setCustomContentView(buildRemote(counts))
            .setCustomBigContentView(buildRemote(counts))
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
