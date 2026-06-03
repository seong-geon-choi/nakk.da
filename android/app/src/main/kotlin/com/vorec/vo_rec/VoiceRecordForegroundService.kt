package com.nakkda.nakkda

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioManager  // setStreamVolume, FLAG_REMOVE_SOUND_AND_VIBRATE
import android.os.*
import android.speech.*
import androidx.core.app.NotificationCompat

class VoiceRecordForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "nakkda_voice_channel"
        private const val NOTIFICATION_ID = 1002
        private const val DOUBLE_PRESS_MS = 500L

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

            if (waitingSecondPress && streamType == firstPressStreamType) {
                // 더블클릭 확정: 보상 후 음성메모 시작
                waitingSecondPress = false
                handler.removeCallbacks(resetRunnable)
                compensateVolume(streamType, firstPressVolume)
                handler.post { startVoiceRecording() }
            } else {
                // 첫 번째 누름: 원래 볼륨 기억, 500ms 대기
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
        handler.post {
            speechRecognizer?.destroy()
            speechRecognizer = null
        }
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    private fun startVoiceRecording() {
        if (isRecording) return
        isRecording = true

        acquireWakeLock()
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
                } else {
                    vibrate(longArrayOf(0, 40, 60, 40))
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

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("음성 메모 대기 중")
            .setContentText("볼륨 UP 2회로 음성 메모를 시작합니다")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
}
