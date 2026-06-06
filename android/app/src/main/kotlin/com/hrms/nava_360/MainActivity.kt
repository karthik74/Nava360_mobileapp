package com.hrms.nava_360

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "app/downloads"
    private val storageReqCode = 9911

    // Held while we wait for the runtime storage-permission dialog (API < 29).
    private var pendingSave: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName")
                        val bytes = call.argument<ByteArray>("bytes")
                        val mimeType = call.argument<String>("mimeType")
                            ?: "application/octet-stream"
                        if (fileName == null || bytes == null) {
                            result.error("BAD_ARGS", "fileName and bytes are required", null)
                        } else {
                            saveOrRequest(fileName, bytes, mimeType, result)
                        }
                    }
                    "openDownload" -> {
                        val uriString = call.argument<String>("uri")
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                        } else {
                            try {
                                openUri(uriString, mimeType)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveOrRequest(
        fileName: String,
        bytes: ByteArray,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        // API 29+ uses scoped MediaStore — no runtime permission required.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                result.success(saveViaMediaStore(fileName, bytes, mimeType))
            } catch (e: Exception) {
                result.error("SAVE_FAILED", e.message, null)
            }
            return
        }
        // Legacy (<= API 28): write to public Downloads with WRITE_EXTERNAL_STORAGE.
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            try {
                result.success(saveLegacy(fileName, bytes))
            } catch (e: Exception) {
                result.error("SAVE_FAILED", e.message, null)
            }
        } else {
            pendingResult = result
            pendingSave = {
                try {
                    pendingResult?.success(saveLegacy(fileName, bytes))
                } catch (e: Exception) {
                    pendingResult?.error("SAVE_FAILED", e.message, null)
                }
            }
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                storageReqCode,
            )
        }
    }

    private fun saveViaMediaStore(fileName: String, bytes: ByteArray, mimeType: String): String {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val collection =
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create a Downloads entry")
        resolver.openOutputStream(uri).use { out ->
            (out ?: throw IllegalStateException("Could not open output stream")).write(bytes)
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(fileName: String, bytes: ByteArray): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, fileName)
        FileOutputStream(file).use { it.write(bytes) }
        return file.absolutePath
    }

    private fun openUri(uriString: String, mimeType: String) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uriString), mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == storageReqCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                pendingSave?.invoke()
            } else {
                pendingResult?.error("PERMISSION_DENIED", "Storage permission denied", null)
            }
            pendingSave = null
            pendingResult = null
        }
    }
}
