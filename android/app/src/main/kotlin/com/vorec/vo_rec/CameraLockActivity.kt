package com.sgchoisg.nakkda

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

    override fun getDartEntrypointFunctionName(): String = "cameraLockMain"

    override fun onCreate(savedInstanceState: Bundle?) {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 촬영/취소 완료 시 Dart가 액티비티를 닫도록 하는 채널.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nakkda/cameraLock")
            .setMethodCallHandler { call, result ->
                if (call.method == "finish") {
                    runOnUiThread { finish() }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
