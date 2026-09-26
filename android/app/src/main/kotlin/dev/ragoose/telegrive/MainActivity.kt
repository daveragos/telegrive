package dev.ragoose.telegrive

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var pendingWriteAccess: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "telegrive/device_storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> result.success(StatFs(filesDir.path).availableBytes)
                    "ensureWriteAccess" -> ensureWriteAccess(result)
                    "saveToDownloads" -> {
                        val source = call.argument<String>("source")!!
                        val relativePath = call.argument<String>("relativePath")!!
                        val name = call.argument<String>("name")!!
                        val mimeType = call.argument<String>("mimeType")!!
                        io.execute {
                            try {
                                val saved = saveToDownloads(File(source), relativePath, name, mimeType)
                                main.post { result.success(saved) }
                            } catch (e: Exception) {
                                main.post { result.error("save_failed", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    /**
     * Copies [source] to `relativePath/name` in shared storage and returns its
     * path. A file already there with the same name and size is taken to be
     * this one; any other clash gets a numbered name.
     */
    private fun saveToDownloads(
        source: File,
        relativePath: String,
        name: String,
        mimeType: String,
    ): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStorageDirectory(), relativePath)
            if (!dir.isDirectory && !dir.mkdirs()) throw IOException("Can't create $relativePath")
            var target = File(dir, name)
            var n = 1
            while (target.exists()) {
                if (target.length() == source.length()) return target.path
                target = File(dir, numbered(name, n++))
            }
            source.copyTo(target)
            MediaScannerConnection.scanFile(this, arrayOf(target.path), arrayOf(mimeType), null)
            return target.path
        }

        // MediaStore needs no permission for an app's own files in Download,
        // and numbers clashing names itself.
        val folder = "$relativePath/"
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        @Suppress("DEPRECATION")
        val pathColumn = arrayOf(MediaStore.MediaColumns.DATA)
        contentResolver.query(
            collection,
            pathColumn,
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND " +
                "${MediaStore.MediaColumns.SIZE}=?",
            arrayOf(folder, name, source.length().toString()),
            null,
        )?.use { if (it.moveToFirst()) return it.getString(0) ?: "$folder$name" }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IOException("Android refused to create $name")
        try {
            val output = contentResolver.openOutputStream(uri)
                ?: throw IOException("Can't write $name")
            output.use { out -> source.inputStream().use { it.copyTo(out, 1 shl 20) } }
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            contentResolver.update(uri, done, null, null)
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        contentResolver.query(uri, pathColumn, null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.let { path -> return path }
        }
        return "$folder$name"
    }

    /** Android 9 and older only write to shared storage with permission. */
    private fun ensureWriteAccess(result: MethodChannel.Result) {
        val permission = Manifest.permission.WRITE_EXTERNAL_STORAGE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingWriteAccess?.success(false)
        pendingWriteAccess = result
        requestPermissions(arrayOf(permission), WRITE_ACCESS_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != WRITE_ACCESS_REQUEST) return
        pendingWriteAccess?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingWriteAccess = null
    }

    private companion object {
        const val WRITE_ACCESS_REQUEST = 7301

        /** `photo.jpg`, 2 → `photo (2).jpg`. */
        fun numbered(name: String, n: Int): String {
            val dot = name.lastIndexOf('.')
            return if (dot <= 0) "$name ($n)" else "${name.substring(0, dot)} ($n)${name.substring(dot)}"
        }
    }
}
