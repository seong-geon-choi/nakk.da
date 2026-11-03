package com.sgchoisg.nakkda

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.view.KeyEvent

/**
 * 블루투스 이어폰/리모컨의 미디어 버튼(재생·정지·다음곡 등)을 화면 꺼짐 상태에서도 받기 위한
 * 경량 미디어 세션.
 *
 * 설계(사용자 확정): **오디오 포커스를 요청하지 않는다**(다른 앱 음악을 멈추거나 줄이지 않음).
 * 대신 **무음 트랙만 재생**해 우리 세션을 "활성 미디어 세션"으로 유지한다 → 세션이 활성인 동안은
 * 미디어 버튼이 음악앱 대신 이쪽으로 라우팅된다(그 시간 동안 음악 곡 변경은 불가 — 트레이드오프).
 *
 * onKey(keyCode)로 ACTION_DOWN(비반복) 키만 전달한다.
 *
 * hookVolume=true면 세션을 '원격 볼륨'으로 선언(setPlaybackToRemote)해 하드웨어 볼륨 업/다운
 * 키가 시스템 미디어 볼륨 대신 이쪽으로 들어오게 한다 → 볼륨 버튼 리모컨을 화면 꺼짐·백그라운드에서
 * +1/−1로 쓸 수 있다(그 대신 세션이 활성인 동안 하드웨어 볼륨으로 음악 볼륨 조절 불가 — 트레이드오프).
 * 볼륨 업 → KEYCODE_VOLUME_UP, 볼륨 다운 → KEYCODE_VOLUME_DOWN 으로 변환해 onKey로 전달한다.
 */
class MediaButtonSession(
    private val context: Context,
    private val tag: String,
    private val hookVolume: Boolean = false,
    // true면 오디오 포커스를 '덕킹' 모드로 요청해, 다른 미디어 앱이 재생 중(포커스 보유)이어도
    // 미디어 버튼을 이쪽으로 가져온다(다른 앱은 멈추지 않고 볼륨만 낮춤 — 단, 영상 앱 등은
    // 자체 정책상 일시정지할 수 있음). false면 포커스를 요청하지 않아 음악이 안 끊기는 대신
    // 다른 앱이 포커스를 쥐고 있으면 버튼을 못 가져온다.
    private val requestFocus: Boolean = false,
    private val onKey: (Int) -> Unit,
) {
    private var session: MediaSession? = null
    @Volatile private var track: AudioTrack? = null
    private var focusRequest: AudioFocusRequest? = null

    fun start() {
        if (session != null) return
        val s = MediaSession(context, tag)
        s.setCallback(object : MediaSession.Callback() {
            override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                val ev: KeyEvent? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonIntent.getParcelableExtra(
                            Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    }
                if (ev != null && ev.action == KeyEvent.ACTION_DOWN && ev.repeatCount == 0) {
                    onKey(ev.keyCode)
                }
                return true
            }
        })
        // STATE_PLAYING + 가능한 전송 액션을 선언해야 미디어 버튼 라우팅 대상이 된다.
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS)
                .setState(PlaybackState.STATE_PLAYING, 0L, 1f)
                .build()
        )
        // 볼륨 버튼 후킹: 세션을 '원격 볼륨'으로 선언하면 볼륨 키가 onAdjustVolume으로 들어온다.
        if (hookVolume) {
            s.setPlaybackToRemote(
                object : VolumeProvider(VolumeProvider.VOLUME_CONTROL_RELATIVE, 100, 50) {
                    override fun onAdjustVolume(direction: Int) {
                        when {
                            direction > 0 -> onKey(KeyEvent.KEYCODE_VOLUME_UP)
                            direction < 0 -> onKey(KeyEvent.KEYCODE_VOLUME_DOWN)
                        }
                    }
                }
            )
        }
        s.isActive = true
        session = s
        if (requestFocus) acquireDuckFocus()
        startSilentAudio()
    }

    /**
     * 오디오 포커스를 '덕킹'(AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)으로 요청한다.
     * 포커스를 쥐면 미디어 버튼이 이쪽 세션으로 라우팅되고, 다른 앱엔 "볼륨만 낮추라"고
     * 요청한다(음악은 작아진 채 계속 재생; 영상 앱 등은 자체 정책상 일시정지할 수 있음).
     * 우리는 무음이므로 포커스 변화에 반응하지 않는다. 세션 종료 시 abandon한다.
     */
    private fun acquireDuckFocus() {
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val req = AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setWillPauseWhenDucked(false)
                .setOnAudioFocusChangeListener { /* 무음이라 반응 없음 */ }
                .build()
            am.requestAudioFocus(req)
            focusRequest = req
        } catch (_: Exception) {}
    }

    /** 포커스 없이 무음 PCM을 흘려 세션을 활성으로 유지(소리 없음). */
    private fun startSilentAudio() {
        try {
            val sampleRate = 44100
            val min = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val bufBytes = if (min > 0) min else 4096
            val t = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build())
                .setBufferSizeInBytes(bufBytes)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            t.play()
            track = t
            val silence = ShortArray(bufBytes / 2)
            Thread {
                try {
                    while (track === t && t.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        // write는 버퍼가 빌 때까지 블록되므로 바쁜 대기가 아니다.
                        t.write(silence, 0, silence.size)
                    }
                } catch (_: Exception) {}
            }.apply { isDaemon = true }.start()
        } catch (_: Exception) {}
    }

    fun stop() {
        val t = track
        track = null
        try { t?.stop(); t?.release() } catch (_: Exception) {}
        val fr = focusRequest
        focusRequest = null
        if (fr != null) {
            try {
                (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                    .abandonAudioFocusRequest(fr)
            } catch (_: Exception) {}
        }
        try { session?.isActive = false; session?.release() } catch (_: Exception) {}
        session = null
    }
}
