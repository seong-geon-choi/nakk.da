package com.sgchoisg.nakkda

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.hardware.*
import android.media.AudioManager
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
        const val ACTION_STOP = "com.sgchoisg.nakkda.STOP_VOICE_SERVICE"
        const val EXTRA_MODE  = "mode"

        private const val VOL_CHANGED        = "android.media.VOLUME_CHANGED_ACTION"
        private const val EXTRA_STREAM_TYPE  = "android.media.EXTRA_VOLUME_STREAM_TYPE"
        private const val EXTRA_STREAM_VALUE = "android.media.EXTRA_VOLUME_STREAM_VALUE"
        private const val EXTRA_PREV_STREAM_VALUE = "android.media.EXTRA_PREV_VOLUME_STREAM_VALUE"
        private const val DOUBLE_PRESS_MS    = 800L

        private const val SHAKE_THRESHOLD_G      = 2.5f
        private const val MIN_SHAKE_INTERVAL_MS  = 250L
        private const val SHAKE_WINDOW_MS        = 1500L
        private const val REQUIRED_SHAKES        = 3

        fun start(context: Context, mode: String = "shake") {
            val intent = Intent(context, VoiceRecordForegroundService::class.java)
                .apply { putExtra(EXTRA_MODE, mode) }
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
    private var volumeReceiverRegistered = false

    // ── 볼륨 버튼 ──────────────────────────────────────────────
    private var firstPressStreamType = -1
    private var firstPressVolume     = -1
    private var waitingSecondPress   = false

    private val volumeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != VOL_CHANGED) return
            val newVolume  = intent.getIntExtra(EXTRA_STREAM_VALUE, -1)
            val prevVolume = intent.getIntExtra(EXTRA_PREV_STREAM_VALUE, -1)
            val streamType = intent.getIntExtra(EXTRA_STREAM_TYPE, -1)
            if (newVolume < prevVolume) return

            if (waitingSecondPress) {
                waitingSecondPress = false
                handler.removeCallbacks(resetRunnable)
                compensateVolume(firstPressStreamType, firstPressVolume)
                handler.post { startVoiceRecording() }
            } else {
                waitingSecondPress    = true
                firstPressStreamType  = streamType
                firstPressVolume      = prevVolume
                handler.removeCallbacks(resetRunnable)
                handler.postDelayed(resetRunnable, DOUBLE_PRESS_MS)
            }
        }
    }

    private val resetRunnable = Runnable {
        waitingSecondPress   = false
        firstPressStreamType = -1
        firstPressVolume     = -1
    }

    private fun compensateVolume(streamType: Int, targetVolume: Int) {
        if (targetVolume < 0) return
        (getSystemService(AUDIO_SERVICE) as AudioManager)
            .setStreamVolume(streamType, targetVolume, AudioManager.FLAG_REMOVE_SOUND_AND_VIBRATE)
    }

    // ── 흔들기 감지 ────────────────────────────────────────────
    private var sensorManager: SensorManager? = null
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

            if (gForce > SHAKE_THRESHOLD_G && now - lastShakeEventTime > MIN_SHAKE_INTERVAL_MS) {
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

        getSharedPreferences(VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(VoiceRecordAccessibilityService.PREFS_VOICE_RUNNING, true).apply()

        createResultNotificationChannel()

        currentMode = LocationTrackingService.getQuickLaunchMode(this)
        applyMode(currentMode)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            getSharedPreferences(VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(VoiceRecordAccessibilityService.PREFS_VOICE_RUNNING, false).apply()
            stopSelf()
            return START_NOT_STICKY
        }
        val newMode = intent?.getStringExtra(EXTRA_MODE) ?: currentMode
        if (newMode != currentMode) {
            currentMode = newMode
            applyMode(currentMode)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        detachVolume()
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
            "shake"  -> { detachVolume(); attachShake() }
            "volume" -> { detachShake();  attachVolume() }
            else     -> { detachVolume(); detachShake() }   // "none"
        }
    }

    private fun attachVolume() {
        if (volumeReceiverRegistered) return
        val filter = IntentFilter(VOL_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(volumeReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(volumeReceiver, filter)
        }
        volumeReceiverRegistered = true
    }

    private fun detachVolume() {
        if (!volumeReceiverRegistered) return
        try { unregisterReceiver(volumeReceiver) } catch (_: Exception) {}
        volumeReceiverRegistered = false
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
            "shake"  -> "음성 메모 대기 중" to "흔들기 3회로 음성 메모를 시작합니다"
            "none"   -> "음성 메모 서비스" to "빠른 실행이 비활성화되어 있습니다"
            else     -> "음성 메모 대기 중" to "볼륨 ↑ 2회로 음성 메모를 시작합니다"
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true).setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .addAction(android.R.drawable.ic_delete, "중지", stopPi)

        if (currentMode == "volume" && !isAccessibilityServiceEnabled()) {
            builder.setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "볼륨 ↑ 2회로 음성 메모를 시작합니다\n\n" +
                    "잠금화면·화면 꺼짐 상태에서도 사용하려면\n" +
                    "설정 → 잠금화면·화면 꺼짐 상태 지원을 활성화하세요"
                )
            )
        }
        return builder.build()
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
        getSharedPreferences(VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(VoiceRecordAccessibilityService.PREFS_KEY, text).apply()
    }

    private fun broadcastResult(text: String) {
        sendBroadcast(Intent(VoiceRecordAccessibilityService.BROADCAST_ACTION).apply {
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

    private fun isAccessibilityServiceEnabled(): Boolean {
        val target = "$packageName/${VoiceRecordAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.split(":").any { it.equals(target, ignoreCase = true) }
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
