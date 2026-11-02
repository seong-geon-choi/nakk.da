package com.sgchoisg.nakkda

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
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

/** 좌/우 영역 배경색 팔레트(길게 눌러 순환). */
private val PALETTE = listOf(
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFC62828),
    Color(0xFF6A1B9A), Color(0xFFEF6C00), Color(0xFF00838F),
    Color(0xFF37474F),
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
    private var colorIdx by mutableStateOf(intArrayOf(0, 1))
    // 즉시 전송용 연결 노드 캐시(매 탭마다 조회하지 않도록).
    private var cachedNodes: List<String> = emptyList()
    // 마지막 로컬 조작 시각 — 직후엔 폰 push로 숫자를 덮지 않아 깜빡임을 막는다.
    private var lastBumpAt = 0L

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
        colorIdx = intArrayOf(prefs.getInt("color_0", 0), prefs.getInt("color_1", 1))
        setContent {
            MaterialTheme {
                CounterScreen(
                    names = names,
                    counts = counts,
                    colorIdx = colorIdx,
                    onPlus = { i -> bump(i, 1, PATH_ADD) },
                    onMinus = { i -> bump(i, -1, PATH_REMOVE) },
                    onStop = { sendStop() },
                    onCycleColor = { side -> cycleColor(side) },
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        dataClient.addListener(dataListener)
        // 연결 노드 캐시 갱신(전송 지연 축소).
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { ns ->
            cachedNodes = ns.map { it.id }
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
    }

    private fun applyData(map: DataMap) {
        val n = map.getStringArrayList("names") ?: arrayListOf()
        val c = map.getIntegerArrayList("counts") ?: arrayListOf()
        runOnUiThread {
            names = n.toList()
            // 최근 로컬 조작 직후엔 낙관적 값을 유지(왕복 중 옛 push로 인한 깜빡임 방지).
            if (SystemClock.elapsedRealtime() - lastBumpAt > RECONCILE_MS) {
                counts = c.toList()
            }
        }
    }

    /** 낙관적 즉시 반영: 워치 숫자를 먼저 올리고(폰 왕복 대기 없음) 명령을 전송한다.
     *  폰의 권위값 push(applyData)가 오면 그 값으로 보정된다. */
    private fun bump(index: Int, delta: Int, path: String) {
        lastBumpAt = SystemClock.elapsedRealtime()
        val c = counts.toMutableList()
        while (c.size <= index) c.add(0)
        c[index] = (c[index] + delta).coerceAtLeast(0)
        counts = c
        send(path, index)
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

    private fun cycleColor(side: Int) {
        val arr = colorIdx.copyOf()
        arr[side] = (arr[side] + 1) % PALETTE.size
        colorIdx = arr
        prefs.edit().putInt("color_$side", arr[side]).apply()
    }

    companion object {
        private const val PATH_STATE = "/nakkda/count/state"
        private const val PATH_ADD = "/nakkda/count/add"
        private const val PATH_REMOVE = "/nakkda/count/remove"
        private const val PATH_STOP = "/nakkda/count/stop"
        // 로컬 조작 후 이 시간 동안은 폰 push로 숫자를 덮지 않는다(보정 지연).
        private const val RECONCILE_MS = 1000L
    }
}

@Composable
private fun CounterScreen(
    names: List<String>,
    counts: List<Int>,
    colorIdx: IntArray,
    onPlus: (Int) -> Unit,
    onMinus: (Int) -> Unit,
    onStop: () -> Unit,
    onCycleColor: (Int) -> Unit,
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
                onPlus = { onPlus(0) },
                onMinus = { onMinus(0) },
                onCycleColor = { onCycleColor(0) },
            )
            if (sides >= 2) {
                CounterSide(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    name = names[1],
                    count = counts.getOrElse(1) { 0 },
                    color = PALETTE[colorIdx.getOrElse(1) { 1 } % PALETTE.size],
                    single = false,
                    onPlus = { onPlus(1) },
                    onMinus = { onMinus(1) },
                    onCycleColor = { onCycleColor(1) },
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
    onPlus: () -> Unit,
    onMinus: () -> Unit,
    onCycleColor: () -> Unit,
) {
    Box(
        modifier
            .background(color)
            // 탭: 위 절반=+1 / 아래 절반=−1, 길게누름=색상 순환.
            .pointerInput(Unit) {
                detectTapGestures(
                    onLongPress = { onCycleColor() },
                    onTap = { pos -> if (pos.y < size.height / 2f) onPlus() else onMinus() },
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
            modifier = Modifier.align(Alignment.Center),
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
            FlipCount(count, if (single) 56.sp.value else 42.sp.value)
        }
    }
}

@OptIn(ExperimentalAnimationApi::class)
@Composable
private fun FlipCount(count: Int, fontSizeSp: Float) {
    AnimatedContent(
        targetState = count,
        transitionSpec = {
            if (targetState > initialState) {
                (slideInVertically { h -> h } + fadeIn()) togetherWith
                    (slideOutVertically { h -> -h } + fadeOut())
            } else {
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
