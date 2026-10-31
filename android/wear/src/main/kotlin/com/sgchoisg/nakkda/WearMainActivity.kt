package com.sgchoisg.nakkda

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable

/**
 * 조과 카운터 워치 리모컨 + 표시기.
 * - +1 / −1 버튼: 폰으로 카운트 명령 전송(/nakkda/count/add, /remove).
 * - 현재 총 조과 수: 폰이 /nakkda/count/state 로 push → 실시간 표시.
 */
class WearMainActivity : ComponentActivity() {

    private val messageClient by lazy { Wearable.getMessageClient(this) }
    private val dataClient by lazy { Wearable.getDataClient(this) }

    private var count by mutableStateOf<Int?>(null)
    private var status by mutableStateOf("")

    private val dataListener = DataClient.OnDataChangedListener { buffer ->
        for (event in buffer) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == PATH_COUNT_STATE) {
                val total = DataMapItem.fromDataItem(event.dataItem).dataMap.getInt("total")
                runOnUiThread { count = total }
            }
        }
        buffer.release()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                CounterScreen(
                    count = count,
                    status = status,
                    onAdd = { send(PATH_COUNT_ADD, "+1") },
                    onRemove = { send(PATH_COUNT_REMOVE, "−1") },
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        dataClient.addListener(dataListener)
        // 리스너는 변경분만 받으므로, 최신 아이템을 한 번 조회해 현재 값을 즉시 반영.
        dataClient.dataItems.addOnSuccessListener { items ->
            for (item in items) {
                if (item.uri.path == PATH_COUNT_STATE) {
                    count = DataMapItem.fromDataItem(item).dataMap.getInt("total")
                }
            }
            items.release()
        }
    }

    override fun onPause() {
        super.onPause()
        dataClient.removeListener(dataListener)
    }

    /** 연결된 폰 노드로 카운트 명령 전송(빈 페이로드). */
    private fun send(path: String, label: String) {
        status = "전송 중…"
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    status = "폰 연결 안됨"
                    return@addOnSuccessListener
                }
                for (node in nodes) {
                    messageClient.sendMessage(node.id, path, ByteArray(0))
                }
                status = "$label 전송"
            }
            .addOnFailureListener { status = "전송 실패" }
    }

    companion object {
        private const val PATH_COUNT_ADD = "/nakkda/count/add"
        private const val PATH_COUNT_REMOVE = "/nakkda/count/remove"
        private const val PATH_COUNT_STATE = "/nakkda/count/state"
    }
}

@Composable
private fun CounterScreen(count: Int?, status: String, onAdd: () -> Unit, onRemove: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = count?.toString() ?: "—",
            style = MaterialTheme.typography.display1,
        )
        Spacer(Modifier.height(10.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            Button(onClick = onRemove) { Text("−1") }
            Spacer(Modifier.width(12.dp))
            Button(onClick = onAdd) { Text("+1") }
        }
        if (status.isNotEmpty()) {
            Text(
                text = status,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}
