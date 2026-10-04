package dev.ragoose.telegrive

import android.Manifest
import android.app.ActivityManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
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
import android.os.PowerManager
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import dev.ragoose.telegrive.picker.DriveDocumentsProvider
import io.flutter.embedding.android.FlutterFragment
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

    /**
     * Publishes the share targets and reports their use one call at a
     * time, in the order Dart sends them, so the last list sent, such as
     * the empty one on sign-out or with app lock on, is the one the share
     * sheet keeps.
     */
    private val shortcuts = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingWriteAccess: MethodChannel.Result? = null

    /**
     * What other apps shared in (cache copies, gallery originals, or files
     * with no room to copy), and captures that came back with no Dart call
     * waiting, until Dart takes them.
     */
    private val pendingShares = mutableListOf<Map<String, Any>>()
    private var shareChannel: MethodChannel? = null

    /** A tapped tg://proxy or tg://socks link, until Dart takes it. */
    private var pendingLink: String? = null
    private var linkChannel: MethodChannel? = null

    /** Follows the default network while Dart listens on telegrive/network. */
    private var networkWatcher: NetworkWatcher? = null

    /**
     * The scanner, the camera and the folder picker come back as activity
     * results, and Android only registers for those before the activity is
     * started. Both channels are created at the top of onCreate, ahead of
     * super.onCreate: a recreated activity re-attaches its Flutter fragment
     * in there, which runs configureFlutterEngine, and that attaches them.
     * They are created in the same order every time, because a result that
     * outlives the process finds its launcher by that order.
     */
    private lateinit var capture: CaptureChannel
    private lateinit var folders: FoldersChannel

    /**
     * Whether this activity is the first one its intent starts, so the
     * intent's route, share or link is acted on. Android hands a task's first
     * intent back, extras and all, when Recents restarts a closed app
     * (flagged as launched from history) and when it recreates an activity
     * whose process it killed (with saved state); the intent has been acted
     * on by then, and acting again would open Transfers or take the same
     * share in once more.
     */
    private var firstStart = false

    override fun onCreate(savedInstanceState: Bundle?) {
        capture = CaptureChannel(this, io, main) { addShared(listOf(it)) }
        folders = FoldersChannel(this, io, main)
        firstStart = savedInstanceState == null &&
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
        if (savedInstanceState != null) forgetRestoredRoute()
        super.onCreate(savedInstanceState)
        capture.restoreState(savedInstanceState)
        if (firstStart) {
            receiveShare(intent)
            receiveLink(intent)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        capture.saveState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receiveShare(intent)
        receiveLink(intent)
    }

    /**
     * The route the launch intent asks for, as the transfer notification's
     * does, or null for the default. Only a [firstStart] has one, so an app
     * reopened from Recents opens the way a plain launch does.
     */
    override fun getInitialRoute(): String? = if (firstStart) super.getInitialRoute() else null

    /**
     * A recreated activity gets its FlutterFragment back from saved state
     * holding the route it was first created with (the fragment's
     * ARG_INITIAL_ROUTE), and the fragment starts its engine from that when
     * it attaches, inside super.onCreate, without asking [getInitialRoute].
     * The route is dropped just before the fragment attaches, so an app that
     * Android killed and brought back opens the way a plain launch does.
     */
    private fun forgetRestoredRoute() {
        supportFragmentManager.registerFragmentLifecycleCallbacks(
            object : FragmentManager.FragmentLifecycleCallbacks() {
                override fun onFragmentPreAttached(fm: FragmentManager, f: Fragment, context: Context) {
                    if (f is FlutterFragment) f.arguments?.remove("initial_route")
                }
            },
            false,
        )
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
                    "setTargets" -> {
                        @Suppress("UNCHECKED_CAST")
                        val targets = (call.arguments as? List<Map<String, String>>).orEmpty()
                        shortcuts.execute {
                            try {
                                ShareTargets.publish(this@MainActivity, targets)
                                main.post { result.success(null) }
                            } catch (e: Exception) {
                                main.post { result.error("targets_failed", e.message, null) }
                            }
                        }
                    }
                    "reportTarget" -> {
                        val id = call.argument<String>("id")
                        shortcuts.execute {
                            try {
                                if (id != null) ShareTargets.reportUsed(this@MainActivity, id)
                                main.post { result.success(null) }
                            } catch (e: Exception) {
                                main.post { result.error("report_failed", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        linkChannel = MethodChannel(messenger, "telegrive/links").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLink" -> result.success(pendingLink.also { pendingLink = null })
                    else -> result.notImplemented()
                }
            }
        }
        capture.attach(messenger)
        folders.attach(messenger)
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
        MethodChannel(messenger, "telegrive/picker").setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val on = call.arguments == true
                    io.execute {
                        try {
                            setPickerEnabled(on)
                            main.post { result.success(null) }
                        } catch (e: Exception) {
                            main.post { result.error("picker_failed", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "telegrive/device_storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> result.success(StatFs(filesDir.path).availableBytes)
                    "totalBytes" -> result.success(StatFs(filesDir.path).totalBytes)
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
        MethodChannel(messenger, "telegrive/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "profile" -> result.success(deviceProfile())
                "deviceInfo" -> result.success(deviceInfo())
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "telegrive/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "durationMs" -> {
                    val path = call.argument<String>("path")
                    io.execute {
                        val ms = path?.let { durationMs(it) }
                        main.post { result.success(ms) }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "telegrive/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> result.success(
                    openSettings(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            null
                        },
                        appDetailsSettings(),
                    ),
                )
                "ignoringBatteryOptimizations" -> result.success(
                    try {
                        getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
                    } catch (e: Exception) {
                        null
                    },
                )
                "openBatterySettings" -> result.success(
                    openSettings(
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                        appDetailsSettings(),
                    ),
                )
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "telegrive/network").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopWatchingNetwork()
                    val watcher = NetworkWatcher(events)
                    networkWatcher = watcher
                    watcher.emit()
                    try {
                        watcher.connectivity.registerDefaultNetworkCallback(watcher)
                    } catch (e: RuntimeException) {
                        // Some phones refuse the callback; Dart keeps the state it
                        // was just sent.
                    }
                }

                override fun onCancel(arguments: Any?) = stopWatchingNetwork()
            },
        )
    }

    override fun onDestroy() {
        stopWatchingNetwork()
        io.shutdown()
        shortcuts.shutdown()
        super.onDestroy()
    }

    /**
     * Sends Dart whether the phone is online and whether its network is
     * metered, whenever the default network changes. Android marks a phone's
     * hotspot as metered, so it counts as mobile data. A callback of our own,
     * because connectivity_plus reports a move from one Wi-Fi to another as
     * no change at all.
     */
    private inner class NetworkWatcher(private val events: EventChannel.EventSink) :
        ConnectivityManager.NetworkCallback() {
        val connectivity: ConnectivityManager = getSystemService(ConnectivityManager::class.java)

        override fun onAvailable(network: Network) = emit()

        override fun onLost(network: Network) = emit()

        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = emit()

        /**
         * Reads the state afresh. Callbacks arrive on Android's own thread,
         * where an exception would end the app, and the sink is main only.
         * Android 11 can refuse the read with a SecurityException that has
         * nothing to do with Telegrive; nothing is sent then, and the next
         * change sends the state again.
         */
        fun emit() {
            val state = try {
                val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                val online = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
                // Android calls having no network metered. Being offline isn't mobile
                // data, so a transfer waiting for the connection isn't held for Wi-Fi.
                mapOf("online" to online, "metered" to (online && connectivity.isActiveNetworkMetered))
            } catch (e: RuntimeException) {
                return
            }
            main.post { if (networkWatcher === this) events.success(state) }
        }
    }

    private fun stopWatchingNetwork() {
        val watcher = networkWatcher ?: return
        networkWatcher = null
        try {
            watcher.connectivity.unregisterNetworkCallback(watcher)
        } catch (e: RuntimeException) {
            // It was never registered, or Android 11 refused, as it can with
            // the network reads.
        }
    }

    /**
     * Starts the first of [intents] this phone has. Some phones leave a
     * settings page out, and the app's own page is always there to fall back on.
     */
    private fun openSettings(vararg intents: Intent?): Boolean {
        for (intent in intents.filterNotNull()) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: RuntimeException) {
                continue
            }
        }
        return false
    }

    private fun appDetailsSettings(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))

    /**
     * Shows the drive in Android's file picker, or takes it out, and tells
     * the picker its roots changed so an open one updates. Only the
     * component is switched here: the provider reads the index with
     * Android's own SQLite, which must never open it in this process, where
     * Drift's copy of SQLite holds it.
     */
    private fun setPickerEnabled(on: Boolean) {
        val component = ComponentName(this, DriveDocumentsProvider::class.java)
        val state = if (on) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        if (packageManager.getComponentEnabledSetting(component) == state) return
        packageManager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        contentResolver.notifyChange(DocumentsContract.buildRootsUri("$packageName.documents"), null)
    }

    /** How much memory the phone has, so a small one can use less of it. */
    private fun deviceProfile(): Map<String, Any>? = try {
        val activities = getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo().also { activities.getMemoryInfo(it) }
        mapOf(
            "lowRam" to activities.isLowRamDevice,
            "memoryClassMb" to activities.memoryClass,
            "totalRamBytes" to memory.totalMem,
        )
    } catch (e: Exception) {
        null
    }

    /**
     * What Telegram's Devices list calls this session: "Google Pixel 8" and
     * "Android 15". A model that already names its maker keeps its own name.
     */
    private fun deviceInfo(): Map<String, String> {
        val maker = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.titlecase(Locale.ROOT) }
        val model = Build.MODEL.orEmpty()
        val named = if (maker.isBlank() || model.startsWith(maker, ignoreCase = true)) model else "$maker $model"
        return mapOf("model" to named, "system" to "Android ${Build.VERSION.RELEASE}")
    }

    /** A video or audio file's length from its own header, or null when it can't be read. */
    private fun durationMs(path: String): Long? = try {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } finally {
            runCatching { retriever.release() }
        }
    } catch (e: Exception) {
        null
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
     * Takes what another app shared, for the upload queue to send once the
     * person picks a folder: a gallery file from where it is, anything else
     * as a copy in the cache. Plain text becomes a note. A share sent to one
     * of the drive's folders in the share sheet carries that folder's id,
     * so it can go straight there.
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
        val folderId = ShareTargets.folderOf(intent)
        io.execute {
            val copied = if (uris.isNotEmpty()) {
                uris.mapNotNull { copyShared(it) }
            } else {
                listOfNotNull(saveNote(text!!, intent.getStringExtra(Intent.EXTRA_SUBJECT)))
            }
            addShared(if (folderId == null) copied else copied.map { it + ("folderId" to folderId) })
        }
    }

    /**
     * Queues files for Dart to take and says so: what other apps shared in,
     * and a capture whose Dart call died with its engine, which then arrives
     * through the same Save to Telegrive sheet.
     */
    private fun addShared(items: List<Map<String, Any>>) {
        synchronized(pendingShares) { pendingShares.addAll(items) }
        main.post { shareChannel?.invokeMethod("sharedAvailable", null) }
    }

    /** Keeps a tapped proxy link for Dart, which asks before connecting through it. */
    private fun receiveLink(intent: Intent?) {
        val link = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.data ?: return
        if (link.scheme != "tg" || link.host !in PROXY_HOSTS) return
        pendingLink = link.toString()
        linkChannel?.invokeMethod("linkAvailable", null)
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

    /**
     * One shared file for Dart. A gallery file Telegrive may read by its own
     * permission is sent from where it is ("owned" false, so it is never
     * deleted). Anything else is copied, unless the copy would leave the
     * phone with less than [ROOM_MARGIN] free: then only its size and the
     * free space go back ("tooBig"), and nothing is kept. A copy is written
     * under a ".part" name and renamed when complete, so a copy cut short is
     * never taken for the file.
     */
    private fun copyShared(uri: Uri): Map<String, Any>? {
        try {
            val (name, size) = describeShared(uri)
            val clean = (name ?: uri.lastPathSegment ?: "Shared file")
                .replace(Regex("[\\\\/:\\u0000-\\u001f]"), "_")
                .ifBlank { "Shared file" }

            val direct = directPath(uri)?.let(::File)?.takeIf { it.canRead() && it.length() == size }
            if (direct != null) {
                return mapOf("path" to direct.path, "name" to clean, "size" to direct.length(), "owned" to false)
            }
            if (size != null && StatFs(cacheDir.path).availableBytes < size + ROOM_MARGIN) {
                return tooBig(clean, size)
            }

            val dir = sharedDir()
            val target = File(dir, clean)
            val partial = File(dir, "$clean.part")
            try {
                copyLeavingRoom(uri, partial)
                if (!partial.renameTo(target)) throw IOException("Can't finish the copy of $clean")
            } catch (e: Exception) {
                dir.deleteRecursively()
                if (e is NoRoom) return tooBig(clean, size ?: e.atLeast)
                throw e
            }
            return mapOf("path" to target.path, "name" to clean, "size" to target.length(), "owned" to true)
        } catch (e: Exception) {
            return null
        }
    }

    /**
     * The name and size the sender gives for [uri], either of which can be
     * missing. Some providers leave a column out or refuse the query, and
     * the file can still be read.
     */
    private fun describeShared(uri: Uri): Pair<String?, Long?> = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use {
                if (!it.moveToFirst()) return@use null
                val name = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val size = it.getColumnIndex(OpenableColumns.SIZE)
                Pair(
                    if (name < 0 || it.isNull(name)) null else it.getString(name),
                    if (size < 0 || it.isNull(size)) null else it.getLong(size),
                )
            } ?: (null to null)
    } catch (e: Exception) {
        null to null
    }

    /**
     * A shared file there is no room to copy, with the space the phone has
     * once any partial copy is gone. When the sender didn't give a size,
     * [size] is what had been read when the copy stopped, so at least that.
     */
    private fun tooBig(name: String, size: Long): Map<String, Any> =
        mapOf("name" to name, "size" to size, "free" to StatFs(cacheDir.path).availableBytes, "tooBig" to true)

    /**
     * Copies [uri] into [target] a megabyte at a time, and stops with
     * [NoRoom] before a write would leave the phone less than [ROOM_MARGIN]
     * free. That also covers a sender that never said how big the file is.
     */
    private fun copyLeavingRoom(uri: Uri, target: File) {
        val input = contentResolver.openInputStream(uri) ?: throw IOException("Can't read $uri")
        input.use { source ->
            target.outputStream().use { out ->
                val buffer = ByteArray(1 shl 20)
                var copied = 0L
                while (true) {
                    val read = source.read(buffer)
                    if (read < 0) return
                    if (StatFs(cacheDir.path).availableBytes < read + ROOM_MARGIN) throw NoRoom(copied + read)
                    out.write(buffer, 0, read)
                    copied += read
                }
            }
        }
    }

    /**
     * The file behind a MediaStore [uri], from the gallery itself or from the
     * system file picker's media documents, when Telegrive's own permission
     * covers it. Read by path on the share's grant alone, it could stop
     * being readable once the grant ends, and an upload still in the queue
     * would lose its file. Null for anything else.
     */
    @Suppress("DEPRECATION")
    private fun directPath(uri: Uri): String? = try {
        val media = when (uri.authority) {
            MediaStore.AUTHORITY -> uri
            MEDIA_DOCUMENTS -> DocumentsContract.getDocumentId(uri).substringAfter(':').toLongOrNull()
                ?.let { MediaStore.Files.getContentUri("external", it) }
            else -> null
        }
        media?.let {
            contentResolver.query(
                it,
                arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.MIME_TYPE),
                null,
                null,
                null,
            )?.use { row -> if (row.moveToFirst() && mayReadMedia(row.getString(1))) row.getString(0) else null }
        }
    } catch (e: Exception) {
        null
    }

    /**
     * Whether Telegrive's own permission lets it read a gallery file of
     * [mimeType]: photo or video access from Android 13 on, which is all
     * backup asks for, and storage access before that. With access to
     * selected photos only (Android 14), the file is copied instead.
     */
    private fun mayReadMedia(mimeType: String?): Boolean {
        val permission = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> Manifest.permission.READ_EXTERNAL_STORAGE
            mimeType?.startsWith("image/") == true -> Manifest.permission.READ_MEDIA_IMAGES
            mimeType?.startsWith("video/") == true -> Manifest.permission.READ_MEDIA_VIDEO
            else -> return false
        }
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
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

    /** A shared copy stopped for room, after [atLeast] bytes of the file. */
    private class NoRoom(val atLeast: Long) : IOException("No room to copy the shared file")

    private companion object {
        const val WRITE_ACCESS_REQUEST = 7301

        /** Room a shared copy leaves free, so it never fills the phone to the last byte. */
        const val ROOM_MARGIN = 64L shl 20

        /** The system file picker's documents for photos, videos and audio. */
        const val MEDIA_DOCUMENTS = "com.android.providers.media.documents"

        /** tg://proxy for MTProto proxies, tg://socks for SOCKS5 ones. */
        val PROXY_HOSTS = setOf("proxy", "socks")

        /** `photo.jpg`, 2 → `photo (2).jpg`. */
        fun numbered(name: String, n: Int): String {
            val dot = name.lastIndexOf('.')
            return if (dot <= 0) "$name ($n)" else "${name.substring(0, dot)} ($n)${name.substring(dot)}"
        }
    }
}
