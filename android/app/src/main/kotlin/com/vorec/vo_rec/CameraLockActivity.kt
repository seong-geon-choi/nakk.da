package com.sgchoisg.nakkda

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 흔들기 → 카메라 전용 액티비티. 잠금화면 위에 카메라만 노출한다.
 *
 * 앱 전체(MainActivity)를 잠금화면 위에 띄우면 모든 메모/사진이 잠금 해제 없이
 * 노출되므로, 카메라 화면만 렌더하는 별도 Dart 진입점(`cameraLockMain`)을 실행하는
 * 독립 액티비티로 격리한다. 최근앱에서도 제외(excludeFromRecents, 매니페스트).
 *
 * 잠금화면 위 표시는 AlarmActivity와 동일한 패턴을 쓴다:
 * setShowWhenLocked + setTurnScreenOn + requestDismissKeyguard.
 * (보안 잠금은 해제되지 않으며, 잠금화면 '위'에서 촬영만 가능하다.)
 */
class CameraLockActivity : FlutterActivity() {

    private var methodChannel: MethodChannel? = null

    // 워치 카메라 조작 브로드캐스트 수신기 — 닫기/셔터/전후면 전환을 Dart로 전달.
    private val cameraReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                WearListenerService.ACTION_CLOSE_CAMERA -> finish()
                WearListenerService.ACTION_CAMERA_SHOOT -> {
                    val delay = intent.getIntExtra("delay", 0)
                    runOnUiThread {
                        methodChannel?.invokeMethod("remoteShoot", mapOf("delay" to delay))
                    }
                }
                WearListenerService.ACTION_CAMERA_FLIP ->
                    runOnUiThread { methodChannel?.invokeMethod("remoteFlip", null) }
            }
        }
    }

    override fun getDartEntrypointFunctionName(): String = "cameraLockMain"

    /** 셀카(전면) 모드로 열지 여부를 Dart 진입점 인자로 전달(워치 호출 시 "selfie"). */
    override fun getDartEntrypointArgs(): List<String> =
        if (intent?.getBooleanExtra("selfie", false) == true) listOf("selfie") else emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        // 워치 카메라 조작(닫기/셔터/전후면) 수신.
        val filter = IntentFilter().apply {
            addAction(WearListenerService.ACTION_CLOSE_CAMERA)
            addAction(WearListenerService.ACTION_CAMERA_SHOOT)
            addAction(WearListenerService.ACTION_CAMERA_FLIP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(cameraReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(cameraReceiver, filter)
        }
        // 잠금화면 '위'에 카메라만 표시(보안 잠금은 해제하지 않음). requestDismissKeyguard는
        // 보안 잠금에서 PIN/지문 인증창을 카메라 위로 띄워 "잠금화면 뒤로 실행"처럼 보이므로
        // 쓰지 않는다. setShowWhenLocked만으로 기본 카메라처럼 잠금 위 촬영이 가능하다.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        try { unregisterReceiver(cameraReceiver) } catch (_: Exception) {}
        methodChannel = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart↔네이티브 채널: Dart→네이티브 "finish"(촬영/취소 완료 시 닫기),
        // 네이티브→Dart "remoteShoot"/"remoteFlip"(워치 셔터/전환) 전달용.
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nakkda/cameraLock")
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "finish" -> {
                            runOnUiThread { finish() }
                            result.success(null)
                        }
                        "openCounter" -> {
                            runOnUiThread { openCounterAndFinish() }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    /** 카메라를 닫고 조과 카운터 화면을 연다(세션 시작). 이미 떠 있으면 재사용. */
    private fun openCounterAndFinish() {
        val speciesJson = CatchLogService.prefsOf(this)
            .getString(CatchLogService.PREFS_SPECIES_KEY, "[]") ?: "[]"
        try { CatchLogService.start(this, speciesJson) } catch (_: Exception) {}
        try {
            startActivity(
                Intent(this, CatchCounterActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP))
        } catch (_: Exception) {}
        finish()
    }
}
