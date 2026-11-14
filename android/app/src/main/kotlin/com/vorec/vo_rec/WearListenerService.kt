package com.sgchoisg.nakkda

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import androidx.core.app.NotificationCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/**
 * 워치로부터 Data Layer 메시지를 수신해 조과 카운트/효과음에 반영한다
 * (폰 UI가 떠 있지 않아도 Data Layer가 이 서비스를 깨운다).
 * - /nakkda/count/add,   payload=어종 인덱스 → 해당 어종 +1
 * - /nakkda/count/remove, payload=어종 인덱스 → 해당 어종 −1
 * - /nakkda/count/stop                        → 재생 중인 추임새/TTS 중지
 * - /nakkda/count/request                      → 현재 어종·조과 상태를 워치로 즉시 push
 * - /nakkda/chart/request                      → 그래프(시간당 조과+조위) 데이터를 워치로 push
 * - /nakkda/settings/color, payload="side,idx"  → 워치에서 바꾼 카운터 색을 폰 설정에 반영
 * - /nakkda/count/reset                        → 오늘 조과 기록 전체 삭제(워치 '기록 초기화')
 * - /nakkda/screen/save, payload=이미지 바이트   → 워치 화면을 갤러리에 저장 + 오늘 메모에 첨부
 * - /nakkda/fishing/end, payload=카운터 캡처   → 오늘 메모에 카운터 화면 + 조과 요약(수 + 그래프 이미지) 기록
 *
 * 세션이 실행 중이면 포그라운드 서비스(알림/TTS/위치)에 명령을 전달한다. 세션이 없으면
 * 포그라운드 서비스를 백그라운드에서 시작할 수 없으므로(안드로이드 제한), 워치 카운트를
 * 오늘 MD 파일에 **직접 기록**하고 워치로 반영한다(숫자는 저장됨). 폰에서 이어 조작할 수
 * 있도록 탭하면 카운터를 여는 알림을 띄운다.
 */
class WearListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            PATH_COUNT_ADD -> forward(CatchLogService.ACTION_ADD, parseIndex(event.data))
            PATH_COUNT_REMOVE -> forward(CatchLogService.ACTION_REMOVE, parseIndex(event.data))
            PATH_STOP_SOUND -> forward(CatchLogService.ACTION_STOP_SOUND, -1)
            PATH_STATE_REQUEST -> {
                CatchLogService.pushStateToWatch(this)
                // 워치 앱 진입 때 설정도 다시 보내, 폰 기본값 변경(앱 업데이트)이 워치에 반영되게.
                WatchSettings.push(this)
            }
            PATH_CHART_REQUEST -> CatchLogService.pushChartStateToWatch(this)
            PATH_CAMERA_OPEN -> launchCamera()
            PATH_CAMERA_CLOSE ->
                sendBroadcast(Intent(ACTION_CLOSE_CAMERA).setPackage(packageName))
            // 워치 화면 켜짐/꺼짐에 따라 미리보기 전송 재개/중지(payload 1/0).
            PATH_CAMERA_PREVIEW -> sendBroadcast(
                Intent(ACTION_CAMERA_PREVIEW).setPackage(packageName)
                    .putExtra("on", event.data.firstOrNull() != 0.toByte()))
            PATH_CAMERA_SHOOT -> sendBroadcast(
                Intent(ACTION_CAMERA_SHOOT).setPackage(packageName)
                    .putExtra("delay", parseIndex(event.data)))
            PATH_CAMERA_FLIP ->
                sendBroadcast(Intent(ACTION_CAMERA_FLIP).setPackage(packageName))
            PATH_SETTINGS_COLOR -> WatchSettings.setColorFromWatch(this, event.data)
            PATH_COUNT_RESET -> forward(CatchLogService.ACTION_CLEAR_ALL, -1)
            PATH_SCREEN_SAVE -> saveWatchScreen(event.data)
            PATH_FISHING_END -> CatchSummary.write(this, CatchSummary.today(), event.data)
        }
    }

    /**
     * 워치 요청으로 폰 카메라(셀카)를 포그라운드로 연다 — 흔들기 카메라와 동일 메커니즘.
     * 오버레이 권한이 있으면 바로 실행, 없으면 전면 인텐트 알림으로 폴백.
     */
    private fun launchCamera() {
        val intent = Intent(this, CameraLockActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            .putExtra("selfie", true)
        if (Settings.canDrawOverlays(this)) {
            try { startActivity(intent); return } catch (_: Exception) {}
        }
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CAMERA_CHANNEL_ID, "워치 카메라 실행", NotificationManager.IMPORTANCE_HIGH))
        }
        val notif = NotificationCompat.Builder(this, CAMERA_CHANNEL_ID)
            .setContentTitle("카메라 실행")
            .setContentText("워치에서 카메라를 엽니다")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
            .setFullScreenIntent(pi, true)
            .setContentIntent(pi)
            .build()
        nm.notify(CAMERA_NOTIF_ID, notif)
    }

    private fun parseIndex(data: ByteArray?): Int =
        data?.let { String(it).trim().toIntOrNull() } ?: 0

    private fun forward(action: String, speciesIndex: Int) {
        val active = CatchLogService.prefsOf(this)
            .getBoolean(CatchLogService.PREFS_ACTIVE_KEY, false)
        if (!active) {
            // 세션 미실행: FGS를 백그라운드에서 시작할 수 없으므로 파일에 직접 기록만 한다.
            // (STOP_SOUND는 재생 중인 소리가 없으니 무시.)
            when (action) {
                CatchLogService.ACTION_ADD, CatchLogService.ACTION_REMOVE ->
                    recordWithoutSession(action, speciesIndex)
                CatchLogService.ACTION_CLEAR_ALL -> {
                    CatchLogService.clearAllCatchesFromFile(this)
                    notifyCountsChanged()
                }
            }
            return
        }
        // 활성 중엔 서비스가 포그라운드로 떠 있어 startForegroundService가 기존 인스턴스에
        // onStartCommand로 명령을 전달한다.
        val intent = Intent(this, CatchLogService::class.java).apply {
            this.action = action
            if (speciesIndex >= 0) {
                putExtra(CatchLogService.EXTRA_SPECIES_INDEX, speciesIndex)
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

    /**
     * 세션이 없을 때 워치 카운트를 오늘 MD 파일에 직접 기록하고 워치로 최신 수를 반영한다.
     * 포그라운드 세션(알림/TTS/위치) 없이 '저장'만 수행 — 백그라운드 FGS 시작 제한을 피한다.
     * 폰에서 이어서 조작할 수 있도록, 탭하면 카운터 화면을 여는 알림을 띄운다.
     */
    private fun recordWithoutSession(action: String, speciesIndex: Int) {
        val species = CatchLogService.loadSpecies(this).getOrNull(speciesIndex) ?: return
        when (action) {
            CatchLogService.ACTION_ADD -> {
                // 세션 있을 때(addCatch)와 동일하게 현재 좌표를 포함해 기록.
                // (onMessageReceived는 백그라운드 스레드라 동기 조회 가능.)
                val loc = CatchLogService.lastLocationBlocking(this)
                CatchLogService.appendCatchToFile(this, species, loc?.first, loc?.second)
            }
            CatchLogService.ACTION_REMOVE ->
                CatchLogService.removeLastCatchFromFile(this, species)
        }
        notifyCountsChanged()
        postRecordedNotification()
    }

    /** 카운터·지도 화면이 떠 있으면 즉시 갱신 + 워치로 최신 수 반영. */
    private fun notifyCountsChanged() {
        try {
            sendBroadcast(
                Intent(CatchLogService.ACTION_COUNTS_CHANGED).setPackage(packageName))
        } catch (_: Exception) {}
        CatchLogService.pushStateToWatch(this)
    }

    /**
     * 워치 화면 캡처를 갤러리(DCIM/nakkda)에 저장하고, 그 경로를 오늘 메모에 사진 항목으로 추가.
     * (onMessageReceived는 백그라운드 스레드라 파일·위치 조회를 동기로 해도 된다.)
     */
    private fun saveWatchScreen(bytes: ByteArray?) {
        if (bytes == null || bytes.isEmpty()) return
        val isPng = bytes.size > 4 && bytes[0] == 0x89.toByte() && bytes[1] == 'P'.code.toByte()
        val mime = if (isPng) "image/png" else "image/jpeg"
        val ext = if (isPng) ".png" else ".jpg"
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
        val path = CatchSummary.saveImageToGallery(this, bytes, mime, "NAKKDA_WATCH_$ts$ext") ?: return
        val loc = CatchLogService.lastLocationBlocking(this)
        CatchLogService.appendPhotoToFile(this, path, loc?.first, loc?.second)
        // 지도 등 열린 화면이 오늘 파일을 다시 읽도록 갱신 신호.
        notifyCountsChanged()
    }

    /** '워치에서 기록됨 — 탭하면 카운터 열기' 알림(일반 알림이라 백그라운드에서도 가능). */
    private fun postRecordedNotification() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "워치 조과 기록", NotificationManager.IMPORTANCE_LOW
                ).apply { setShowBadge(false); setSound(null, null) })
        }
        val species = CatchLogService.loadSpecies(this)
        val counts = CatchLogService.loadCountsFromFile(this)
        val summary = if (species.isEmpty()) {
            "탭하여 카운터 열기"
        } else {
            species.joinToString(" · ") { "$it ${counts[it] ?: 0}" }
        }
        val openPi = PendingIntent.getActivity(
            this, 301,
            Intent(this, CatchCounterActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("워치에서 조과 기록됨")
            .setContentText(summary)
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentIntent(openPi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
        try { nm.notify(NOTIF_ID, notif) } catch (_: Exception) {}
    }

    companion object {
        private const val PATH_COUNT_ADD = "/nakkda/count/add"
        private const val PATH_COUNT_REMOVE = "/nakkda/count/remove"
        private const val PATH_STOP_SOUND = "/nakkda/count/stop"
        private const val PATH_STATE_REQUEST = "/nakkda/count/request"
        private const val PATH_CHART_REQUEST = "/nakkda/chart/request"
        private const val PATH_CAMERA_OPEN = "/nakkda/camera/open"
        private const val PATH_CAMERA_CLOSE = "/nakkda/camera/close"
        private const val PATH_CAMERA_SHOOT = "/nakkda/camera/shoot"
        private const val PATH_CAMERA_FLIP = "/nakkda/camera/flip"
        private const val PATH_CAMERA_PREVIEW = "/nakkda/camera/preview"
        private const val PATH_SETTINGS_COLOR = "/nakkda/settings/color"
        private const val PATH_COUNT_RESET = "/nakkda/count/reset"
        private const val PATH_SCREEN_SAVE = "/nakkda/screen/save"
        private const val PATH_FISHING_END = "/nakkda/fishing/end"
        private const val CHANNEL_ID = "nakkda_watch_record"
        private const val NOTIF_ID = 1009
        private const val CAMERA_CHANNEL_ID = "nakkda_watch_camera"
        private const val CAMERA_NOTIF_ID = 1010
        // CameraLockActivity가 수신하는 브로드캐스트(워치 카메라 조작).
        const val ACTION_CLOSE_CAMERA = "com.sgchoisg.nakkda.CLOSE_CAMERA"
        const val ACTION_CAMERA_SHOOT = "com.sgchoisg.nakkda.CAMERA_SHOOT"
        const val ACTION_CAMERA_FLIP = "com.sgchoisg.nakkda.CAMERA_FLIP"
        const val ACTION_CAMERA_PREVIEW = "com.sgchoisg.nakkda.CAMERA_PREVIEW"
    }
}
