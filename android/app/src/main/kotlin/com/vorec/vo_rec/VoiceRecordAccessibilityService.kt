package com.nakkda.nakkda

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.*
import android.speech.*
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class VoiceRecordAccessibilityService : AccessibilityService() {

    companion object {
        const val PREFS_NAME = "nakkda_prefs"
        const val PREFS_KEY = "pending_voice_result"
        const val BROADCAST_ACTION = "com.nakkda.nakkda.VOICE_RESULT"
        private const val DOUBLE_PRESS_MS = 500L
    }

    private var isRecording = false
    private var speechRecognizer: SpeechRecognizer? = null
    private val handler = Handler(Looper.getMainLooper())

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

    private fun startVoiceRecording() {
        if (isRecording) return
        isRecording = true

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
                vibrate(longArrayOf(0, 40, 60, 40)) // 실패 패턴
            }

            override fun onResults(results: Bundle?) {
                isRecording = false
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (!text.isNullOrBlank()) {
                    saveResult(text)
                    broadcastResult(text)
                    vibrate(longArrayOf(0, 50, 50, 100)) // 성공 패턴
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

    override fun onDestroy() {
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
