package dev.ragoose.telegrive

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

// A FragmentActivity, which local_auth needs for the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var pendingWriteAccess: MethodChannel.Result? = null

    /** Files other apps shared in, copied into the cache, until Dart takes them. */
    private val pendingShares = mutableListOf<Map<String, Any>>()
    private var shareChannel: MethodChannel? = null

    /** Dart's listener on the network, and the Android callback feeding it. */
    private var networkSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val connectivity: ConnectivityManager by lazy {
        getSystemService(ConnectivityManager::class.java)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A recreated activity has already handled its intent.
        if (savedInstanceState == null) receiveShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receiveShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        shareChannel = MethodChannel(messenger, "telegrive/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShared" -> result.success(
                        synchronized(pendingShares) { pendingShares.toList().also { pendingShares.clear() } },
                    )
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(messenger, "telegrive/security").setMethodCallHandler { call, result ->
            when (call.method) {
                "setPrivateRecents" -> {
                    // Keeps the app's content out of the recents screen while the
                    // app lock is on (Android 13+).
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        setRecentsScreenshotEnabled(call.arguments != true)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "telegrive/device_storage")
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
        // Our own callback rather than connectivity_plus: that plugin folds a
        // move between two Wi-Fi networks into one "wifi", so a hotspot taking
        // over from home Wi-Fi would never reach Dart.
        EventChannel(messenger, "telegrive/network").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopWatchingNetwork()
                    networkSink = events
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) = emitNetwork()
                        override fun onLost(network: Network) = emitNetwork()
                        override fun onCapabilitiesChanged(
                            network: Network,
                            capabilities: NetworkCapabilities,
                        ) = emitNetwork()
                    }
                    networkCallback = callback
                    connectivity.registerDefaultNetworkCallback(callback)
                    emitNetwork()
                }

                override fun onCancel(arguments: Any?) = stopWatchingNetwork()
            },
        )
    }

    override fun onDestroy() {
        stopWatchingNetwork()
        io.shutdown()
        super.onDestroy()
    }

    /**
     * Tells Dart whether the phone is online and whether its bytes are paid
     * for. Android calls back on its own thread; the sink is only safe on the
     * main one.
     */
    private fun emitNetwork() {
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val online = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val metered = connectivity.isActiveNetworkMetered
        main.post { networkSink?.success(mapOf("online" to online, "metered" to metered)) }
    }

    private fun stopWatchingNetwork() {
        networkSink = null
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            connectivity.unregisterNetworkCallback(callback)
        } catch (e: IllegalArgumentException) {
            // Android had already let go of it.
        }
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

    /**
     * Copies what another app shared into the cache, where the upload queue
     * can read it once the person picks a folder. Plain text becomes a note.
     */
    private fun receiveShare(intent: Intent?) {
        if (intent == null) return
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(streamOf(intent))
            Intent.ACTION_SEND_MULTIPLE -> streamsOf(intent)
            else -> return
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (uris.isEmpty() && text.isNullOrBlank()) return
        io.execute {
            val copied = if (uris.isNotEmpty()) {
                uris.mapNotNull { copyShared(it) }
            } else {
                listOfNotNull(saveNote(text!!, intent.getStringExtra(Intent.EXTRA_SUBJECT)))
            }
            synchronized(pendingShares) { pendingShares.addAll(copied) }
            main.post { shareChannel?.invokeMethod("sharedAvailable", null) }
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamsOf(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        } ?: emptyList()

    private fun sharedDir(): File =
        File(cacheDir, "shared/${System.nanoTime()}").apply { mkdirs() }

    private fun copyShared(uri: Uri): Map<String, Any>? = try {
        var name: String? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0)
        }
        val clean = (name ?: uri.lastPathSegment ?: "Shared file")
            .replace(Regex("[\\\\/:\\u0000-\\u001f]"), "_")
            .ifBlank { "Shared file" }
        val target = File(sharedDir(), clean)
        val input = contentResolver.openInputStream(uri) ?: throw IOException("Can't read $uri")
        input.use { source -> target.outputStream().use { source.copyTo(it, 1 shl 20) } }
        mapOf("path" to target.path, "name" to clean, "size" to target.length())
    } catch (e: Exception) {
        null
    }

    private fun saveNote(text: String, subject: String?): Map<String, Any>? = try {
        val stamp = SimpleDateFormat("yyyy-MM-dd HH.mm", Locale.US).format(Date())
        val title = subject?.takeIf { it.isNotBlank() }?.take(60)?.replace(Regex("[\\\\/:]"), "_")
        val target = File(sharedDir(), "${title ?: "Note $stamp"}.txt")
        target.writeText(text)
        mapOf("path" to target.path, "name" to target.name, "size" to target.length())
    } catch (e: Exception) {
        null
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
