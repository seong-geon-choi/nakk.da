package com.sgchoisg.nakkda

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
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
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == PATH_STATE) {
                applyData(DataMapItem.fromDataItem(event.dataItem).dataMap)
            }
        }
        buffer.release()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = getSharedPreferences("wear_counter", Context.MODE_PRIVATE)
        colorIdx = intArrayOf(prefs.getInt("color_0", 0), prefs.getInt("color_1", 4))
        setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize()) {
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
            for (id in cachedNodes) messageClient.sendMessage(id, PATH_REQUEST, ByteArray(0))
        }
        // 진입 시 최신값 즉시 반영.
        dataClient.dataItems.addOnSuccessListener { items ->
            for (item in items) {
                if (item.uri.path == PATH_STATE) {
                    applyData(DataMapItem.fromDataItem(item).dataMap)
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
        if (pending == counts) return
        // 낙관적 값과 다름: 폰이 아직 따라오는 중일 수 있어 더 기다린다.
        // 단, 오래 지속되면(명령 유실 등) 그때만 한 번 보정.
        if (idle < MAX_RECONCILE_MS) {
            reconcileHandler.postDelayed(reconcileRunnable, 300)
            return
        }
        counts = pending
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
