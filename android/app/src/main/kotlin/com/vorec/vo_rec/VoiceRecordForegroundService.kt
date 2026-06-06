package com.nakkda.nakkda

import android.app.*
import android.app.PendingIntent
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioManager  // setStreamVolume, FLAG_REMOVE_SOUND_AND_VIBRATE
import android.os.*
import android.provider.Settings
import android.speech.*
import androidx.core.app.NotificationCompat

class VoiceRecordForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID        = "nakkda_voice_channel"
        private const val RESULT_CHANNEL_ID = "nakkda_result_channel"
        private const val NOTIFICATION_ID        = 1002
        private const val RESULT_NOTIFICATION_ID = 1003
        const val ACTION_STOP = "com.nakkda.nakkda.STOP_VOICE_SERVICE"
        private const val DOUBLE_PRESS_MS = 800L

        // AudioManager 내부 상수 (@UnsupportedAppUsage라 public API 미노출)
        private const val VOL_CHANGED = "android.media.VOLUME_CHANGED_ACTION"
        private const val EXTRA_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE"
        private const val EXTRA_STREAM_VALUE = "android.media.EXTRA_VOLUME_STREAM_VALUE"
        private const val EXTRA_PREV_STREAM_VALUE = "android.media.EXTRA_PREV_VOLUME_STREAM_VALUE"

        fun start(context: Context) {
            val intent = Intent(context, VoiceRecordForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val resultNotifHandler = Handler(Looper.getMainLooper())
    private var firstPressStreamType = -1
    private var firstPressVolume = -1
    private var waitingSecondPress = false
    private var isRecording = false
    private var speechRecognizer: SpeechRecognizer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val volumeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != VOL_CHANGED) return
            val streamType = intent.getIntExtra(EXTRA_STREAM_TYPE, -1)
            val newVolume = intent.getIntExtra(EXTRA_STREAM_VALUE, -1)
            val prevVolume = intent.getIntExtra(EXTRA_PREV_STREAM_VALUE, -1)

            // 볼륨 감소는 무시
            if (newVolume < prevVolume) return

            if (waitingSecondPress) {
                // 더블클릭 확정: 보상 후 음성메모 시작
                waitingSecondPress = false
                handler.removeCallbacks(resetRunnable)
                compensateVolume(firstPressStreamType, firstPressVolume)
                handler.post { startVoiceRecording() }
            } else {
                // 첫 번째 누름: 원래 볼륨 기억, 대기
                waitingSecondPress = true
                firstPressStreamType = streamType
                firstPressVolume = prevVolume
                handler.removeCallbacks(resetRunnable)
                handler.postDelayed(resetRunnable, DOUBLE_PRESS_MS)
            }
        }
    }

    private val resetRunnable = Runnable {
        waitingSecondPress = false
        firstPressStreamType = -1
        firstPressVolume = -1
    }

    // 첫 번째 누름 이전 볼륨으로 원복 (UI 없이 조용히)
    private fun compensateVolume(streamType: Int, targetVolume: Int) {
        if (targetVolume < 0) return
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        am.setStreamVolume(streamType, targetVolume, AudioManager.FLAG_REMOVE_SOUND_AND_VIBRATE)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (e: SecurityException) {
            stopSelf()
            return
        }

        getSharedPreferences(VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(VoiceRecordAccessibilityService.PREFS_VOICE_RUNNING, true).apply()

        createResultNotificationChannel()
        val filter = IntentFilter(VOL_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(volumeReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(volumeReceiver, filter)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(volumeReceiver)
        handler.removeCallbacksAndMessages(null)
        resultNotifHandler.removeCallbacksAndMessages(null)
        handler.post {
            speechRecognizer?.destroy()
            speechRecognizer = null
        }
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            getSharedPreferences(VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(VoiceRecordAccessibilityService.PREFS_VOICE_RUNNING, false).apply()
            stopSelf()
            return START_NOT_STICKY
        }
        // 앱 재진입 시 접근성 상태가 바뀌었을 수 있으므로 알림 갱신
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?) = null

    private fun showRecordingNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        nm.notify(RESULT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
                .setContentTitle("음성 인식 중")
                .setContentText("말씀하세요...")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
        )
    }

    private fun startVoiceRecording() {
        if (isRecording) return
        isRecording = true

        acquireWakeLock()
        showRecordingNotification()
        vibrate(longArrayOf(0, 80))

        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}

            override fun onError(error: Int) {
                isRecording = false
                releaseWakeLock()
                vibrate(longArrayOf(0, 40, 60, 40))
                showErrorNotification()
            }

            override fun onResults(results: Bundle?) {
                isRecording = false
                releaseWakeLock()
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (!text.isNullOrBlank()) {
                    saveResult(text)
                    broadcastResult(text)
                    vibrate(longArrayOf(0, 50, 50, 100))
                    showResultNotification(text)
                } else {
                    vibrate(longArrayOf(0, 40, 60, 40))
                    showErrorNotification()
                }
            }

            override fun onPartialResults(partial: Bundle?) {}
            override fun onEvent(type: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2000L)
        }
        speechRecognizer?.startListening(intent)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nakkda:voice_recording")
        wakeLock?.acquire(30_000L)
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun saveResult(text: String) {
        getSharedPreferences(VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(VoiceRecordAccessibilityService.PREFS_KEY, text).apply()
    }

    private fun broadcastResult(text: String) {
        sendBroadcast(Intent(VoiceRecordAccessibilityService.BROADCAST_ACTION).apply {
            putExtra("result", text)
            setPackage(packageName)
        })
    }

    @Suppress("DEPRECATION")
    private fun vibrate(pattern: LongArray) {
        val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            v.vibrate(pattern, -1)
        }
    }

    private fun createResultNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                RESULT_CHANNEL_ID, "음성 메모 결과", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun showResultNotification(text: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        val notif = NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
            .setContentTitle("음성 메모 저장됨")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setAutoCancel(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        nm.notify(RESULT_NOTIFICATION_ID, notif)
        resultNotifHandler.removeCallbacksAndMessages(null)
        resultNotifHandler.postDelayed({ nm.cancel(RESULT_NOTIFICATION_ID) }, 4000L)
    }

    private fun showErrorNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        val notif = NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
            .setContentTitle("음성 인식 실패")
            .setContentText("다시 시도해 주세요")
            .setSmallIcon(android.R.drawable.ic_delete)
            .setAutoCancel(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        nm.notify(RESULT_NOTIFICATION_ID, notif)
        resultNotifHandler.removeCallbacksAndMessages(null)
        resultNotifHandler.postDelayed({ nm.cancel(RESULT_NOTIFICATION_ID) }, 2000L)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "음성 메모 대기", NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "볼륨 UP 2회로 음성 메모 시작"
                setShowBadge(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val target = "$packageName/${VoiceRecordAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(":").any { it.equals(target, ignoreCase = true) }
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, VoiceRecordForegroundService::class.java)
            .apply { action = ACTION_STOP }
        val stopPi = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("음성 메모 대기 중")
            .setContentText("볼륨 ↑ 2회로 음성 메모를 시작합니다")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .addAction(android.R.drawable.ic_delete, "중지", stopPi)
        if (!isAccessibilityServiceEnabled()) {
            builder.setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(
                        "볼륨 ↑ 2회로 음성 메모를 시작합니다\n\n" +
                        "잠금화면·화면 꺼짐 상태에서도 사용하려면\n" +
                        "설정 → 잠금화면·화면 꺼짐 상태 지원을 활성화하세요"
                    )
            )
        }
        return builder.build()
    }
}
