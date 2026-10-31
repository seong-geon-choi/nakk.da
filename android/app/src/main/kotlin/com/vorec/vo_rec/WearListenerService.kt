package com.sgchoisg.nakkda

import android.content.Intent
import android.os.Build
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/**
 * 워치로부터 Data Layer 메시지를 수신해 조과 카운트에 반영한다
 * (폰 UI가 떠 있지 않아도 Data Layer가 이 서비스를 깨운다).
 * BT 리모컨과 동일하게 "실행 중인 카운터 세션"에만 반영한다(세션 미실행 시 무시).
 */
class WearListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            PATH_COUNT_ADD -> forward(CatchLogService.ACTION_ADD)
            PATH_COUNT_REMOVE -> forward(CatchLogService.ACTION_REMOVE_LAST)
        }
    }

    private fun forward(action: String) {
        // 세션 미실행이면 무시(리모컨과 동일 의미). 활성 중엔 서비스가 포그라운드로 떠 있어
        // startForegroundService가 기존 인스턴스에 onStartCommand로 명령을 전달한다.
        val active = CatchLogService.prefsOf(this)
            .getBoolean(CatchLogService.PREFS_ACTIVE_KEY, false)
        if (!active) return
        val intent = Intent(this, CatchLogService::class.java).apply {
            this.action = action
            if (action == CatchLogService.ACTION_ADD) {
                // 워치 +1은 기본(첫 번째) 어종에 기록. 어종 선택은 향후 고도화.
                putExtra(CatchLogService.EXTRA_SPECIES_INDEX, 0)
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            // 세션이 막 종료되어 포그라운드 시작이 제한되는 드문 경우는 무시한다.
        }
    }

    companion object {
        private const val PATH_COUNT_ADD = "/nakkda/count/add"
        private const val PATH_COUNT_REMOVE = "/nakkda/count/remove"
    }
}
