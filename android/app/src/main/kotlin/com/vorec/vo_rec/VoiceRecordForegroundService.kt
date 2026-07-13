package com.sgchoisg.nakkda

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.hardware.*
import android.os.*
import android.speech.*
import androidx.core.app.NotificationCompat

class VoiceRecordForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID        = "nakkda_voice_channel"
        private const val RESULT_CHANNEL_ID = "nakkda_result_channel"
        private const val NOTIFICATION_ID        = 1002
        private const val RESULT_NOTIFICATION_ID = 1003
        const val ACTION_STOP = "com.sgchoisg.nakkda.STOP_VOICE_SERVICE"
        const val EXTRA_MODE  = "mode"
        const val EXTRA_SHAKE_THRESHOLD = "shakeThresholdG"

        // 음성 인식 결과 전달용(SharedPreferences + 브로드캐스트)
        const val PREFS_NAME       = "nakkda_prefs"
        const val PREFS_KEY        = "pending_voice_result"
        const val BROADCAST_ACTION = "com.sgchoisg.nakkda.VOICE_RESULT"

        private const val DEFAULT_SHAKE_THRESHOLD_G = 3.5f
        private const val MIN_SHAKE_INTERVAL_MS  = 250L
        private const val SHAKE_WINDOW_MS        = 1500L
        private const val REQUIRED_SHAKES        = 3

        fun start(
            context: Context,
            mode: String = "shake",
            shakeThresholdG: Float = DEFAULT_SHAKE_THRESHOLD_G,
        ) {
            val intent = Intent(context, VoiceRecordForegroundService::class.java)
                .apply {
                    putExtra(EXTRA_MODE, mode)
                    putExtra(EXTRA_SHAKE_THRESHOLD, shakeThresholdG)
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val handler             = Handler(Looper.getMainLooper())
    private val resultNotifHandler  = Handler(Looper.getMainLooper())
    private var isRecording         = false
    private var speechRecognizer: SpeechRecognizer? = null
    private var wakeLock: PowerManager.WakeLock?    = null
    private var currentMode         = "shake"

    // ── 흔들기 감지 ────────────────────────────────────────────
    private var sensorManager: SensorManager? = null
    private var shakeThresholdG = DEFAULT_SHAKE_THRESHOLD_G
    private var lastShakeEventTime = 0L
    private var shakeCount         = 0
    private var windowStartTime    = 0L
    private var sensorListenerRegistered = false

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val now  = SystemClock.elapsedRealtime()
            val x    = event.values[0]; val y = event.values[1]; val z = event.values[2]
            val gForce = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat() /
                         SensorManager.GRAVITY_EARTH

            if (gForce > shakeThresholdG && now - lastShakeEventTime > MIN_SHAKE_INTERVAL_MS) {
                lastShakeEventTime = now
                if (now - windowStartTime > SHAKE_WINDOW_MS) {
                    windowStartTime = now; shakeCount = 1
                } else {
                    shakeCount++
                    if (shakeCount >= REQUIRED_SHAKES) {
                        shakeCount = 0; windowStartTime = 0L
                        handler.post { startVoiceRecording() }
                    }
                }
            }
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    // ── 생명주기 ───────────────────────────────────────────────
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
        } catch (e: SecurityException) { stopSelf(); return }

        createResultNotificationChannel()

        currentMode = LocationTrackingService.getQuickLaunchMode(this)
        shakeThresholdG = LocationTrackingService.getShakeThresholdG(this)
        applyMode(currentMode)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val newMode = intent?.getStringExtra(EXTRA_MODE) ?: currentMode
        val newThreshold =
            intent?.getFloatExtra(EXTRA_SHAKE_THRESHOLD, shakeThresholdG) ?: shakeThresholdG
        // 모드가 바뀌거나, 흔들기 모드에서 임계값이 바뀌면 센서 리스너를 다시 붙인다.
        if (newMode != currentMode ||
            (newMode == "shake" && newThreshold != shakeThresholdG)) {
            currentMode = newMode
            shakeThresholdG = newThreshold
            applyMode(currentMode)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        detachShake()
        handler.removeCallbacksAndMessages(null)
        resultNotifHandler.removeCallbacksAndMessages(null)
        handler.post { speechRecognizer?.destroy(); speechRecognizer = null }
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    // ── 모드 적용 ──────────────────────────────────────────────
    private fun applyMode(mode: String) {
        when (mode) {
            "shake"  -> attachShake()
            else     -> detachShake()   // "none"
        }
    }

    private fun attachShake() {
        if (sensorListenerRegistered) return
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        val accel = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        sensorManager?.registerListener(sensorListener, accel, SensorManager.SENSOR_DELAY_GAME)
        sensorListenerRegistered = true
    }

    private fun detachShake() {
        if (!sensorListenerRegistered) return
        sensorManager?.unregisterListener(sensorListener)
        sensorManager = null
        sensorListenerRegistered = false
    }

    // ── 음성 녹음 ──────────────────────────────────────────────
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
                isRecording = false; releaseWakeLock()
                vibrate(longArrayOf(0, 40, 60, 40)); showErrorNotification()
            }

            override fun onResults(results: Bundle?) {
                isRecording = false; releaseWakeLock()
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (!text.isNullOrBlank()) {
                    saveResult(text); broadcastResult(text)
                    vibrate(longArrayOf(0, 50, 50, 100)); showResultNotification(text)
                } else {
                    vibrate(longArrayOf(0, 40, 60, 40)); showErrorNotification()
                }
            }

            override fun onPartialResults(partial: Bundle?) {}
            override fun onEvent(type: Int, params: Bundle?) {}
        })

        speechRecognizer?.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2000L)
            }
        )
    }

    // ── 알림 ───────────────────────────────────────────────────
    private fun buildNotification(): Notification {
        val stopPi = PendingIntent.getService(
            this, 0,
            Intent(this, VoiceRecordForegroundService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val (title, body) = when (currentMode) {
            "none"   -> "음성 메모 서비스" to "빠른 실행이 비활성화되어 있습니다"
            else     -> "음성 메모 대기 중" to "흔들기 3회로 음성 메모를 시작합니다"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true).setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .addAction(android.R.drawable.ic_delete, "중지", stopPi)
            .build()
    }

    private fun showRecordingNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        nm.notify(RESULT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
                .setContentTitle("음성 인식 중").setContentText("말씀하세요...")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now).setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).build()
        )
    }

    private fun showResultNotification(text: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        nm.notify(RESULT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
                .setContentTitle("음성 메모 저장됨")
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setAutoCancel(true).setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).build()
        )
        resultNotifHandler.removeCallbacksAndMessages(null)
        resultNotifHandler.postDelayed({ nm.cancel(RESULT_NOTIFICATION_ID) }, 4000L)
    }

    private fun showErrorNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(RESULT_NOTIFICATION_ID)
        nm.notify(RESULT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, RESULT_CHANNEL_ID)
                .setContentTitle("음성 인식 실패").setContentText("다시 시도해 주세요")
                .setSmallIcon(android.R.drawable.ic_delete).setAutoCancel(true).setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).build()
        )
        resultNotifHandler.removeCallbacksAndMessages(null)
        resultNotifHandler.postDelayed({ nm.cancel(RESULT_NOTIFICATION_ID) }, 2000L)
    }

    // ── 헬퍼 ───────────────────────────────────────────────────
    private fun saveResult(text: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(PREFS_KEY, text).apply()
    }

    private fun broadcastResult(text: String) {
        sendBroadcast(Intent(BROADCAST_ACTION).apply {
            putExtra("result", text); setPackage(packageName)
        })
    }

    @Suppress("DEPRECATION")
    private fun vibrate(pattern: LongArray) {
        val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            v.vibrate(VibrationEffect.createWaveform(pattern, -1))
        else v.vibrate(pattern, -1)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nakkda:voice_recording")
        wakeLock?.acquire(30_000L)
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "음성 메모 대기", NotificationManager.IMPORTANCE_MIN)
                .apply { setShowBadge(false) }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun createResultNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(RESULT_CHANNEL_ID, "음성 메모 결과", NotificationManager.IMPORTANCE_HIGH)
                .apply { setShowBadge(false); setSound(null, null); enableVibration(false) }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }
}
