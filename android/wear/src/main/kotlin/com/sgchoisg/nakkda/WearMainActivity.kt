package com.sgchoisg.nakkda

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.PixelCopy
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import androidx.wear.ambient.AmbientLifecycleObserver
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.cos

/** 좌/우 영역 배경색 팔레트(16색). 영역을 길게 누르면 그리드 피커에서 선택. */
private val PALETTE = listOf(
    Color(0xFF1565C0), // 0 파랑
    Color(0xFF1E88E5), // 1 하늘
    Color(0xFF00838F), // 2 청록
    Color(0xFF00897B), // 3 틸
    Color(0xFF2E7D32), // 4 초록
    Color(0xFF7CB342), // 5 연두
    Color(0xFFF9A825), // 6 노랑
    Color(0xFFEF6C00), // 7 주황
    Color(0xFFD84315), // 8 진주황
    Color(0xFFC62828), // 9 빨강
    Color(0xFFAD1457), // 10 분홍
    Color(0xFF6A1B9A), // 11 보라
    Color(0xFF4527A0), // 12 진보라
    Color(0xFF455A64), // 13 청회색
    Color(0xFF37474F), // 14 진회색
    Color(0xFF263238), // 15 먹색
)

/**
 * 조과 카운터 워치 — 어종별 좌/우 분할 표시 + 탭 카운트.
 * - 각 영역 위쪽 탭=+1, 아래쪽 탭=−1 (해당 어종). 길게 누르면 그 영역 색상 순환.
 * - 화면 정중앙 탭 → 폰의 재생 중 추임새/TTS 중지.
 * - 어종 1개면 화면 전체를 하나의 카운터로 구성.
 * 데이터: 폰이 /nakkda/count/state 로 names[]·counts[] push → 실시간 표시.
 */
class WearMainActivity : ComponentActivity() {

    private val messageClient by lazy { Wearable.getMessageClient(this) }
    private val dataClient by lazy { Wearable.getDataClient(this) }
    private lateinit var prefs: SharedPreferences

    private var names by mutableStateOf<List<String>>(emptyList())
    private var counts by mutableStateOf<List<Int>>(emptyList())
    private var colorIdx by mutableStateOf(intArrayOf(0, 4))
    // 그래프 페이지용(시간당 조과 + 조위) — 폰이 /nakkda/chart/state로 push.
    private var chartNames by mutableStateOf<List<String>>(emptyList())
    private var chartHours by mutableStateOf<List<IntArray>>(emptyList())
    private var tideMins by mutableStateOf<List<Int>>(emptyList())
    private var tideLevels by mutableStateOf<List<Int>>(emptyList())
    // 카메라 페이지에서 '실행'을 눌러 폰 카메라를 연 상태(셔터 UI 노출). 페이지 이탈 시 false.
    private var cameraLaunched by mutableStateOf(false)
    // 앰비언트(화면 꺼짐) 상태 — true면 저전력 AoD만 표시하고 앱은 활성으로 유지(워치페이스로
    // 안 돌아감). 화면이 다시 켜지면 그대로 카운터 화면이 유지된다.
    private var ambient by mutableStateOf(false)
    // 유사 AOD 표시 상태 — true면 어두운 오버레이(AmbientOverlay)로 카운트만 희미하게.
    private var dimmed by mutableStateOf(false)
    // 폰에서 관리하는 워치 설정(/nakkda/settings). 값은 prefs에 저장돼 오프라인에도 유지.
    private var brightOn = DEF_BRIGHT_ON      // 켜짐 밝기 %(0=시스템 밝기 따름)
    private var dimLevel = DEF_DIM_LEVEL      // 어두울 때 밝기 %
    private var dimIdleSec = DEF_DIM_IDLE_SEC // 어둡게 되기까지 초(0=어둡게 안 함)
    private var keepOn = false                // 화면 항상 켜두기(기본 끔 — 배터리)
    private var vibrate = false               // 카운트 시 진동
    // 요약 화면(AmbientOverlay) 시계·마지막 조과 경과 시간 표시.
    private var showClock by mutableStateOf(true)
    private var showElapsed by mutableStateOf(true)
    // 절전 색상: 카운터 배경을 어둡게(OLED는 밝은 면적만큼 전력 소모).
    private var ecoColors by mutableStateOf(false)
    // 마지막 조과 시각(epoch ms, 0=없음/모름). 폰이 오늘 메모 기준으로 push, +1은 즉시 반영.
    private var lastCatchAt by mutableStateOf(0L)
    // 요약 화면 표시용 현재 시각 — 1분마다(앰비언트에선 onUpdateAmbient로) 갱신.
    private var clockNow by mutableStateOf(System.currentTimeMillis())

    private val ambientObserver by lazy {
        AmbientLifecycleObserver(
            this,
            object : AmbientLifecycleObserver.AmbientLifecycleCallback {
                override fun onEnterAmbient(
                    ambientDetails: AmbientLifecycleObserver.AmbientDetails
                ) {
                    ambient = true
                }

                override fun onExitAmbient() {
                    ambient = false
                }

                // 앰비언트 중엔 코루틴 타이머가 멈출 수 있어 시스템의 1분 갱신 신호로 시계를 맞춘다.
                override fun onUpdateAmbient() {
                    clockNow = System.currentTimeMillis()
                }
            },
        )
    }
    // 플립 애니메이션 여부 — 연타(짧은 간격)면 스냅(false), 단독 조작이면 플립(true).
    private var animateFlip by mutableStateOf(false)
    // 색상 그리드 피커가 열린 영역(null=닫힘, 0=좌, 1=우).
    private var pickerSide by mutableStateOf<Int?>(null)
    // 중앙 길게 누르기 메뉴(카운터 캡처 / 카운터 초기화 / 낚시 종료) + 초기화 확인 단계.
    private var menuOpen by mutableStateOf(false)
    private var confirmReset by mutableStateOf(false)
    // 메뉴에 '카운터 초기화'를 보일지(카운터=보임, 그래프=캡처만).
    private var menuAllowReset by mutableStateOf(true)
    // 짧은 안내 문구(저장·초기화 결과). 잠시 뒤 자동으로 사라짐.
    private var toast by mutableStateOf<String?>(null)
    // 낚시 종료: 카운터 화면 캡처 대기(캡처 이미지를 요약과 함께 폰에 보냄).
    private var endCapturePending by mutableStateOf(false)
    private val toastRunnable = Runnable { toast = null }
    // 즉시 전송용 연결 노드 캐시(매 탭마다 조회하지 않도록).
    private var cachedNodes: List<String> = emptyList()
    // 마지막 로컬 조작 시각 — 직후엔 폰 push로 숫자를 덮지 않아 깜빡임을 막는다.
    private var lastBumpAt = 0L
    // 권위값 적용 디바운스: 밀려오는 중간 push들을 흘리고 조용해진 뒤 최종값만 1회 반영.
    private val reconcileHandler = Handler(Looper.getMainLooper())
    private var pendingCounts: List<Int>? = null
    private val reconcileRunnable = Runnable { tryReconcile() }

    // 유사 AOD: 화면은 계속 켜두되(FLAG_KEEP_SCREEN_ON) 일정 시간 조작이 없으면 창
    // 밝기만 낮추고, 터치·카운트 동작 시 원래 밝기로 복귀(시스템 Ambient 미지원 대체).
    private val dimHandler = Handler(Looper.getMainLooper())
    private val dimRunnable = Runnable { dimmed = true; applyDim(true) }

    private val dataListener = DataClient.OnDataChangedListener { buffer ->
        for (event in buffer) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            when (event.dataItem.uri.path) {
                PATH_STATE -> applyData(DataMapItem.fromDataItem(event.dataItem).dataMap)
                PATH_CHART -> applyChart(DataMapItem.fromDataItem(event.dataItem).dataMap)
                PATH_SETTINGS -> applySettings(DataMapItem.fromDataItem(event.dataItem).dataMap)
            }
        }
        buffer.release()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 시작 시 검정 배경 + 48dp 원형 아이콘 스플래시(Wear 품질기준 WO-V15). super.onCreate 이전 호출.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        // 화면이 꺼져도 앱을 활성으로 유지(앰비언트) — 다시 켜면 카운터 화면이 그대로 유지된다.
        lifecycle.addObserver(ambientObserver)
        // 기본은 시스템 화면 시간 초과에 맡긴다(배터리 — 화면 켜둠은 시간당 약 30% 소모).
        // AOD가 켜져 있으면 앰비언트 요약 화면, 꺼져 있으면 화면이 꺼지고, 워치페이스로 돌아가도
        // '진행 중' 아이콘(Ongoing Activity)을 눌러 바로 돌아온다.
        // 폰 설정 '화면 항상 켜두기'를 켜면 화면을 켜두고 유휴 시 창 밝기만 낮추는 '유사 AOD'로 동작.
        prefs = getSharedPreferences("wear_counter", Context.MODE_PRIVATE)
        loadSettings()
        applyKeepOn()
        startOngoing()
        val startPage = prefs.getInt("start_page", 1).coerceIn(0, 2)
        setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    // 0=조과 그래프(왼쪽), 1=카운터(시작·가운데), 2=카메라(오른쪽).
                    val pagerState = rememberPagerState(initialPage = startPage, pageCount = { 3 })
                    val scope = rememberCoroutineScope()
                    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                        when (page) {
                            // 그래프 화면 길게 누르기 → 저장 메뉴(손가락에 가려 즉시 저장 결과가 안 보여 한 단계 둠).
                            0 -> Box(
                                Modifier.fillMaxSize().pointerInput(Unit) {
                                    detectTapGestures(onLongPress = {
                                        menuAllowReset = false
                                        confirmReset = false
                                        menuOpen = true
                                    })
                                },
                            ) {
                                ChartScreen(
                                    names = chartNames,
                                    hours = chartHours,
                                    tideMins = tideMins,
                                    tideLevels = tideLevels,
                                    colorIdx = colorIdx,
                                )
                            }
                            1 -> Box(Modifier.fillMaxSize()) {
                                CounterScreen(
                                    names = names,
                                    counts = counts,
                                    colorIdx = colorIdx,
                                    eco = ecoColors,
                                    animate = animateFlip,
                                    onPlus = { i -> bump(i, 1, PATH_ADD) },
                                    onMinus = { i -> bump(i, -1, PATH_REMOVE) },
                                    onStop = { sendStop() },
                                    onMenu = {
                                        menuAllowReset = true
                                        confirmReset = false
                                        menuOpen = true
                                    },
                                    onPickColor = { side -> pickerSide = side },
                                )
                                val side = pickerSide
                                if (side != null) {
                                    ColorPicker(
                                        current = colorIdx.getOrElse(side) { 0 },
                                        onRotary = { dir -> moveCursor(dir) },
                                        onPick = { idx ->
                                            previewColor(side, idx)
                                            persistColor(side)
                                            pickerSide = null
                                        },
                                        onDismiss = {
                                            persistColor(side)
                                            pickerSide = null
                                        },
                                    )
                                }
                            }
                            else -> CameraScreen(
                                launched = cameraLaunched,
                                onLaunch = { cameraLaunched = true; sendCameraOpen() },
                                onCancel = { scope.launch { pagerState.animateScrollToPage(1) } },
                                onShoot = { delaySec -> sendCameraShoot(delaySec) },
                                onFlip = { sendCameraFlip() },
                            )
                        }
                    }
                    PageDots(3, pagerState.currentPage, Modifier.align(Alignment.BottomCenter))
                    if (menuOpen) {
                        ActionMenu(
                            allowReset = menuAllowReset,
                            confirmReset = confirmReset,
                            onSave = { saveScreen() },
                            onAskReset = { confirmReset = true },
                            onEndFishing = { endFishing() },
                            onConfirmReset = { resetCounts() },
                            onDismiss = { menuOpen = false; confirmReset = false },
                        )
                    }
                    toast?.let { msg ->
                        Text(
                            msg,
                            color = Color.White,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .align(Alignment.Center)
                                .background(Color(0xE6000000), RoundedCornerShape(14.dp))
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                        )
                    }
                    // 앰비언트(화면 꺼짐): 밝은 UI 대신 저전력 AoD를 덮어 표시(앱은 유지).
                    if (ambient || dimmed) {
                        AmbientOverlay(
                            names = names,
                            counts = counts,
                            now = clockNow,
                            showClock = showClock,
                            lastCatchAt = if (showElapsed) lastCatchAt else 0L,
                        )
                        // 표시되는 동안 분이 바뀔 때마다 갱신(표시 시작 시 즉시 1회).
                        LaunchedEffect(Unit) {
                            while (true) {
                                clockNow = System.currentTimeMillis()
                                delay(60_000L - clockNow % 60_000L)
                            }
                        }
                    }
                    LaunchedEffect(endCapturePending) {
                        if (!endCapturePending) return@LaunchedEffect
                        wakeBright()
                        if (pagerState.currentPage != 1) pagerState.scrollToPage(1)
                        delay(350) // 메뉴가 사라진 카운터 화면이 그려질 때까지
                        endCapturePending = false
                        captureScreen(
                            path = PATH_FISHING_END,
                            okMsg = "조과 요약을 메모에 저장",
                            // 캡처 실패해도 요약(그래프)은 저장.
                            onFail = {
                                sendToPhone(PATH_FISHING_END)
                                showToast("조과 요약을 메모에 저장")
                            },
                        )
                    }
                    LaunchedEffect(pagerState) {
                        var prev = pagerState.currentPage
                        snapshotFlow { pagerState.currentPage }.collect { page ->
                            // 그래프 페이지로 넘어오면 폰에 최신 데이터 요청.
                            if (page == 0) requestChart()
                            // 카메라 페이지(2)에서 빠져나오면 폰 카메라 화면을 닫는다.
                            if (prev == 2 && page != 2) {
                                sendCameraClose()
                                cameraLaunched = false
                            }
                            prev = page
                        }
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        wakeBright() // 화면 밝게 + 유휴(어둡게) 타이머 시작
        dataClient.addListener(dataListener)
        // 연결 노드 캐시 갱신(전송 지연 축소) + 진입 시 폰에 최신 어종·조과 상태 요청.
        // (폰에서 어종을 바꾼 뒤 앱을 안 열어 캐시된 state가 낡았을 수 있으므로 한 번 당겨온다.)
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { ns ->
            cachedNodes = ns.map { it.id }
            for (id in cachedNodes) {
                messageClient.sendMessage(id, PATH_REQUEST, ByteArray(0))
                messageClient.sendMessage(id, PATH_CHART_REQUEST, ByteArray(0))
            }
        }
        // 진입 시 최신값 즉시 반영.
        dataClient.dataItems.addOnSuccessListener { items ->
            var phoneKnowsColors = false
            for (item in items) {
                when (item.uri.path) {
                    PATH_STATE -> applyData(DataMapItem.fromDataItem(item).dataMap)
                    PATH_CHART -> applyChart(DataMapItem.fromDataItem(item).dataMap)
                    PATH_SETTINGS -> {
                        val m = DataMapItem.fromDataItem(item).dataMap
                        phoneKnowsColors = m.containsKey("color_0")
                        applySettings(m)
                    }
                }
            }
            items.release()
            // 폰이 아직 색을 모르면 워치의 현재 색을 알려 폰 설정 화면과 맞춘다
            // (안 그러면 폰에서 다른 설정을 바꿀 때 워치 색이 기본값으로 덮인다).
            if (!phoneKnowsColors) { sendColor(0); sendColor(1) }
        }
    }

    override fun onPause() {
        super.onPause()
        dataClient.removeListener(dataListener)
        reconcileHandler.removeCallbacks(reconcileRunnable)
        dimHandler.removeCallbacks(dimRunnable)
    }

    // 모든 터치·키 입력에서 호출됨 — 밝기 복원 + 유휴 타이머 재시작.
    override fun onUserInteraction() {
        super.onUserInteraction()
        wakeBright()
    }

    /** 창 밝기를 낮추거나(어둡게) 기본값으로 되돌린다(창 단위라 시스템 설정은 불변). */
    private fun applyDim(dim: Boolean) {
        val target = when {
            dim -> dimLevel / 100f
            brightOn > 0 -> brightOn / 100f
            else -> WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        }
        val lp = window.attributes
        if (lp.screenBrightness != target) {
            lp.screenBrightness = target
            window.attributes = lp
        }
    }

    /** 밝기를 원래대로 복원하고 유휴 타이머를 재시작(dimIdleSec 후 다시 어둡게).
     *  화면 항상 켜두기가 꺼져 있거나 시간이 0이면 어둡게 하지 않는다(시스템 시간 초과에 맡김). */
    private fun wakeBright() {
        dimmed = false
        applyDim(false)
        dimHandler.removeCallbacks(dimRunnable)
        if (keepOn && dimIdleSec > 0) dimHandler.postDelayed(dimRunnable, dimIdleSec * 1000L)
    }

    /** prefs에서 워치 설정을 읽어 필드에 반영. */
    private fun loadSettings() {
        brightOn = prefs.getInt("bright_on", DEF_BRIGHT_ON).coerceIn(0, 100)
        dimLevel = prefs.getInt("dim_level", DEF_DIM_LEVEL).coerceIn(1, 100)
        dimIdleSec = prefs.getInt("dim_idle_sec", DEF_DIM_IDLE_SEC).coerceAtLeast(0)
        keepOn = prefs.getBoolean("keep_on", false)
        ecoColors = prefs.getBoolean("eco_colors", false)
        vibrate = prefs.getBoolean("vibrate", false)
        showClock = prefs.getBoolean("show_clock", true)
        showElapsed = prefs.getBoolean("show_elapsed", true)
        colorIdx = intArrayOf(prefs.getInt("color_0", 0), prefs.getInt("color_1", 4))
    }

    private fun applyKeepOn() {
        if (keepOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** 폰이 보낸 설정(/nakkda/settings)을 저장하고 즉시 적용. 없는 키는 기존값 유지. */
    private fun applySettings(map: DataMap) {
        val e = prefs.edit()
        for (k in listOf("bright_on", "dim_level", "dim_idle_sec", "start_page", "color_0", "color_1")) {
            if (map.containsKey(k)) e.putInt(k, map.getInt(k))
        }
        for (k in listOf("keep_on", "vibrate", "show_clock", "show_elapsed", "eco_colors")) {
            if (map.containsKey(k)) e.putBoolean(k, map.getBoolean(k))
        }
        e.apply()
        runOnUiThread {
            loadSettings()
            applyKeepOn()
            // 요약 화면(어둠/앰비언트) 중이면 깨우지 않고 그대로 설정만 반영.
            // 단, 바뀐 설정이 어둡게 하기를 끈 경우엔 어둠 상태를 유지할 수 없어 밝힌다.
            when {
                ambient -> {}
                dimmed && keepOn && dimIdleSec > 0 -> applyDim(true)
                else -> wakeBright()
            }
        }
    }

    /** 카운트 시 진동(설정 켜짐일 때만). +1은 짧게 한 번, −1은 두 번. */
    private fun vibrateCount(plus: Boolean) {
        if (!vibrate) return
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
        val effect = if (plus) {
            VibrationEffect.createOneShot(40, VibrationEffect.DEFAULT_AMPLITUDE)
        } else {
            VibrationEffect.createWaveform(longArrayOf(0, 40, 90, 40), -1)
        }
        try { v?.vibrate(effect) } catch (_: Exception) {}
    }

    /** 영역 색을 폰에 알려 폰 설정과 동기화. */
    private fun sendColor(side: Int) {
        val idx = colorIdx.getOrElse(side) { return }
        sendToPhone(PATH_SETTINGS_COLOR, "$side,$idx".toByteArray())
    }

    /** 메뉴를 닫고, 메뉴가 사라진 화면이 그려진 뒤 지금 화면을 캡처해 폰으로 보낸다. */
    private fun saveScreen() {
        menuOpen = false
        confirmReset = false
        dimHandler.postDelayed({ captureScreen() }, 300)
    }

    /** 지금 화면을 캡처해 path로 폰에 보낸다. 캡처 실패 시 onFail(기본: 실패 안내). */
    private fun captureScreen(
        path: String = PATH_SCREEN_SAVE,
        okMsg: String = "폰 갤러리·메모에 저장",
        onFail: () -> Unit = { showToast("저장 실패") },
    ) {
        val view = window.decorView
        if (view.width <= 0 || view.height <= 0) { onFail(); return }
        val bmp = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(window, bmp, { result ->
                if (result != PixelCopy.SUCCESS) {
                    onFail()
                    return@request
                }
                Thread { sendScreenToPhone(encodeScreen(bmp), path, okMsg) }.start()
            }, Handler(Looper.getMainLooper()))
        } catch (_: Exception) {
            onFail()
        }
    }

    /** 원형 워치면 화면과 같게 원 밖을 투명하게 잘라낸다(PNG 알파로 보존). */
    private fun toCircle(src: Bitmap): Bitmap {
        val size = minOf(src.width, src.height)
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, (size - src.width) / 2f, (size - src.height) / 2f, paint)
        return out
    }

    /** 메시지 한도(약 100KB) 안에 들도록 PNG, 크면 JPEG로 인코딩. */
    private fun encodeScreen(raw: Bitmap): ByteArray {
        val bmp = if (resources.configuration.isScreenRound) toCircle(raw) else raw
        val png = ByteArrayOutputStream().also {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
        }.toByteArray()
        if (png.size <= MAX_MESSAGE_BYTES) return png
        return ByteArrayOutputStream().also {
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, it)
        }.toByteArray()
    }

    private fun sendScreenToPhone(bytes: ByteArray, path: String, okMsg: String) {
        if (bytes.size > MAX_MESSAGE_BYTES) {
            runOnUiThread { showToast("저장 실패") }
            return
        }
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { ns ->
                if (ns.isEmpty()) {
                    showToast("폰 연결 안 됨")
                    return@addOnSuccessListener
                }
                cachedNodes = ns.map { it.id }
                for (n in ns) messageClient.sendMessage(n.id, path, bytes)
                showToast(okMsg)
            }
            .addOnFailureListener { showToast("폰 연결 안 됨") }
    }

    /** 오늘 조과 기록 전체 삭제 요청. 워치 숫자는 바로 0으로(폰 권위값이 곧 따라옴). */
    private fun resetCounts() {
        menuOpen = false
        confirmReset = false
        counts = counts.map { 0 }
        pendingCounts = null
        lastCatchAt = 0L
        lastBumpAt = SystemClock.elapsedRealtime()
        sendToPhone(PATH_COUNT_RESET)
        showToast("카운터 초기화")
    }

    /** 낚시 종료 → 폰이 오늘 메모에 조과 요약(수 + 그래프 이미지)을 기록. 조과 0이면 보내지 않음. */
    private fun endFishing() {
        menuOpen = false
        confirmReset = false
        if (counts.sum() <= 0) {
            showToast("조과 없음 · 요약 생략")
            return
        }
        // 카운터 화면으로 이동해 캡처한 뒤, 그 이미지를 담아 요약 요청(아래 LaunchedEffect).
        endCapturePending = true
    }

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) startOngoing()
        }

    /** 워치페이스에 '진행 중' 아이콘(Ongoing Activity) — 누르면 낚.다로 바로 복귀. 알림 권한 필요. */
    private fun startOngoing() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (!prefs.getBoolean("notif_asked", false)) {
                prefs.edit().putBoolean("notif_asked", true).apply()
                notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
            return
        }
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            nm.createNotificationChannel(
                NotificationChannel(CH_ONGOING, "낚시 중", NotificationManager.IMPORTANCE_LOW))
            val pi = PendingIntent.getActivity(
                this, 0,
                Intent(this, WearMainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val b = NotificationCompat.Builder(this, CH_ONGOING)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("낚.다")
                .setContentText("낚시 중")
                .setOngoing(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_WORKOUT)
                .setContentIntent(pi)
            OngoingActivity.Builder(applicationContext, ONGOING_ID, b)
                .setStaticIcon(R.mipmap.ic_launcher)
                .setTouchIntent(pi)
                .setStatus(Status.Builder().addTemplate("낚시 중").build())
                .build()
                .apply(applicationContext)
            nm.notify(ONGOING_ID, b.build())
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        // 앱을 완전히 닫을 때만 '진행 중' 아이콘 제거(화면 꺼짐·워치페이스 복귀는 유지).
        if (isFinishing) {
            try { getSystemService(NotificationManager::class.java)?.cancel(ONGOING_ID) } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    private fun showToast(msg: String) {
        toast = msg
        dimHandler.removeCallbacks(toastRunnable)
        dimHandler.postDelayed(toastRunnable, 1800)
    }

    private fun applyData(map: DataMap) {
        val n = map.getStringArrayList("names") ?: arrayListOf()
        val c = map.getIntegerArrayList("counts") ?: arrayListOf()
        // 구버전 폰은 키가 없음 → 0(경과 시간 숨김).
        val last = map.getLong("last_catch_at", 0L)
        runOnUiThread {
            names = n.toList()
            lastCatchAt = last
            // 권위값은 바로 덮지 않고 보류 → 조용해지면(디바운스) 최종값만 반영.
            pendingCounts = c.toList()
            scheduleReconcile()
        }
    }

    /** 폰이 push한 그래프 데이터(어종별 시간당 조과 + 조위 극값)를 반영. */
    private fun applyChart(map: DataMap) {
        val n = map.getStringArrayList("names") ?: arrayListOf()
        val hrs = ArrayList<IntArray>(n.size)
        for (i in n.indices) {
            val a = map.getIntegerArrayList("hours_$i") ?: arrayListOf()
            val arr = IntArray(24)
            for (h in 0 until minOf(24, a.size)) arr[h] = a[h]
            hrs.add(arr)
        }
        val tm = map.getIntegerArrayList("tide_min") ?: arrayListOf()
        val tl = map.getIntegerArrayList("tide_level") ?: arrayListOf()
        runOnUiThread {
            chartNames = n.toList()
            chartHours = hrs
            tideMins = tm.toList()
            tideLevels = tl.toList()
        }
    }

    /** 그래프 페이지 진입 시 폰에 최신 그래프 데이터 요청(캐시 노드로 즉시). */
    private fun requestChart() {
        val nodes = cachedNodes
        if (nodes.isNotEmpty()) {
            for (id in nodes) messageClient.sendMessage(id, PATH_CHART_REQUEST, ByteArray(0))
        } else {
            Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { ns ->
                cachedNodes = ns.map { it.id }
                for (n in ns) messageClient.sendMessage(n.id, PATH_CHART_REQUEST, ByteArray(0))
            }
        }
    }

    /** 조작·push가 멈춘 뒤 RECONCILE_MS 후에 최종 권위값을 반영(연타 중 중간값은 무시). */
    private fun scheduleReconcile() {
        reconcileHandler.removeCallbacks(reconcileRunnable)
        reconcileHandler.postDelayed(reconcileRunnable, RECONCILE_MS)
    }

    private fun tryReconcile() {
        val pending = pendingCounts ?: return
        val idle = SystemClock.elapsedRealtime() - lastBumpAt
        // 조작 직후면 반영 보류.
        if (idle < RECONCILE_MS) {
            reconcileHandler.postDelayed(reconcileRunnable, 200)
            return
        }
        // 이미 일치 → 할 일 없음(오르내림 없음).
        if (pending == counts) { pendingCounts = null; return }
        // 낙관적 값과 다름: 폰이 아직 따라오는 중일 수 있어 더 기다린다.
        // 단, 오래 지속되면(명령 유실 등) 그때만 한 번 보정.
        if (idle < MAX_RECONCILE_MS) {
            reconcileHandler.postDelayed(reconcileRunnable, 300)
            return
        }
        counts = pending
        pendingCounts = null
        wakeBright() // 폰/리모컨發 원격 카운트 변경 시 화면을 밝혀 알림
    }

    /** 낙관적 즉시 반영: 워치 숫자를 먼저 올리고(폰 왕복 대기 없음) 명령을 전송한다.
     *  폰의 권위값 push(applyData)가 오면 그 값으로 보정된다. */
    private fun bump(index: Int, delta: Int, path: String) {
        val now = SystemClock.elapsedRealtime()
        // 직전 조작과 간격이 짧으면(연타) 스냅, 넉넉하면 플립.
        animateFlip = (now - lastBumpAt) >= FLIP_GAP_MS
        lastBumpAt = now
        val c = counts.toMutableList()
        while (c.size <= index) c.add(0)
        c[index] = (c[index] + delta).coerceAtLeast(0)
        counts = c
        // bump 이전에 받아둔 권위값은 폐기 — 이걸 남겨두면 폰 push가 늦게 올 때
        // 오래된 값으로 되돌아간다(되돌아감 버그). 이후 새로 도착한 push만 신뢰한다.
        pendingCounts = null
        if (delta > 0) lastCatchAt = System.currentTimeMillis()
        vibrateCount(delta > 0)
        send(path, index)
        scheduleReconcile() // 조작 중엔 권위값 반영을 계속 뒤로 미룬다.
    }

    /** 어종 인덱스를 payload로 담아 폰에 카운트 명령 전송(캐시 노드로 즉시). */
    private fun send(path: String, speciesIndex: Int) {
        val payload = speciesIndex.toString().toByteArray()
        val nodes = cachedNodes
        if (nodes.isNotEmpty()) {
            for (id in nodes) messageClient.sendMessage(id, path, payload)
        } else {
            Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { ns ->
                cachedNodes = ns.map { it.id }
                for (n in ns) messageClient.sendMessage(n.id, path, payload)
            }
        }
    }

    private fun sendStop() {
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                messageClient.sendMessage(node.id, PATH_STOP, ByteArray(0))
            }
        }
    }

    /** 카메라 페이지에서 '실행' 확인 시 폰에 카메라(셀카) 열기를 요청. */
    private fun sendCameraOpen() = sendToPhone(PATH_CAMERA_OPEN)

    /** 카메라 페이지에서 빠져나올 때 폰 카메라 화면 닫기를 요청. */
    private fun sendCameraClose() = sendToPhone(PATH_CAMERA_CLOSE)

    /** 셔터: [delaySec]초 뒤 촬영(0이면 즉시). 폰이 카운트다운 후 촬영한다. */
    private fun sendCameraShoot(delaySec: Int) =
        sendToPhone(PATH_CAMERA_SHOOT, delaySec.toString().toByteArray())

    /** 전/후면 카메라 전환 요청. */
    private fun sendCameraFlip() = sendToPhone(PATH_CAMERA_FLIP)

    /** 연결된 노드로 메시지를 보낸다(캐시 노드 우선, 없으면 조회 후 전송). */
    private fun sendToPhone(path: String, payload: ByteArray = ByteArray(0)) {
        val nodes = cachedNodes
        if (nodes.isNotEmpty()) {
            for (id in nodes) messageClient.sendMessage(id, path, payload)
        } else {
            Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { ns ->
                cachedNodes = ns.map { it.id }
                for (n in ns) messageClient.sendMessage(n.id, path, payload)
            }
        }
    }

    /** 미리보기(상태만): 영역 색을 즉시 바꿔 배경·피커 커서에 반영. 저장은 닫을 때. */
    private fun previewColor(side: Int, idx: Int) {
        val arr = colorIdx.copyOf()
        if (side in arr.indices) {
            arr[side] = idx.coerceIn(0, PALETTE.size - 1)
            colorIdx = arr
        }
    }

    /** 베젤 회전: 피커가 열린 영역의 색 커서를 delta만큼 이동. */
    private fun moveCursor(delta: Int) {
        val side = pickerSide ?: return
        previewColor(side, colorIdx.getOrElse(side) { 0 } + delta)
    }

    /** 현재 영역 색을 prefs에 저장(피커 닫을 때 확정). */
    private fun persistColor(side: Int) {
        prefs.edit().putInt("color_$side", colorIdx.getOrElse(side) { 0 }).apply()
        sendColor(side)
    }

    companion object {
        private const val PATH_STATE = "/nakkda/count/state"
        private const val PATH_ADD = "/nakkda/count/add"
        private const val PATH_REMOVE = "/nakkda/count/remove"
        private const val PATH_STOP = "/nakkda/count/stop"
        private const val PATH_REQUEST = "/nakkda/count/request"
        private const val PATH_CHART = "/nakkda/chart/state"
        private const val PATH_CHART_REQUEST = "/nakkda/chart/request"
        private const val PATH_CAMERA_OPEN = "/nakkda/camera/open"
        private const val PATH_CAMERA_CLOSE = "/nakkda/camera/close"
        private const val PATH_CAMERA_SHOOT = "/nakkda/camera/shoot"
        private const val PATH_CAMERA_FLIP = "/nakkda/camera/flip"
        private const val PATH_SETTINGS = "/nakkda/settings"
        private const val PATH_SETTINGS_COLOR = "/nakkda/settings/color"
        private const val PATH_COUNT_RESET = "/nakkda/count/reset"
        private const val PATH_SCREEN_SAVE = "/nakkda/screen/save"
        private const val PATH_FISHING_END = "/nakkda/fishing/end"
        private const val CH_ONGOING = "nakkda_ongoing"
        private const val ONGOING_ID = 1001
        // Data Layer 메시지 크기 한도(100KB)보다 약간 작게.
        private const val MAX_MESSAGE_BYTES = 95_000
        // 조작·push가 멈춘 뒤 이 시간이 지나야 권위값 반영을 시도(디바운스).
        private const val RECONCILE_MS = 700L
        // 낙관적 값과 불일치가 이 시간 이상 지속되면(명령 유실 등) 한 번 강제 보정.
        private const val MAX_RECONCILE_MS = 2500L
        // 직전 조작과 간격이 이보다 짧으면 연타로 보고 플립을 생략(스냅).
        private const val FLIP_GAP_MS = 320L
        // 워치 설정 기본값(폰 WatchSettings와 동일). 유사 AOD: 조작이 없으면 이 시간 후 어둡게.
        private const val DEF_BRIGHT_ON = 0       // 0=시스템 밝기 따름
        private const val DEF_DIM_LEVEL = 10      // 어두울 때 밝기 10%
        private const val DEF_DIM_IDLE_SEC = 15
    }
}

/** 중앙 길게 누르기 메뉴. 초기화는 확인 단계를 한 번 더 거친다(되돌릴 수 없음). */
@Composable
private fun ActionMenu(
    allowReset: Boolean,
    confirmReset: Boolean,
    onSave: () -> Unit,
    onAskReset: () -> Unit,
    onEndFishing: () -> Unit,
    onConfirmReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.92f))
            // 버튼 밖(빈 곳)을 누르면 닫힘 — 아래 카운터·페이지로 터치가 새지 않게도 막는다.
            .pointerInput(Unit) { detectTapGestures { onDismiss() } },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!confirmReset) {
                // 원형 화면에서 가장 넓은 가운데에 2행만 둔다(닫기 버튼 대신 빈 곳 탭).
                // 1행: 캡처·초기화(카운터 화면), 그래프 화면에선 그래프 캡처만.
                if (allowReset) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        MenuButton("카운터\n캡처", Color(0xFF1E88E5), onSave, width = 76.dp, height = 52.dp)
                        MenuButton("카운터\n초기화", Color(0xFFC62828), onAskReset, width = 76.dp, height = 52.dp)
                    }
                } else {
                    MenuButton("그래프 캡처", Color(0xFF1E88E5), onSave, width = 120.dp, height = 40.dp)
                }
                // 2행: 낚시 종료.
                MenuButton("낚시 종료", Color(0xFF2E7D32), onEndFishing, width = 120.dp, height = 40.dp)
            } else {
                Text(
                    "오늘 조과 기록을\n모두 삭제할까요?",
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                )
                Text(
                    "되돌릴 수 없습니다",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 11.sp,
                )
                MenuButton("삭제", Color(0xFFC62828), onConfirmReset)
                MenuButton("취소", Color(0xFF455A64), onDismiss)
            }
        }
    }
}

@Composable
private fun MenuButton(
    label: String,
    color: Color,
    onClick: () -> Unit,
    width: Dp = 132.dp,
    height: Dp = 36.dp,
    fontSize: TextUnit = 14.sp,
) {
    Box(
        Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(20.dp))
            .background(color)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = Color.White,
            fontSize = fontSize,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            lineHeight = fontSize * 1.15f,
        )
    }
}

@Composable
private fun CounterScreen(
    names: List<String>,
    counts: List<Int>,
    colorIdx: IntArray,
    eco: Boolean,
    animate: Boolean,
    onPlus: (Int) -> Unit,
    onMinus: (Int) -> Unit,
    onStop: () -> Unit,
    onMenu: () -> Unit,
    onPickColor: (Int) -> Unit,
) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (names.isEmpty()) {
            Text(
                text = "카운터 세션\n대기 중",
                color = Color.White,
                textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center),
            )
            return@Box
        }
        val sides = if (names.size >= 2) 2 else 1
        Row(Modifier.fillMaxSize()) {
            CounterSide(
                modifier = Modifier.weight(1f).fillMaxHeight(),
                name = names[0],
                count = counts.getOrElse(0) { 0 },
                color = PALETTE[colorIdx.getOrElse(0) { 0 } % PALETTE.size],
                eco = eco,
                single = sides == 1,
                animate = animate,
                onPlus = { onPlus(0) },
                onMinus = { onMinus(0) },
                onPickColor = { onPickColor(0) },
            )
            if (sides >= 2) {
                CounterSide(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    name = names[1],
                    count = counts.getOrElse(1) { 0 },
                    color = PALETTE[colorIdx.getOrElse(1) { 1 } % PALETTE.size],
                    eco = eco,
                    single = false,
                    animate = animate,
                    onPlus = { onPlus(1) },
                    onMinus = { onMinus(1) },
                    onPickColor = { onPickColor(1) },
                )
            }
        }
        // 정중앙 원형 영역 → 탭=재생 중 미디어 중지, 길게=메뉴(카운터 캡처/초기화/낚시 종료).
        Box(
            Modifier.align(Alignment.Center).size(52.dp).clip(CircleShape).pointerInput(Unit) {
                detectTapGestures(onTap = { onStop() }, onLongPress = { onMenu() })
            },
        )
    }
}

@Composable
private fun CounterSide(
    modifier: Modifier,
    name: String,
    count: Int,
    color: Color,
    eco: Boolean,
    single: Boolean,
    animate: Boolean,
    onPlus: () -> Unit,
    onMinus: () -> Unit,
    onPickColor: () -> Unit,
) {
    // 숫자(이름+카운트) 블록의 하단 y(px). 이 지점까지는 +1, 그 아래만 −1.
    // 측정 전(NaN)에는 높이 절반을 임시 경계로 사용.
    var plusMaxY by remember { mutableStateOf(Float.NaN) }
    Box(
        modifier
            // 절전 색상이면 어종 색을 옅게 깔아(검정 위 22%) 구분만 유지하고 밝은 면적을 줄인다.
            .background(if (eco) color.copy(alpha = 0.22f) else color)
            // 탭: 위~숫자영역 하단=+1 / 숫자영역 아래=−1, 길게누름=색상 순환.
            .pointerInput(Unit) {
                detectTapGestures(
                    onLongPress = { onPickColor() },
                    onTap = { pos ->
                        val boundary = if (plusMaxY.isNaN()) size.height / 2f else plusMaxY
                        if (pos.y < boundary) onPlus() else onMinus()
                    },
                )
            }
            // 스와이프: 위로=+1 / 아래로=−1 (한 번에 1회).
            .pointerInput(Unit) {
                var dy = 0f
                val threshold = 24.dp.toPx()
                detectVerticalDragGestures(
                    onDragStart = { dy = 0f },
                    onVerticalDrag = { change, delta ->
                        dy += delta
                        change.consume()
                    },
                    onDragEnd = {
                        if (dy <= -threshold) onPlus()
                        else if (dy >= threshold) onMinus()
                    },
                )
            },
    ) {
        // 표시 오버레이(제스처 비소유 → 이벤트가 영역 Box로 전달됨).
        val hint = Color.White.copy(alpha = 0.55f)
        Text(
            "＋", color = hint, fontSize = 15.sp,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = if (single) 10.dp else 22.dp),
        )
        Text(
            "－", color = hint, fontSize = 18.sp,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = if (single) 10.dp else 22.dp),
        )
        Column(
            modifier = Modifier
                .align(Alignment.Center)
                // 숫자 블록의 실제 하단을 탭 경계로 전달(+ / − 분할점).
                .onGloballyPositioned { plusMaxY = it.boundsInParent().bottom },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = name,
                color = Color.White.copy(alpha = 0.9f),
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
            FlipCount(count, if (single) 56.sp.value else 42.sp.value, animate)
        }
    }
}

@OptIn(ExperimentalAnimationApi::class)
@Composable
private fun FlipCount(count: Int, fontSizeSp: Float, animate: Boolean) {
    AnimatedContent(
        targetState = count,
        transitionSpec = {
            when {
                // 연타 중엔 애니메이션 없이 즉시 전환(스냅).
                !animate -> EnterTransition.None togetherWith ExitTransition.None
                targetState > initialState ->
                    (slideInVertically { h -> h } + fadeIn()) togetherWith
                        (slideOutVertically { h -> -h } + fadeOut())
                else ->
                    (slideInVertically { h -> -h } + fadeIn()) togetherWith
                        (slideOutVertically { h -> h } + fadeOut())
            }
        },
        label = "flip",
    ) { c ->
        Text(
            text = "$c",
            color = Color.White,
            fontSize = fontSizeSp.sp,
            fontWeight = FontWeight.Black,
        )
    }
}

/** 16색 스와치 그리드 피커(4×4).
 *  - 손가락: 색칩 탭=적용+닫힘 / 바깥 탭=현재 커서색으로 확정+닫힘.
 *  - 베젤: 회전으로 커서(흰 테두리) 이동 + 배경 실시간 미리보기. */
@Composable
private fun ColorPicker(
    current: Int,
    onRotary: (Int) -> Unit,
    onPick: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }
    Box(
        Modifier
            .fillMaxSize()
            .onRotaryScrollEvent { e ->
                if (e.verticalScrollPixels != 0f) {
                    onRotary(if (e.verticalScrollPixels > 0) 1 else -1)
                }
                true
            }
            .focusRequester(focusRequester)
            .focusable()
            .background(Color.Black.copy(alpha = 0.78f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onDismiss() },
        contentAlignment = Alignment.Center,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            for (row in 0 until 4) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    for (col in 0 until 4) {
                        val idx = row * 4 + col
                        Box(
                            Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(PALETTE[idx])
                                .then(
                                    if (idx == current) {
                                        Modifier.border(3.dp, Color.White, CircleShape)
                                    } else {
                                        Modifier
                                    },
                                )
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { onPick(idx) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * 카메라 페이지 — 실수로 스와이프돼도 바로 실행되지 않도록 확인을 거친 뒤
 * 폰 카메라(셀카)를 연다. 이 페이지에서 빠져나가면(스와이프) 폰 카메라는 닫힌다.
 */
@Composable
private fun CameraScreen(
    launched: Boolean,
    onLaunch: () -> Unit,
    onCancel: () -> Unit,
    onShoot: (Int) -> Unit,
    onFlip: () -> Unit,
) {
    if (!launched) {
        Box(
            Modifier.fillMaxSize().background(Color.Black).padding(18.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("카메라 (셀카)", color = Color.White, fontSize = 15.sp,
                    fontWeight = FontWeight.Bold)
                Text("폰 카메라를 실행할까요?", color = Color.White.copy(alpha = 0.8f),
                    fontSize = 12.sp, textAlign = TextAlign.Center)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PillButton("취소", Color(0xFF37474F), onCancel)
                    PillButton("실행", Color(0xFF2E7D32), onLaunch)
                }
            }
        }
    } else {
        CameraControls(onShoot = onShoot, onFlip = onFlip)
    }
}

/** 폰 카메라 원격 조작 — 셔터(탭=즉시, 길게=누른 초만큼 타이머) + 상하 스와이프 전/후면 전환. */
@OptIn(ExperimentalAnimationApi::class)
@Composable
private fun CameraControls(onShoot: (Int) -> Unit, onFlip: () -> Unit) {
    val scope = rememberCoroutineScope()
    var heldSec by remember { mutableStateOf(0) }
    var pressing by remember { mutableStateOf(false) }
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            // 상하 스와이프: 전/후면 전환.
            .pointerInput(Unit) {
                var dy = 0f
                val threshold = 28.dp.toPx()
                detectVerticalDragGestures(
                    onDragStart = { dy = 0f },
                    onVerticalDrag = { change, delta -> dy += delta; change.consume() },
                    onDragEnd = { if (kotlin.math.abs(dy) >= threshold) onFlip() },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            // 셔터를 아래쪽에 붙인다(하단 여백은 페이지 점만 피할 정도).
            Modifier.fillMaxSize().padding(top = 18.dp, bottom = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            // 설명(위)
            Text(
                "탭=즉시 · 길게=타이머\n상하 스와이프=전/후면",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 10.sp,
                textAlign = TextAlign.Center,
            )
            // 셔터 버튼(아래)
            Box(
                Modifier
                    .size(77.dp) // 96dp에서 20% 축소
                    .clip(CircleShape)
                    .background(Color.White)
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onPress = {
                                pressing = true
                                val start = SystemClock.elapsedRealtime()
                                val job = scope.launch {
                                    while (true) {
                                        heldSec =
                                            ((SystemClock.elapsedRealtime() - start) / 1000).toInt()
                                        kotlinx.coroutines.delay(100)
                                    }
                                }
                                val released = tryAwaitRelease()
                                job.cancel()
                                val secs =
                                    ((SystemClock.elapsedRealtime() - start) / 1000).toInt()
                                pressing = false
                                heldSec = 0
                                if (released) onShoot(secs)
                            },
                        )
                    },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(59.dp).clip(CircleShape).background(Color(0xFFD32F2F)))
            }
        }
        // 길게 누르는 동안: 누적 초를 화면 가득 크게(애니메이션) 표시.
        if (pressing && heldSec > 0) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.82f)),
                contentAlignment = Alignment.Center,
            ) {
                AnimatedContent(
                    targetState = heldSec,
                    transitionSpec = {
                        (slideInVertically { h -> h / 2 } + fadeIn()) togetherWith
                            (slideOutVertically { h -> -h / 2 } + fadeOut())
                    },
                    label = "held",
                ) { s ->
                    Text(
                        "$s",
                        color = Color.White,
                        fontSize = 120.sp,
                        fontWeight = FontWeight.Black,
                    )
                }
            }
        }
    }
}

@Composable
private fun PillButton(label: String, color: Color, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(CircleShape)
            .background(color)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 18.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    }
}

/** '방금 / N분 전 / N시간 M분 전'. */
private fun elapsedText(now: Long, at: Long): String {
    val min = ((now - at).coerceAtLeast(0L) / 60_000L).toInt()
    return when {
        min < 1 -> "방금"
        min < 60 -> "${min}분 전"
        min % 60 == 0 -> "${min / 60}시간 전"
        else -> "${min / 60}시간 ${min % 60}분 전"
    }
}

/** 앰비언트(화면 꺼짐)·어둠 요약 화면 — 위 시계, 가운데 조과 수, 아래 마지막 조과 경과를 흐리게(저전력·번인 방지). */
@Composable
private fun AmbientOverlay(
    names: List<String>,
    counts: List<Int>,
    now: Long,
    showClock: Boolean,
    lastCatchAt: Long,
) {
    val context = LocalContext.current
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            // 어둠 상태의 첫 입력은 '깨우기'로만 소비(밑의 카운터 오증가 방지).
            .pointerInput(Unit) { detectTapGestures {} },
    ) {
        val dim = Color.White.copy(alpha = 0.6f)
        // 시계: 화면 최상단 중앙.
        if (showClock) {
            val pattern = if (android.text.format.DateFormat.is24HourFormat(context)) "HH:mm" else "h:mm"
            Text(
                SimpleDateFormat(pattern, Locale.getDefault()).format(Date(now)),
                color = dim,
                fontSize = 14.sp,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
            )
        }
        // 조과 수: 정중앙.
        if (names.isEmpty()) {
            Text("낚.다", color = dim, fontSize = 18.sp, modifier = Modifier.align(Alignment.Center))
        } else Row(
            Modifier.align(Alignment.Center),
            horizontalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            for (i in names.indices.take(2)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        names[i],
                        color = dim.copy(alpha = 0.45f),
                        fontSize = 12.sp,
                        maxLines = 1,
                    )
                    Text(
                        "${counts.getOrElse(i) { 0 }}",
                        color = dim,
                        fontSize = 40.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
        // 마지막 조과 경과: 아래쪽 중앙.
        if (lastCatchAt > 0L) {
            Text(
                elapsedText(now, lastCatchAt),
                color = dim.copy(alpha = 0.45f),
                fontSize = 12.sp,
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp),
            )
        }
    }
}

/** 하단 페이지 인디케이터(스와이프로 여러 페이지가 있음을 알림). */
@Composable
private fun PageDots(count: Int, current: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.padding(bottom = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (i in 0 until count) {
            Box(
                Modifier
                    .size(if (i == current) 6.dp else 5.dp)
                    .clip(CircleShape)
                    .background(
                        if (i == current) Color.White else Color.White.copy(alpha = 0.4f)),
            )
        }
    }
}

/**
 * 그래프 페이지 — 시간대별 조과(어종별 그룹 막대) 위에 조위(코사인 보간 S곡선)를 겹쳐 그린다.
 * 색은 카운터 좌/우 영역 색과 동일(어종 순서 일치)해 한눈에 대응된다.
 */
@Composable
private fun ChartScreen(
    names: List<String>,
    hours: List<IntArray>,
    tideMins: List<Int>,
    tideLevels: List<Int>,
    colorIdx: IntArray,
) {
    Box(
        Modifier.fillMaxSize().background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        if (names.isEmpty() || hours.isEmpty()) {
            Text(
                "그래프 대기 중\n(카운터 세션 필요)",
                color = Color.White,
                textAlign = TextAlign.Center,
                fontSize = 13.sp,
            )
            return@Box
        }
        val seriesColors = names.indices.map {
            PALETTE[(colorIdx.getOrElse(it) { it * 5 }) % PALETTE.size]
        }
        Column(
            Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("시간대별 조과", color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp)
            Spacer(Modifier.height(2.dp))
            Canvas(Modifier.fillMaxWidth().weight(1f)) {
                drawCatchTide(hours, tideMins, tideLevels, seriesColors)
            }
            Spacer(Modifier.height(2.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (i in names.indices) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(seriesColors[i]))
                        Spacer(Modifier.width(3.dp))
                        Text(
                            names[i],
                            color = Color.White.copy(alpha = 0.85f),
                            fontSize = 10.sp,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

/** 조위+시간당 조과 막대를 Canvas에 그린다(폰 CatchTideChart의 워치용 축소 포팅). */
private fun DrawScope.drawCatchTide(
    hours: List<IntArray>,
    tideMins: List<Int>,
    tideLevels: List<Int>,
    colors: List<Color>,
) {
    // 조위 점(분, cm) — 시간 순 정렬.
    val tide = ArrayList<Pair<Int, Int>>()
    for (i in tideMins.indices) if (i < tideLevels.size) tide.add(tideMins[i] to tideLevels[i])
    tide.sortBy { it.first }

    // x 범위: 조위 시각 + 조과가 있는 시(hour)들을 포함, 최소 3시간.
    val mins = ArrayList<Int>()
    for (p in tide) mins.add(p.first)
    for (arr in hours) for (h in 0..23) if (arr[h] > 0) { mins.add(h * 60); mins.add(h * 60 + 60) }
    var startMin: Int
    var endMin: Int
    if (mins.isEmpty()) {
        startMin = 300; endMin = 960
    } else {
        val lo = mins.minOrNull() ?: 0
        val hi = mins.maxOrNull() ?: 0
        startMin = (lo / 60) * 60
        endMin = ((hi + 59) / 60) * 60
        if (endMin - startMin < 180) endMin = startMin + 180
        startMin = startMin.coerceIn(0, 1440); endMin = endMin.coerceIn(0, 1440)
    }
    val span = endMin - startMin
    if (span <= 0) return

    val padL = 20f; val padR = 6f; val padT = 6f; val padB = 14f
    val plotW = size.width - padL - padR
    val plotH = size.height - padT - padB
    if (plotW <= 0 || plotH <= 0) return
    val base = padT + plotH
    fun xOf(minute: Int) = padL + plotW * (minute - startMin) / span

    val grid = Color.White.copy(alpha = 0.12f)
    val txt = Color.White.copy(alpha = 0.6f)
    val centerPaint = android.graphics.Paint().apply {
        color = txt.toArgb(); textSize = 9.sp.toPx(); isAntiAlias = true
        textAlign = android.graphics.Paint.Align.CENTER
    }
    val rightPaint = android.graphics.Paint().apply {
        color = txt.toArgb(); textSize = 9.sp.toPx(); isAntiAlias = true
        textAlign = android.graphics.Paint.Align.RIGHT
    }

    // 시간 그리드 + 3시간마다 라벨.
    var h = (startMin + 59) / 60
    while (h * 60 <= endMin) {
        val x = xOf(h * 60)
        drawLine(grid, Offset(x, padT), Offset(x, base), strokeWidth = 1f)
        if (h % 3 == 0) {
            drawContext.canvas.nativeCanvas.drawText("$h", x, size.height - 3f, centerPaint)
        }
        h++
    }

    // 어종별 그룹 막대.
    var maxCount = 1
    for (arr in hours) for (v in arr) if (v > maxCount) maxCount = v
    val n = hours.size
    if (n > 0) {
        var hh = startMin / 60
        while (hh * 60 < endMin) {
            val x0 = xOf(hh * 60); val x1 = xOf(hh * 60 + 60)
            val slotW = x1 - x0
            if (slotW > 2) {
                val sidePad = 2f
                val bw = (slotW - sidePad * 2) / n
                for (i in 0 until n) {
                    val cnt = hours[i].getOrElse(hh) { 0 }
                    if (cnt > 0) {
                        val left = x0 + sidePad + i * bw + 0.5f
                        val right = left + bw - 1f
                        if (right > left) {
                            val top = base - plotH * (cnt.toFloat() / maxCount)
                            drawRoundRect(
                                color = colors.getOrElse(i) { Color.Gray },
                                topLeft = Offset(left, top),
                                size = Size(right - left, base - top),
                                cornerRadius = CornerRadius(1.5f, 1.5f),
                            )
                        }
                    }
                }
            }
            hh++
        }
    }
    // y축 0 / 최대 마리수.
    drawContext.canvas.nativeCanvas.drawText("0", padL - 3f, base, rightPaint)
    drawContext.canvas.nativeCanvas.drawText("$maxCount", padL - 3f, padT + 8f, rightPaint)

    // 조위 곡선 + 꼭지점 cm 라벨.
    if (tide.size >= 2) {
        var minL = tide[0].second; var maxL = tide[0].second
        for (p in tide) {
            if (p.second < minL) minL = p.second
            if (p.second > maxL) maxL = p.second
        }
        if (maxL == minL) maxL = minL + 1
        fun levelAt(minute: Int): Float {
            if (minute <= tide.first().first) return tide.first().second.toFloat()
            if (minute >= tide.last().first) return tide.last().second.toFloat()
            for (i in 0 until tide.size - 1) {
                val a = tide[i]; val b = tide[i + 1]
                if (minute >= a.first && minute <= b.first) {
                    val f = (minute - a.first).toFloat() / (b.first - a.first)
                    val c = ((1 - cos(Math.PI * f)) / 2).toFloat()
                    return a.second + (b.second - a.second) * c
                }
            }
            return tide.last().second.toFloat()
        }
        fun yOf(lv: Float) = padT + plotH * (1 - (lv - minL) / (maxL - minL))
        val tideColor = Color(0xFF4FC3F7)
        val line = Path(); val fill = Path(); var started = false
        var x = 0f
        while (x <= plotW) {
            val minute = (startMin + span * (x / plotW)).toInt()
            val y = yOf(levelAt(minute))
            val px = padL + x
            if (!started) {
                line.moveTo(px, y); fill.moveTo(px, base); fill.lineTo(px, y); started = true
            } else {
                line.lineTo(px, y); fill.lineTo(px, y)
            }
            x += 2f
        }
        fill.lineTo(padL + plotW, base); fill.close()
        drawPath(fill, tideColor.copy(alpha = 0.16f))
        drawPath(line, tideColor.copy(alpha = 0.8f), style = Stroke(width = 2f))
        for (p in tide) {
            if (p.first < startMin || p.first > endMin) continue
            val cx = xOf(p.first); val cy = yOf(p.second.toFloat())
            drawCircle(tideColor, radius = 2.5f, center = Offset(cx, cy))
            drawContext.canvas.nativeCanvas.drawText(
                "${p.second}", cx, (cy - 5f).coerceAtLeast(8f), centerPaint)
        }
    }
}
