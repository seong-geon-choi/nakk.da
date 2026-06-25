package com.sgchoisg.nakkda

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
import org.json.JSONArray

class MainActivity : FlutterActivity() {

    private val mediaChannelName = "com.sgchoisg.nakkda/media"
    private val accessibilityChannelName = "com.sgchoisg.nakkda/accessibility"
    private val arChannelName = "com.sgchoisg.nakkda/ar"
    private val safChannelName = "com.sgchoisg.nakkda/saf"

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
                        val lowerName = sourceFile.name.lowercase()
                        val isVideo = lowerName.endsWith(".mp4") || lowerName.endsWith(".mov") ||
                            lowerName.endsWith(".3gp") || lowerName.endsWith(".mkv")
                        val mimeType: String
                        val ext: String
                        val mediaUri: android.net.Uri
                        val displayNameKey: String
                        val mimeTypeKey: String
                        val relativePathKey: String
                        val isPendingKey: String
                        val dataKey: String
                        if (isVideo) {
                            mimeType = "video/mp4"
                            ext = ".mp4"
                            mediaUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                            displayNameKey = MediaStore.Video.Media.DISPLAY_NAME
                            mimeTypeKey = MediaStore.Video.Media.MIME_TYPE
                            relativePathKey = MediaStore.Video.Media.RELATIVE_PATH
                            isPendingKey = MediaStore.Video.Media.IS_PENDING
                            dataKey = MediaStore.Video.Media.DATA
                        } else {
                            val isPng = lowerName.endsWith(".png")
                            mimeType = if (isPng) "image/png" else "image/jpeg"
                            ext = if (isPng) ".png" else ".jpg"
                            mediaUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                            displayNameKey = MediaStore.Images.Media.DISPLAY_NAME
                            mimeTypeKey = MediaStore.Images.Media.MIME_TYPE
                            relativePathKey = MediaStore.Images.Media.RELATIVE_PATH
                            isPendingKey = MediaStore.Images.Media.IS_PENDING
                            dataKey = MediaStore.Images.Media.DATA
                        }
                        val dateStr = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                        val displayName = "NAKKDA_$dateStr$ext"

                        val values = ContentValues().apply {
                            put(displayNameKey, displayName)
                            put(mimeTypeKey, mimeType)
                            put(relativePathKey, "$relativePath/")
                            put(isPendingKey, 1)
                        }
                        val uri = contentResolver.insert(mediaUri, values)
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
                        values.put(isPendingKey, 0)
                        contentResolver.update(uri, values, null, null)

                        if (isVideo) {
                            // 동영상은 content URI 반환 (ExoPlayer가 file:// 경로로 접근 불가)
                            result.success(uri.toString())
                        } else {
                            var filePath: String? = null
                            contentResolver.query(
                                uri, arrayOf(dataKey), null, null, null
                            )?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    filePath = cursor.getString(cursor.getColumnIndexOrThrow(dataKey))
                                }
                            }
                            if (filePath.isNullOrEmpty()) {
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
                        }
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
                        arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.DATA),
                        "${MediaStore.Images.Media.DATE_TAKEN} BETWEEN ? AND ?",
                        arrayOf(startMs.toString(), endMs.toString()),
                        "${MediaStore.Images.Media.DATE_TAKEN} ASC"
                    )?.use { cursor ->
                        android.util.Log.d("ScanPhotos", "matched=${cursor.count}")
                        val idCol = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                        val dtCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
                        val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                        while (cursor.moveToNext()) {
                            val id = cursor.getLong(idCol)
                            val dateTaken = cursor.getLong(dtCol)
                            if (dateTaken == 0L) continue
                            val filePath = if (dataCol >= 0) cursor.getString(dataCol) else null
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
                            items.add(mapOf("contentUri" to contentUri.toString(), "path" to filePath, "dateTaken" to dateTaken, "lat" to gpsLat, "lng" to gpsLng))
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
                            call.argument<String>("wmJson")?.let { putExtra("wmJson", it) }
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
                    "ensureDefaultFolder" -> {
                        val rel = call.argument<String>("relativePath") ?: "Documents/nakkda"
                        result.success(ensurePublicFolder(rel))
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
                    "getFilesModifiedTimes" -> {
                        val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARG", "uri missing", null)
                        // 폴더를 단일 쿼리로 열거해 전체 자식의 수정시간을 한 번에 가져온다.
                        // (파일별 findFile = 매번 폴더 전체 스캔이라 O(N^2)로 느렸음)
                        result.success(safChildModifiedTimes(uri))
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
                    "writePhotoBytes" -> {
                        val folderUri = call.argument<String>("folderUri") ?: return@setMethodCallHandler result.error("ARG", "folderUri missing", null)
                        val filename  = call.argument<String>("filename")  ?: return@setMethodCallHandler result.error("ARG", "filename missing", null)
                        val bytes     = call.argument<ByteArray>("bytes")  ?: return@setMethodCallHandler result.error("ARG", "bytes missing", null)
                        try {
                            val root = DocumentFile.fromTreeUri(this, Uri.parse(folderUri))
                            val sub  = root?.findFile("photos") ?: root?.createDirectory("photos")
                            val mime = if (filename.endsWith(".mp4")) "video/mp4" else "image/jpeg"
                            val dest = sub?.findFile(filename) ?: sub?.createFile(mime, filename)
                            if (dest == null) { result.error("CREATE_FAILED", "cannot create file", null); return@setMethodCallHandler }
                            contentResolver.openOutputStream(dest.uri)?.use { out -> out.write(bytes) }
                            result.success(null)
                        } catch (e: Exception) { result.error("WRITE_ERROR", e.message, null) }
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

        // ── 위치 트래킹 채널 ─────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sgchoisg.nakkda/tracking")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startTracking" -> {
                        val intervalMeters = call.argument<Int>("intervalMeters") ?: 100
                        if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
                                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            LocationTrackingService.start(this, intervalMeters)
                        }
                        result.success(null)
                    }
                    "stopTracking" -> {
                        LocationTrackingService.stop(this)
                        result.success(null)
                    }
                    "isTracking" -> {
                        val active = getSharedPreferences(
                            LocationTrackingService.PREFS_NAME, Context.MODE_PRIVATE
                        ).getBoolean(LocationTrackingService.PREFS_ACTIVE_KEY, false)
                        result.success(active)
                    }
                    "getAndClearTrackPoints" -> {
                        val prefs = getSharedPreferences(
                            LocationTrackingService.PREFS_NAME, Context.MODE_PRIVATE
                        )
                        val list = synchronized(LocationTrackingService.pendingLock) {
                            val json = prefs.getString(LocationTrackingService.PREFS_PENDING_KEY, "[]") ?: "[]"
                            val arr = try { JSONArray(json) } catch (_: Exception) { JSONArray() }
                            val items = mutableListOf<String>()
                            for (i in 0 until arr.length()) items.add(arr.getString(i))
                            prefs.edit().remove(LocationTrackingService.PREFS_PENDING_KEY).commit()
                            items
                        }
                        result.success(list)
                    }
                    "commuteSync" -> {
                        val prefs = getSharedPreferences(
                            CommuteAlarmService.PREFS_NAME, Context.MODE_PRIVATE)
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val pins = call.argument<List<Map<String, Any>>>("pins") ?: emptyList()
                        val pinsJson = JSONArray()
                        for (p in pins) {
                            val lat = (p["lat"] as? Number)?.toDouble()
                            val lng = (p["lng"] as? Number)?.toDouble()
                            if (lat != null && lng != null) pinsJson.put("$lat,$lng")
                        }
                        prefs.edit()
                            .putBoolean(CommuteAlarmService.KEY_ENABLED, enabled)
                            .putInt(CommuteAlarmService.KEY_RADIUS,
                                call.argument<Int>("radius") ?: 200)
                            .putString(CommuteAlarmService.KEY_SOUND,
                                call.argument<String>("sound") ?: "systemDefault")
                            .putString(CommuteAlarmService.KEY_PINS, pinsJson.toString())
                            .putInt(CommuteAlarmService.KEY_AM_START,
                                call.argument<Int>("amStart") ?: 420)
                            .putInt(CommuteAlarmService.KEY_AM_END,
                                call.argument<Int>("amEnd") ?: 540)
                            .putInt(CommuteAlarmService.KEY_PM_START,
                                call.argument<Int>("pmStart") ?: 1080)
                            .putInt(CommuteAlarmService.KEY_PM_END,
                                call.argument<Int>("pmEnd") ?: 1200)
                            .putInt(CommuteAlarmService.KEY_CUSTOM_START,
                                call.argument<Int>("customStart") ?: 600)
                            .putInt(CommuteAlarmService.KEY_CUSTOM_END,
                                call.argument<Int>("customEnd") ?: 720)
                            .putBoolean(CommuteAlarmService.KEY_AM_ENABLED,
                                call.argument<Boolean>("amEnabled") ?: true)
                            .putBoolean(CommuteAlarmService.KEY_PM_ENABLED,
                                call.argument<Boolean>("pmEnabled") ?: true)
                            .putBoolean(CommuteAlarmService.KEY_CUSTOM_ENABLED,
                                call.argument<Boolean>("customEnabled") ?: false)
                            .putBoolean(CommuteAlarmService.KEY_WEEKDAYS_ONLY,
                                call.argument<Boolean>("weekdaysOnly") ?: true)
                            .apply()
                        val hasLoc = checkSelfPermission(
                            android.Manifest.permission.ACCESS_FINE_LOCATION) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED ||
                            checkSelfPermission(
                                android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                        if (enabled && pinsJson.length() > 0 && hasLoc) {
                            CommuteAlarmService.start(this)
                        } else {
                            CommuteAlarmService.stop(this)
                        }
                        result.success(null)
                    }
                    "commuteStop" -> {
                        getSharedPreferences(CommuteAlarmService.PREFS_NAME, Context.MODE_PRIVATE)
                            .edit().putBoolean(CommuteAlarmService.KEY_ENABLED, false).apply()
                        CommuteAlarmService.stop(this)
                        result.success(null)
                    }
                    "setQuickLaunchMode" -> {
                        val mode = call.argument<String>("mode") ?: "volume"
                        val threshold =
                            (call.argument<Double>("shakeThresholdG") ?: 3.5).toFloat()
                        getSharedPreferences(LocationTrackingService.PREFS_NAME, Context.MODE_PRIVATE)
                            .edit()
                            .putString(LocationTrackingService.PREFS_QUICK_LAUNCH_MODE_KEY, mode)
                            .putFloat(LocationTrackingService.PREFS_SHAKE_THRESHOLD_KEY, threshold)
                            .apply()
                        VoiceRecordForegroundService.start(this, mode, threshold)
                        result.success(null)
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
                val posX = if (data.hasExtra(ArMeasureActivity.EXTRA_POS_X))
                    data.getFloatExtra(ArMeasureActivity.EXTRA_POS_X, 1f).toDouble() else null
                val posY = if (data.hasExtra(ArMeasureActivity.EXTRA_POS_Y))
                    data.getFloatExtra(ArMeasureActivity.EXTRA_POS_Y, 1f).toDouble() else null
                pending?.success(mapOf(
                    "path" to path, "distanceCm" to dist, "applyWatermark" to applyWm,
                    "posX" to posX, "posY" to posY))
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

    /// 공용 저장소에 폴더(예: Documents/nakkda)가 없으면 생성한다.
    /// SAF 픽커가 해당 폴더에서 열려 사용자가 권한 부여만 하면 되도록 하기 위함.
    /// API 29+ : MediaStore로 .keep 마커 파일을 만들어 폴더 생성 (추가 권한 불필요)
    /// API 26~28 : 레거시 File.mkdirs
    private fun ensurePublicFolder(relPath: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (publicFolderExists(relPath)) return true
                val values = ContentValues().apply {
                    put(MediaStore.Files.FileColumns.DISPLAY_NAME, ".keep")
                    put(MediaStore.Files.FileColumns.RELATIVE_PATH, relPath.trimEnd('/'))
                    put(MediaStore.Files.FileColumns.MIME_TYPE, "application/octet-stream")
                }
                contentResolver.insert(MediaStore.Files.getContentUri("external"), values) != null
            } else {
                @Suppress("DEPRECATION")
                val dir = File(Environment.getExternalStorageDirectory(), relPath)
                dir.exists() || dir.mkdirs()
            }
        } catch (_: Exception) { false }
    }

    private fun publicFolderExists(relPath: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val rel = relPath.trimEnd('/') + "/"
                contentResolver.query(
                    MediaStore.Files.getContentUri("external"),
                    arrayOf(MediaStore.Files.FileColumns._ID),
                    "${MediaStore.Files.FileColumns.RELATIVE_PATH}=?",
                    arrayOf(rel), null
                )?.use { it.count > 0 } ?: false
            } else {
                @Suppress("DEPRECATION")
                File(Environment.getExternalStorageDirectory(), relPath).exists()
            }
        } catch (_: Exception) { false }
    }

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

    // 폴더 자식을 단일 쿼리로 열거(.md 파일명만, 정렬).
    // DocumentFile.listFiles + 자식별 name 쿼리(O(N))보다 빠르다.
    private fun safListMdFiles(uriString: String): List<String> {
        val names = ArrayList<String>()
        try {
            val tree = Uri.parse(uriString)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree))
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null
            )?.use { c ->
                val nameCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (c.moveToNext()) {
                    val name = c.getString(nameCol) ?: continue
                    if (name.endsWith(".md")) names.add(name)
                }
            }
        } catch (_: Exception) {}
        names.sort()
        return names
    }

    // 폴더 자식 전체의 수정시간(name -> epochMillis)을 단일 쿼리로 반환.
    private fun safChildModifiedTimes(uriString: String): Map<String, Long> {
        val times = HashMap<String, Long>()
        try {
            val tree = Uri.parse(uriString)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree))
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                ),
                null, null, null
            )?.use { c ->
                val nameCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val modCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                while (c.moveToNext()) {
                    val name = c.getString(nameCol) ?: continue
                    val ms = if (c.isNull(modCol)) 0L else c.getLong(modCol)
                    if (ms > 0L) times[name] = ms
                }
            }
        } catch (_: Exception) {}
        return times
    }

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
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            val mode = LocationTrackingService.getQuickLaunchMode(this)
            VoiceRecordForegroundService.start(
                this, mode, LocationTrackingService.getShakeThresholdG(this))
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
