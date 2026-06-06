package com.nakkda.nakkda

import android.app.Activity
import android.content.*
import android.content.pm.ServiceInfo
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
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
    private val safChannelName = "com.nakkda.nakkda/saf"

    private var accessibilityChannel: MethodChannel? = null
    private var pendingArResult: MethodChannel.Result? = null
    private var pendingGalleryResult: MethodChannel.Result? = null
    private var pendingMediaResult: MethodChannel.Result? = null
    private var pendingSafResult: MethodChannel.Result? = null

    companion object {
        private const val AR_REQUEST_CODE = 1001
        private const val GALLERY_PICK_REQUEST_CODE = 1002
        private const val SAF_FOLDER_REQUEST_CODE = 1003
        private const val GALLERY_MEDIA_REQUEST_CODE = 1004
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
                "pickGalleryMedia" -> {
                    if (pendingMediaResult != null) {
                        result.error("BUSY", "Media pick already in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingMediaResult = result
                    val mimeFilter = call.argument<String>("mimeFilter") ?: "*/*"
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        if (mimeFilter == "*/*") {
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                        } else {
                            type = mimeFilter
                        }
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, GALLERY_MEDIA_REQUEST_CODE)
                }
                "scanPhotosByDate" -> {
                    val year  = call.argument<Int>("year")  ?: return@setMethodCallHandler result.error("ARG", "year missing", null)
                    val month = call.argument<Int>("month") ?: return@setMethodCallHandler result.error("ARG", "month missing", null)
                    val day   = call.argument<Int>("day")   ?: return@setMethodCallHandler result.error("ARG", "day missing", null)
                    val cal = java.util.Calendar.getInstance()
                    cal.set(year, month - 1, day, 0, 0, 0); cal.set(java.util.Calendar.MILLISECOND, 0)
                    val startMs = cal.timeInMillis
                    cal.set(year, month - 1, day, 23, 59, 59); cal.set(java.util.Calendar.MILLISECOND, 999)
                    val endMs = cal.timeInMillis
                    android.util.Log.d("ScanPhotos", "scan $year-$month-$day startMs=$startMs endMs=$endMs")
                    // 전체 사진 및 DATE_TAKEN 샘플 로깅
                    contentResolver.query(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_TAKEN),
                        null, null, "${MediaStore.Images.Media.DATE_TAKEN} DESC"
                    )?.use { c ->
                        android.util.Log.d("ScanPhotos", "total=${c.count}")
                        val dtCol = c.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
                        var n = 0; while (c.moveToNext() && n < 5) { android.util.Log.d("ScanPhotos", "  sample=${c.getLong(dtCol)}"); n++ }
                    }
                    val items = mutableListOf<Map<String, Any?>>()
                    contentResolver.query(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_TAKEN),
                        "${MediaStore.Images.Media.DATE_TAKEN} BETWEEN ? AND ?",
                        arrayOf(startMs.toString(), endMs.toString()),
                        "${MediaStore.Images.Media.DATE_TAKEN} ASC"
                    )?.use { cursor ->
                        android.util.Log.d("ScanPhotos", "matched=${cursor.count}")
                        val idCol = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                        val dtCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
                        while (cursor.moveToNext()) {
                            val id = cursor.getLong(idCol)
                            val dateTaken = cursor.getLong(dtCol)
                            if (dateTaken == 0L) continue
                            val contentUri = android.content.ContentUris.withAppendedId(
                                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                            var gpsLat: Double? = null; var gpsLng: Double? = null
                            try {
                                val exifUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                                    MediaStore.setRequireOriginal(contentUri) else contentUri
                                contentResolver.openInputStream(exifUri)?.use { stream ->
                                    val exif = android.media.ExifInterface(stream)
                                    val latStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE)
                                    val lngStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE)
                                    val latRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE_REF)
                                    val lngRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE_REF)
                                    if (latStr != null && lngStr != null) {
                                        var lat = parseDms(latStr); var lng = parseDms(lngStr)
                                        if (latRef?.uppercase() == "S") lat = -lat
                                        if (lngRef?.uppercase() == "W") lng = -lng
                                        if (lat != 0.0 || lng != 0.0) { gpsLat = lat; gpsLng = lng }
                                    }
                                }
                            } catch (_: Exception) {}
                            items.add(mapOf("contentUri" to contentUri.toString(), "dateTaken" to dateTaken, "lat" to gpsLat, "lng" to gpsLng))
                        }
                    }
                    android.util.Log.d("ScanPhotos", "result=${items.size}")
                    result.success(items)
                }
                "copyContentUriToCache" -> {
                    val uriStr = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                    result.success(copyUriToCache(Uri.parse(uriStr)))
                }
                "getBuildInfo" -> {
                    result.success(mapOf(
                        "version"   to BuildConfig.VERSION_NAME,
                        "buildTime" to BuildConfig.BUILD_TIME
                    ))
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

        // ── SAF 채널 (Storage Access Framework) ─────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        if (pendingSafResult != null) {
                            result.error("BUSY", "Folder pick already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingSafResult = result
                        val initialPath = call.argument<String>("initialPath")
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                     Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                     Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            try {
                                val docId = if (initialPath != null) {
                                    val rel = initialPath.removePrefix("/storage/emulated/0/")
                                    "primary:$rel"
                                } else {
                                    "primary:Documents"
                                }
                                putExtra(DocumentsContract.EXTRA_INITIAL_URI,
                                    DocumentsContract.buildDocumentUri(
                                        "com.android.externalstorage.documents", docId))
                            } catch (_: Exception) {}
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, SAF_FOLDER_REQUEST_CODE)
                    }
                    "readTextFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val filename = call.argument<String>("filename") ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        result.success(safReadFile(uri, filename))
                    }
                    "writeTextFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val filename = call.argument<String>("filename") ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        val content = call.argument<String>("content") ?: return@setMethodCallHandler result.error("ARG", "content missing", null)
                        safWriteFile(uri, filename, content)
                        result.success(null)
                    }
                    "appendTextFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val filename = call.argument<String>("filename") ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        val content = call.argument<String>("content") ?: return@setMethodCallHandler result.error("ARG", "content missing", null)
                        val existing = safReadFile(uri, filename) ?: ""
                        safWriteFile(uri, filename, existing + content)
                        result.success(null)
                    }
                    "fileExists" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val filename = call.argument<String>("filename") ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        result.success(safFileExists(uri, filename))
                    }
                    "listMdFiles" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        result.success(safListMdFiles(uri))
                    }
                    "ensureFolder" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        safEnsureNoMedia(uri)
                        result.success(null)
                    }
                    "deleteFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val filename = call.argument<String>("filename") ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        safDeleteFile(uri, filename)
                        result.success(null)
                    }
                    "renameFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val oldFilename = call.argument<String>("oldFilename") ?: return@setMethodCallHandler result.error("ARG", "oldFilename missing", null)
                        val newFilename = call.argument<String>("newFilename") ?: return@setMethodCallHandler result.error("ARG", "newFilename missing", null)
                        safRenameFile(uri, oldFilename, newFilename)
                        result.success(null)
                    }
                    "copyFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val srcFilename = call.argument<String>("srcFilename") ?: return@setMethodCallHandler result.error("ARG", "srcFilename missing", null)
                        val dstFilename = call.argument<String>("dstFilename") ?: return@setMethodCallHandler result.error("ARG", "dstFilename missing", null)
                        val content = safReadFile(uri, srcFilename)
                        if (content != null) safWriteFile(uri, dstFilename, content)
                        result.success(null)
                    }
                    "getDisplayPath" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        result.success(safGetDisplayPath(uri))
                    }
                    "copyFileToSafFolder" -> {
                        val sourcePath = call.argument<String>("sourcePath") ?: return@setMethodCallHandler result.error("ARG", "sourcePath missing", null)
                        val folderUri  = call.argument<String>("folderUri")  ?: return@setMethodCallHandler result.error("ARG", "folderUri missing", null)
                        val filename   = call.argument<String>("filename")   ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        try {
                            val root = DocumentFile.fromTreeUri(this, Uri.parse(folderUri))
                            val sub  = root?.findFile("photos") ?: root?.createDirectory("photos")
                            val dest = sub?.findFile(filename)  ?: sub?.createFile("image/jpeg", filename)
                            if (dest == null) { result.error("CREATE_FAILED", "cannot create file", null); return@setMethodCallHandler }
                            java.io.FileInputStream(java.io.File(sourcePath)).use { inp ->
                                contentResolver.openOutputStream(dest.uri)?.use { out -> inp.copyTo(out) }
                            }
                            result.success(null)
                        } catch (e: Exception) { result.error("COPY_ERROR", e.message, null) }
                    }
                    "readSafImage" -> {
                        val folderUri = call.argument<String>("folderUri") ?: return@setMethodCallHandler result.error("ARG", "folderUri missing", null)
                        val subpath   = call.argument<String>("subpath")   ?: return@setMethodCallHandler result.error("ARG", "subpath missing", null)
                        try {
                            var node = DocumentFile.fromTreeUri(this, Uri.parse(folderUri))
                            for (part in subpath.split("/")) { node = node?.findFile(part) }
                            val bytes = node?.let { contentResolver.openInputStream(it.uri)?.use { s -> s.readBytes() } }
                            result.success(bytes)
                        } catch (e: Exception) { result.error("READ_ERROR", e.message, null) }
                    }
                    "listPhotosFolder" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val photosFolder = safFolder(uri)?.findFile("photos")
                        val names = photosFolder?.listFiles()
                            ?.filter { it.isFile }
                            ?.mapNotNull { it.name }
                            ?: emptyList<String>()
                        result.success(names)
                    }
                    "deletePhotoFile" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        val filename = call.argument<String>("filename") ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        safFolder(uri)?.findFile("photos")?.findFile(filename)?.delete()
                        result.success(null)
                    }
                    "readExifGps" -> {
                        val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("ARG", "path missing", null)
                        android.util.Log.d("ExifGps", "readExifGps path=$path")
                        android.util.Log.d("ExifGps", "file exists=${java.io.File(path).exists()}, size=${java.io.File(path).length()}")
                        try {
                            val exif = android.media.ExifInterface(path)
                            val latStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE)
                            val latRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE_REF)
                            val lngStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE)
                            val lngRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE_REF)
                            android.util.Log.d("ExifGps", "latStr=$latStr latRef=$latRef lngStr=$lngStr lngRef=$lngRef")
                            if (latStr == null || lngStr == null) {
                                android.util.Log.d("ExifGps", "no GPS attributes, returning null")
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            var lat = parseDms(latStr)
                            var lng = parseDms(lngStr)
                            if (latRef?.uppercase() == "S") lat = -lat
                            if (lngRef?.uppercase() == "W") lng = -lng
                            android.util.Log.d("ExifGps", "parsed lat=$lat lng=$lng")
                            if (lat == 0.0 && lng == 0.0) {
                                android.util.Log.d("ExifGps", "lat/lng both 0.0, returning null")
                                result.success(null)
                            } else {
                                android.util.Log.d("ExifGps", "success lat=$lat lng=$lng")
                                result.success(mapOf("lat" to lat, "lng" to lng))
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("ExifGps", "exception: ${e.message}", e)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
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
        if (requestCode == SAF_FOLDER_REQUEST_CODE) {
            val pending = pendingSafResult
            pendingSafResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                pending?.success(mapOf(
                    "uri" to uri.toString(),
                    "displayPath" to safGetDisplayPath(uri.toString())
                ))
            } else {
                pending?.success(null)
            }
        }
        if (requestCode == GALLERY_MEDIA_REQUEST_CODE) {
            val pending = pendingMediaResult
            pendingMediaResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                val mimeType = contentResolver.getType(uri) ?: ""
                val isVideo = mimeType.startsWith("video/")
                val filePath = copyUriToCache(uri)
                if (isVideo) {
                    pending?.success(mapOf("path" to filePath, "isVideo" to true, "lat" to null, "lng" to null))
                } else {
                    // 이미지: GPS 읽기 시도
                    var gpsLat: Double? = null
                    var gpsLng: Double? = null
                    try {
                        val exifUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                            MediaStore.setRequireOriginal(uri) else uri
                        contentResolver.openInputStream(exifUri)?.use { stream ->
                            val exif = android.media.ExifInterface(stream)
                            val latStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE)
                            val lngStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE)
                            val latRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE_REF)
                            val lngRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE_REF)
                            if (latStr != null && lngStr != null) {
                                var lat = parseDms(latStr); var lng = parseDms(lngStr)
                                if (latRef?.uppercase() == "S") lat = -lat
                                if (lngRef?.uppercase() == "W") lng = -lng
                                if (lat != 0.0 || lng != 0.0) { gpsLat = lat; gpsLng = lng }
                            }
                        }
                    } catch (_: Exception) {}
                    pending?.success(mapOf("path" to filePath, "isVideo" to false, "lat" to gpsLat, "lng" to gpsLng))
                }
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

                // ACCESS_MEDIA_LOCATION 권한으로 원본 URI에서 GPS 읽기
                var gpsLat: Double? = null
                var gpsLng: Double? = null
                try {
                    val exifUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                        MediaStore.setRequireOriginal(uri) else uri
                    contentResolver.openInputStream(exifUri)?.use { stream ->
                        val exif = android.media.ExifInterface(stream)
                        val latStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE)
                        val lngStr = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE)
                        val latRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LATITUDE_REF)
                        val lngRef = exif.getAttribute(android.media.ExifInterface.TAG_GPS_LONGITUDE_REF)
                        android.util.Log.d("ExifGps", "gallery original URI: latStr=$latStr lngStr=$lngStr latRef=$latRef")
                        if (latStr != null && lngStr != null) {
                            var lat = parseDms(latStr); var lng = parseDms(lngStr)
                            if (latRef?.uppercase() == "S") lat = -lat
                            if (lngRef?.uppercase() == "W") lng = -lng
                            if (lat != 0.0 || lng != 0.0) { gpsLat = lat; gpsLng = lng }
                            android.util.Log.d("ExifGps", "gallery GPS: lat=$lat lng=$lng")
                        }
                    }
                } catch (e: UnsupportedOperationException) {
                    android.util.Log.d("ExifGps", "ACCESS_MEDIA_LOCATION not granted")
                } catch (e: Exception) {
                    android.util.Log.w("ExifGps", "gallery GPS read failed: ${e.message}")
                }

                pending?.success(mapOf("path" to filePath, "lat" to gpsLat, "lng" to gpsLng))
            } else {
                pending?.success(null)  // 취소
            }
        }
    }

    // ── EXIF DMS 파서 ────────────────────────────────────────

    private fun parseRatio(r: String): Double {
        val idx = r.trim().indexOf('/')
        if (idx < 0) return r.trim().toDoubleOrNull() ?: 0.0
        val n = r.substring(0, idx).trim().toDoubleOrNull() ?: 0.0
        val d = r.substring(idx + 1).trim().toDoubleOrNull() ?: 1.0
        return if (d == 0.0) 0.0 else n / d
    }

    private fun parseDms(dms: String): Double {
        val parts = dms.split(",")
        if (parts.size < 3) return 0.0
        return parseRatio(parts[0]) + parseRatio(parts[1]) / 60.0 + parseRatio(parts[2]) / 3600.0
    }

    // ── SAF 헬퍼 ─────────────────────────────────────────────

    private fun safFolder(uriString: String): DocumentFile? =
        DocumentFile.fromTreeUri(this, Uri.parse(uriString))

    private fun safReadFile(uriString: String, filename: String): String? {
        val file = safFolder(uriString)?.findFile(filename) ?: return null
        return try {
            contentResolver.openInputStream(file.uri)?.use { it.bufferedReader(Charsets.UTF_8).readText() }
        } catch (_: Exception) { null }
    }

    private fun safWriteFile(uriString: String, filename: String, content: String) {
        val folder = safFolder(uriString) ?: return
        val file = folder.findFile(filename) ?: folder.createFile("application/octet-stream", filename) ?: return
        try {
            contentResolver.openOutputStream(file.uri, "wt")?.use {
                it.write(content.toByteArray(Charsets.UTF_8))
            }
        } catch (_: Exception) {}
    }

    private fun safFileExists(uriString: String, filename: String): Boolean =
        safFolder(uriString)?.findFile(filename)?.exists() == true

    private fun safListMdFiles(uriString: String): List<String> =
        safFolder(uriString)?.listFiles()
            ?.filter { it.isFile && it.name?.endsWith(".md") == true }
            ?.mapNotNull { it.name }
            ?.sorted() ?: emptyList()

    private fun safEnsureNoMedia(uriString: String) {
        val folder = safFolder(uriString) ?: return
        if (folder.findFile(".nomedia") == null) {
            folder.createFile("application/octet-stream", ".nomedia")
        }
    }

    private fun safDeleteFile(uriString: String, filename: String) {
        safFolder(uriString)?.findFile(filename)?.delete()
    }

    private fun safRenameFile(uriString: String, oldFilename: String, newFilename: String) {
        safFolder(uriString)?.findFile(oldFilename)?.renameTo(newFilename)
    }

    private fun safGetDisplayPath(uriString: String): String {
        return try {
            val uri = Uri.parse(uriString)
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val colon = docId.indexOf(':')
            if (colon >= 0) "/storage/emulated/0/${docId.substring(colon + 1)}"
            else uriString
        } catch (_: Exception) { uriString }
    }

    // ─────────────────────────────────────────────────────────

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val mimeType = contentResolver.getType(uri) ?: "image/jpeg"
            val ext = when {
                mimeType.startsWith("video/") -> "mp4"
                mimeType.contains("png") -> "png"
                else -> "jpg"
            }
            val dest = File(cacheDir, "gallery_${System.currentTimeMillis()}.$ext")
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
