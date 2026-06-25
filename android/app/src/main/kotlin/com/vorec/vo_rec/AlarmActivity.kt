package com.sgchoisg.nakkda

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 출퇴근 도착 알람 전체화면 UI(잠금화면 위 표시).
 * 알람음/진동은 CommuteAlarmService가 재생하며, 여기선 "끄기"로 즉시 중지만 한다.
 */
class AlarmActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager)
                .requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContentView(buildView())

        // 서비스 알람이 1분 후 자동 중지되므로 화면도 동일하게 자동 종료
        handler.postDelayed({ dismiss() }, 60000L)
    }

    private fun buildView(): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0D47A1"))
            setPadding(48, 48, 48, 48)
        }
        val title = TextView(this).apply {
            text = "🚇 목적지 접근"
            setTextColor(Color.WHITE)
            textSize = 30f
            gravity = Gravity.CENTER
        }
        val msg = TextView(this).apply {
            text = "설정한 지점 반경에 들어왔습니다.\n내릴 준비를 하세요!"
            setTextColor(Color.parseColor("#E0E0E0"))
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 64)
        }
        val stopBtn = Button(this).apply {
            text = "끄기"
            textSize = 20f
            setOnClickListener { dismiss() }
        }
        root.addView(title)
        root.addView(msg)
        root.addView(
            stopBtn,
            LinearLayout.LayoutParams(700, 160).apply { gravity = Gravity.CENTER }
        )
        return root
    }

    /** 알람 중지를 서비스에 알리고 화면 종료 */
    private fun dismiss() {
        handler.removeCallbacksAndMessages(null)
        try {
            startService(
                Intent(this, CommuteAlarmService::class.java)
                    .apply { action = CommuteAlarmService.ACTION_STOP_ALARM }
            )
        } catch (_: Exception) {}
        finish()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
