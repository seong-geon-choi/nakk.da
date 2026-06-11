package com.sgchoisg.nakkda

import android.app.NotificationChannel
import android.app.NotificationManager
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.*
import android.speech.*
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat

class VoiceRecordAccessibilityService : AccessibilityService() {

    companion object {
        const val PREFS_NAME = "nakkda_prefs"
        const val PREFS_KEY = "pending_voice_result"
        const val PREFS_VOICE_RUNNING = "voice_running"
        const val BROADCAST_ACTION = "com.sgchoisg.nakkda.VOICE_RESULT"
        private const val DOUBLE_PRESS_MS = 500L
        private const val RESULT_CHANNEL_ID = "nakkda_result_channel"
        private const val RESULT_NOTIFICATION_ID = 1003
    }

    private var isRecording = false
    private var speechRecognizer: SpeechRecognizer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null

    // 첫 번째 누름을 소비하고, 두 번째가 오지 않으면 볼륨을 보상 조정
    private var pendingCompensate = false
    private val compensateRunnable = Runnable {
        if (pendingCompensate) {
            pendingCompensate = false
            (getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager)
                .adjustVolume(
                    android.media.AudioManager.ADJUST_RAISE,
                    android.media.AudioManager.FLAG_SHOW_UI
                )
        }
    }

    override fun onServiceConnected() {
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        serviceInfo = info
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP &&
            event.action == KeyEvent.ACTION_DOWN
        ) {
            val running = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREFS_VOICE_RUNNING, true)
            if (!running) return false
            if (pendingCompensate) {
                // 두 번째 누름 — 보상 취소 + 음성 메모 시작 (볼륨 변화 없음)
                pendingCompensate = false
                handler.removeCallbacks(compensateRunnable)
                handler.post { startVoiceRecording() }
            } else {
                // 첫 번째 누름 — 소비하고 400ms 대기
                pendingCompensate = true
                handler.postDelayed(compensateRunnable, DOUBLE_PRESS_MS)
            }
            return true // 항상 소비 (볼륨 즉시 변경 방지)
        }
        return false
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nakkda:accessibility_voice")
        wakeLock?.acquire(30_000L)
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun showRecordingNotification() {
        ensureResultChannel()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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

    private fun saveResult(text: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PREFS_KEY, text)
            .apply()
    }

    private fun broadcastResult(text: String) {
        val intent = Intent(BROADCAST_ACTION).apply {
            putExtra("result", text)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    @Suppress("DEPRECATION")
    private fun vibrate(pattern: LongArray) {
        val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            v.vibrate(pattern, -1)
        }
    }

    private fun ensureResultChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                RESULT_CHANNEL_ID, "음성 메모 결과", NotificationManager.IMPORTANCE_HIGH
            ).apply { setSound(null, null); enableVibration(false); setShowBadge(false) }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    private fun showResultNotification(text: String) {
        ensureResultChannel()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        nm.notify(RESULT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
                .setContentTitle("음성 메모 저장됨")
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setAutoCancel(true).setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
        )
        handler.postDelayed({ nm.cancel(RESULT_NOTIFICATION_ID) }, 4000L)
    }

    private fun showErrorNotification() {
        ensureResultChannel()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        nm.notify(RESULT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
                .setContentTitle("음성 인식 실패")
                .setContentText("다시 시도해 주세요")
                .setSmallIcon(android.R.drawable.ic_delete)
                .setAutoCancel(true).setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
        )
        handler.postDelayed({ nm.cancel(RESULT_NOTIFICATION_ID) }, 2000L)
    }

    override fun onDestroy() {
        releaseWakeLock()
        handler.post {
            speechRecognizer?.destroy()
            speechRecognizer = null
        }
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {}
    override fun onInterrupt() {
        speechRecognizer?.stopListening()
        isRecording = false
    }
}
