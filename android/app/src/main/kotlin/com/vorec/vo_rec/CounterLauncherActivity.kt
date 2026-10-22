package com.sgchoisg.nakkda

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * 홈화면 고정 바로가기가 실행하는 트램펄린(화면 없음).
 * 저장된 어종으로 조과 세션(알림)을 시작하고 잠금화면 카운터 화면을 바로 띄운 뒤 종료한다.
 * 메모화면 '카운터' 버튼의 네이티브 동작과 동일한 결과.
 */
class CounterLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 이전에 앱에서 동기화해 둔 어종 목록(prefs)으로 세션 시작 → 알림 표시.
        val speciesJson = CatchLogService.prefsOf(this)
            .getString(CatchLogService.PREFS_SPECIES_KEY, "[]") ?: "[]"
        try {
            CatchLogService.start(this, speciesJson)
        } catch (_: Exception) {}
        try {
            startActivity(
                Intent(this, CatchCounterActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {}
        finish()
    }
}
