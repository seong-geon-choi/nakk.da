package com.sgchoisg.nakkda

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
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
import kotlinx.coroutines.launch
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
            },
        )
    }
    // 플립 애니메이션 여부 — 연타(짧은 간격)면 스냅(false), 단독 조작이면 플립(true).
    private var animateFlip by mutableStateOf(false)
    // 색상 그리드 피커가 열린 영역(null=닫힘, 0=좌, 1=우).
    private var pickerSide by mutableStateOf<Int?>(null)
    // 즉시 전송용 연결 노드 캐시(매 탭마다 조회하지 않도록).
    private var cachedNodes: List<String> = emptyList()
    // 마지막 로컬 조작 시각 — 직후엔 폰 push로 숫자를 덮지 않아 깜빡임을 막는다.
    private var lastBumpAt = 0L
    // 권위값 적용 디바운스: 밀려오는 중간 push들을 흘리고 조용해진 뒤 최종값만 1회 반영.
    private val reconcileHandler = Handler(Looper.getMainLooper())
    private var pendingCounts: List<Int>? = null
    private val reconcileRunnable = Runnable { tryReconcile() }

    private val dataListener = DataClient.OnDataChangedListener { buffer ->
        for (event in buffer) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            when (event.dataItem.uri.path) {
                PATH_STATE -> applyData(DataMapItem.fromDataItem(event.dataItem).dataMap)
                PATH_CHART -> applyChart(DataMapItem.fromDataItem(event.dataItem).dataMap)
            }
        }
        buffer.release()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 화면이 꺼져도 앱을 활성으로 유지(앰비언트) — 다시 켜면 카운터 화면이 그대로 유지된다.
        lifecycle.addObserver(ambientObserver)
        prefs = getSharedPreferences("wear_counter", Context.MODE_PRIVATE)
        colorIdx = intArrayOf(prefs.getInt("color_0", 0), prefs.getInt("color_1", 4))
        setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    // 0=조과 그래프(왼쪽), 1=카운터(시작·가운데), 2=카메라(오른쪽).
                    val pagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })
                    val scope = rememberCoroutineScope()
                    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                        when (page) {
                            0 -> ChartScreen(
                                names = chartNames,
                                hours = chartHours,
                                tideMins = tideMins,
                                tideLevels = tideLevels,
                                colorIdx = colorIdx,
                            )
                            1 -> Box(Modifier.fillMaxSize()) {
                                CounterScreen(
                                    names = names,
                                    counts = counts,
                                    colorIdx = colorIdx,
                                    animate = animateFlip,
                                    onPlus = { i -> bump(i, 1, PATH_ADD) },
                                    onMinus = { i -> bump(i, -1, PATH_REMOVE) },
                                    onStop = { sendStop() },
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
                    // 앰비언트(화면 꺼짐): 밝은 UI 대신 저전력 AoD를 덮어 표시(앱은 유지).
                    if (ambient) {
                        AmbientOverlay(names = names, counts = counts)
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
            for (item in items) {
                when (item.uri.path) {
                    PATH_STATE -> applyData(DataMapItem.fromDataItem(item).dataMap)
                    PATH_CHART -> applyChart(DataMapItem.fromDataItem(item).dataMap)
                }
            }
            items.release()
        }
    }

    override fun onPause() {
        super.onPause()
        dataClient.removeListener(dataListener)
        reconcileHandler.removeCallbacks(reconcileRunnable)
    }

    private fun applyData(map: DataMap) {
        val n = map.getStringArrayList("names") ?: arrayListOf()
        val c = map.getIntegerArrayList("counts") ?: arrayListOf()
        runOnUiThread {
            names = n.toList()
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
        // 조작·push가 멈춘 뒤 이 시간이 지나야 권위값 반영을 시도(디바운스).
        private const val RECONCILE_MS = 700L
        // 낙관적 값과 불일치가 이 시간 이상 지속되면(명령 유실 등) 한 번 강제 보정.
        private const val MAX_RECONCILE_MS = 2500L
        // 직전 조작과 간격이 이보다 짧으면 연타로 보고 플립을 생략(스냅).
        private const val FLIP_GAP_MS = 320L
    }
}

@Composable
private fun CounterScreen(
    names: List<String>,
    counts: List<Int>,
    colorIdx: IntArray,
    animate: Boolean,
    onPlus: (Int) -> Unit,
    onMinus: (Int) -> Unit,
    onStop: () -> Unit,
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
                    single = false,
                    animate = animate,
                    onPlus = { onPlus(1) },
                    onMinus = { onMinus(1) },
                    onPickColor = { onPickColor(1) },
                )
            }
        }
        // 정중앙 원형 영역 → 재생 중 미디어 중지(좌/우 탭 위에 오버레이).
        Box(
            Modifier.align(Alignment.Center).size(52.dp).clip(CircleShape).clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onStop() },
        )
    }
}

@Composable
private fun CounterSide(
    modifier: Modifier,
    name: String,
    count: Int,
    color: Color,
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
            .background(color)
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
            Modifier.fillMaxSize().padding(vertical = 18.dp),
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
                    .size(96.dp)
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
                Box(Modifier.size(74.dp).clip(CircleShape).background(Color(0xFFD32F2F)))
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

/** 앰비언트(화면 꺼짐) AoD — 검은 배경에 어종별 조과 수만 흐리게 표시(저전력·번인 방지). */
@Composable
private fun AmbientOverlay(names: List<String>, counts: List<Int>) {
    Box(
        Modifier.fillMaxSize().background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        val dim = Color.White.copy(alpha = 0.6f)
        if (names.isEmpty()) {
            Text("낚.다", color = dim, fontSize = 18.sp)
            return@Box
        }
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
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
