package com.nakkda.nakkda

import android.app.Activity
import android.content.*
import android.content.pm.ServiceInfo
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val mediaChannelName = "com.nakkda.nakkda/media"
    private val accessibilityChannelName = "com.nakkda.nakkda/accessibility"
    private val arChannelName = "com.nakkda.nakkda/ar"

    private var accessibilityChannel: MethodChannel? = null
    private var pendingArResult: MethodChannel.Result? = null
    private var pendingGalleryResult: MethodChannel.Result? = null

    companion object {
        private const val AR_REQUEST_CODE = 1001
        private const val GALLERY_PICK_REQUEST_CODE = 1002
    }

    private val voiceResultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val text = intent.getStringExtra("result") ?: return
            runOnUiThread {
                accessibilityChannel?.invokeMethod("onVoiceResult", text)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 미디어 채널 (사진 저장 / 갤러리 피커) ─────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                "saveToGallery" -> {
                    val sourcePath = call.argument<String>("path")
                    val relativePath = call.argument<String>("relativePath") ?: "DCIM/nakkda"
                    if (sourcePath == null) {
                        result.error("INVALID_ARG", "path is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val sourceFile = File(sourcePath)
                        val isPng = sourceFile.name.lowercase().endsWith(".png")
                        val mimeType = if (isPng) "image/png" else "image/jpeg"
                        val ext = if (isPng) ".png" else ".jpg"
                        val dateStr = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                        val displayName = "NAKKDA_$dateStr$ext"

                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                            put(MediaStore.Images.Media.RELATIVE_PATH, "$relativePath/")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                        val uri = contentResolver.insert(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values
                        )
                        if (uri == null) {
                            result.error("INSERT_FAILED", "MediaStore insert returned null", null)
                            return@setMethodCallHandler
                        }
                        val out = contentResolver.openOutputStream(uri)
                        if (out == null) {
                            contentResolver.delete(uri, null, null)
                            result.error("STREAM_FAILED", "openOutputStream returned null", null)
                            return@setMethodCallHandler
                        }
                        out.use { sourceFile.inputStream().copyTo(it) }

                        values.clear()
                        values.put(MediaStore.Images.Media.IS_PENDING, 0)
                        contentResolver.update(uri, values, null, null)

                        var filePath: String? = null
                        contentResolver.query(
                            uri, arrayOf(MediaStore.Images.Media.DATA), null, null, null
                        )?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                filePath = cursor.getString(
                                    cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                                )
                            }
                        }
                        if (filePath == null) {
                            val base = Environment.getExternalStorageDirectory().absolutePath
                            filePath = "$base/$relativePath/$displayName"
                        }

                        val finalPath = filePath
                        if (finalPath != null) {
                            MediaScannerConnection.scanFile(
                                applicationContext, arrayOf(finalPath), arrayOf(mimeType), null
                            )
                        }
                        result.success(filePath)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                "pickGalleryImage" -> {
                    if (pendingGalleryResult != null) {
                        result.error("BUSY", "Gallery pick already in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingGalleryResult = result
                    val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, GALLERY_PICK_REQUEST_CODE)
                }
                else -> result.notImplemented()
                }
            }

        // ── AR 측정 채널 ─────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, arChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "launchArMeasure") {
                    val watermarkEnabled = call.argument<Boolean>("watermarkEnabled") ?: false
                    pendingArResult = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(
                        Intent(this, ArMeasureActivity::class.java).apply {
                            putExtra(ArMeasureActivity.EXTRA_WATERMARK_ENABLED, watermarkEnabled)
                            call.argument<String>("wmPosition")?.let { putExtra("wmPosition", it) }
                            call.argument<String>("wmDateFmt")?.let { putExtra("wmDateFmt", it) }
                            call.argument<String>("wmTimeFmt")?.let { putExtra("wmTimeFmt", it) }
                            call.argument<String>("wmCustomText")?.let { putExtra("wmCustomText", it) }
                            call.argument<Int>("wmFontSize")?.let { putExtra("wmFontSize", it) }
                            call.argument<Boolean>("wmBold")?.let { putExtra("wmBold", it) }
                            call.argument<Double>("wmBoxOpacity")?.let { putExtra("wmBoxOpacity", it.toFloat()) }
                            call.argument<String>("wmAlignment")?.let { putExtra("wmAlignment", it) }
                        },
                        AR_REQUEST_CODE
                    )
                } else {
                    result.notImplemented()
                }
            }

        // ── 접근성 채널 ──────────────────────────────────────
        accessibilityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, accessibilityChannelName
        )
        accessibilityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> {
                    val enabled = isAccessibilityServiceEnabled()
                    result.success(enabled)
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                    result.success(null)
                }
                "getPendingResult" -> {
                    val prefs = getSharedPreferences(
                        VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE
                    )
                    result.success(prefs.getString(VoiceRecordAccessibilityService.PREFS_KEY, null))
                }
                "clearPendingResult" -> {
                    getSharedPreferences(
                        VoiceRecordAccessibilityService.PREFS_NAME, Context.MODE_PRIVATE
                    ).edit().remove(VoiceRecordAccessibilityService.PREFS_KEY).apply()
                    result.success(null)
                }
                "startVoiceService" -> {
                    if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                            == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        VoiceRecordForegroundService.start(this)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val target = "${packageName}/${VoiceRecordAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(":").any { it.equals(target, ignoreCase = true) }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == AR_REQUEST_CODE) {
            val pending = pendingArResult
            pendingArResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                val path = data.getStringExtra(ArMeasureActivity.EXTRA_PHOTO_PATH)
                val dist = if (data.hasExtra(ArMeasureActivity.EXTRA_DISTANCE_CM))
                    data.getDoubleExtra(ArMeasureActivity.EXTRA_DISTANCE_CM, -1.0)
                else null
                val applyWm = data.getBooleanExtra(ArMeasureActivity.EXTRA_APPLY_WATERMARK, false)
                pending?.success(mapOf("path" to path, "distanceCm" to dist, "applyWatermark" to applyWm))
            } else {
                pending?.success(null)
            }
        }
        if (requestCode == GALLERY_PICK_REQUEST_CODE) {
            val pending = pendingGalleryResult
            pendingGalleryResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                var filePath: String? = null
                // MANAGE_EXTERNAL_STORAGE 있으면 MediaStore에서 실제 파일 경로 조회
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    Environment.isExternalStorageManager()) {
                    contentResolver.query(
                        uri, arrayOf(MediaStore.Images.Media.DATA), null, null, null
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val col = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                            if (col >= 0) filePath = cursor.getString(col)
                        }
                    }
                }
                // 권한 없거나 경로 조회 실패 시 앱 캐시에 복사
                if (filePath == null) filePath = copyUriToCache(uri)
                pending?.success(filePath)
            } else {
                pending?.success(null)  // 취소
            }
        }
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val dest = File(cacheDir, "gallery_${System.currentTimeMillis()}.jpg")
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            dest.absolutePath
        } catch (e: Exception) { null }
    }

    override fun onResume() {
        super.onResume()
        // RECORD_AUDIO가 허가된 경우에만 시작 (API 34+ SecurityException 방지)
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            VoiceRecordForegroundService.start(this)
        }
        val filter = IntentFilter(VoiceRecordAccessibilityService.BROADCAST_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(voiceResultReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(voiceResultReceiver, filter)
        }
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(voiceResultReceiver) } catch (_: Exception) {}
    }
}
