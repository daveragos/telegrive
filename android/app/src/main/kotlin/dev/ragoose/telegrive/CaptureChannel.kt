package dev.ragoose.telegrive

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.provider.MediaStore
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executor

/**
 * Hands the camera app the file a photo is taken into. A subclass of its
 * own, so the merged manifest keeps it apart from the FileProviders that
 * share_plus and open_filex declare, and so the provider the manifest
 * names exists from the first launch on.
 */
class CaptureFileProvider : FileProvider()

/**
 * Google's document scanner and the phone's camera app, for a scan or a
 * photo that goes straight into a drive folder. Both come back as activity
 * results, which an activity can only register for before it is started,
 * so MainActivity creates this in onCreate and the Flutter engine attaches
 * to it later. One Dart call waits at a time; its answer is the file in the
 * cache, null when the person backed out, or an error when the scanner or
 * the camera couldn't start. When Android killed Telegrive while the camera
 * was in front, the result arrives in a new process with no call waiting
 * for it, and goes to [onOrphan] rather than being lost.
 */
class CaptureChannel(
    private val activity: FlutterFragmentActivity,
    private val io: Executor,
    private val main: Handler,
    private val onOrphan: (Map<String, Any>) -> Unit,
) {
    private val scanLauncher: ActivityResultLauncher<IntentSenderRequest> =
        activity.registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { onScan(it) }
    private val photoLauncher: ActivityResultLauncher<Uri> =
        activity.registerForActivityResult(ActivityResultContracts.TakePicture()) { onPhoto(it) }

    /** The Dart call waiting for a scan or a photo. */
    private var pending: MethodChannel.Result? = null

    /** The file the camera app writes into, kept across process death. */
    private var photoTarget: File? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "telegrive/capture").setMethodCallHandler { call, result ->
            when (call.method) {
                "support" -> support(result)
                "scan" -> scan(result)
                "photo" -> photo(result)
                else -> result.notImplemented()
            }
        }
    }

    /** Remembers the photo under way, so a recreated activity can find it. */
    fun saveState(out: Bundle) {
        photoTarget?.let { out.putString(PHOTO_TARGET, it.path) }
    }

    fun restoreState(saved: Bundle?) {
        saved?.getString(PHOTO_TARGET)?.let { photoTarget = File(it) }
    }

    /**
     * Whether this phone can scan, and whether it can take a photo, so the
     * create sheet leaves out what the phone can't do rather than grey it.
     * Scanning needs Play services; a photo needs an app that answers
     * IMAGE_CAPTURE. Both checks ask other processes, so they run off the
     * main thread.
     */
    private fun support(result: MethodChannel.Result) {
        io.execute {
            val answer = try {
                val services = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity)
                val camera = Intent(MediaStore.ACTION_IMAGE_CAPTURE).resolveActivity(activity.packageManager)
                mapOf("scan" to (services == ConnectionResult.SUCCESS), "photo" to (camera != null))
            } catch (e: RuntimeException) {
                mapOf("scan" to false, "photo" to false)
            }
            main.post { result.success(answer) }
        }
    }

    /**
     * Opens the scanner for a PDF of up to 30 pages, cropped and
     * straightened by Play services on the phone. Getting its intent is
     * asynchronous, and it fails when Play services is missing or hasn't
     * fetched the scanner module yet.
     */
    private fun scan(result: MethodChannel.Result) {
        if (!claim(result)) return
        val options = GmsDocumentScannerOptions.Builder()
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            .setGalleryImportAllowed(false)
            .setPageLimit(30)
            .build()
        GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
            .addOnSuccessListener { sender ->
                try {
                    scanLauncher.launch(IntentSenderRequest.Builder(sender).build())
                } catch (e: RuntimeException) {
                    // The activity went away while Play services was answering.
                    fail("unavailable", e.message)
                }
            }
            .addOnFailureListener { e -> fail("unavailable", e.message) }
    }

    /**
     * Opens the camera app on a file of Telegrive's own, reached through
     * [CaptureFileProvider], so the picture never lands in the gallery. A
     * phone without a camera app refuses the intent, and one where another
     * library declared the CAMERA permission refuses it until granted.
     */
    private fun photo(result: MethodChannel.Result) {
        if (!claim(result)) return
        val target = File(activity.cacheDir, "captured/${System.nanoTime()}/Photo ${stamp()}.jpg")
        target.parentFile?.mkdirs()
        photoTarget = target
        try {
            photoLauncher.launch(FileProvider.getUriForFile(activity, "${activity.packageName}.capture", target))
        } catch (e: ActivityNotFoundException) {
            cameraRefused(target, e)
        } catch (e: SecurityException) {
            cameraRefused(target, e)
        }
    }

    private fun cameraRefused(target: File, e: Exception) {
        photoTarget = null
        target.parentFile?.deleteRecursively()
        fail("no_camera", e.message)
    }

    /**
     * Copies the scanner's PDF into the capture folder under a name of
     * Telegrive's own, off the main thread, and removes the scanner's copy
     * when it is a plain file in the cache. Backing out of the scanner, or
     * a result whose PDF can't be read, answers null. A scanner Android
     * couldn't start comes back as a cancel that carries the exception, and
     * that is the scanner failing, not the person backing out.
     */
    private fun onScan(result: ActivityResult) {
        val data = result.data
        if (result.resultCode != Activity.RESULT_OK) {
            val refused = data?.hasExtra(ActivityResultContracts.StartIntentSenderForResult.EXTRA_SEND_INTENT_EXCEPTION)
            if (refused == true) fail("unavailable", "The scanner couldn't be started") else deliver(null)
            return
        }
        val pdf = data?.let { GmsDocumentScanningResult.fromActivityResultIntent(it)?.pdf }
        if (pdf == null) {
            deliver(null)
            return
        }
        io.execute {
            val target = File(activity.cacheDir, "captured/${System.nanoTime()}/Scan ${stamp()}.pdf")
            val copied = try {
                target.parentFile?.mkdirs()
                val input = activity.contentResolver.openInputStream(pdf.uri) ?: throw IOException("Can't read the scan")
                input.use { source -> target.outputStream().use { source.copyTo(it, 1 shl 20) } }
                true
            } catch (e: Exception) {
                target.parentFile?.deleteRecursively()
                false
            }
            if (!copied) {
                deliver(null)
                return@execute
            }
            discardScannerFile(pdf.uri)
            deliver(
                mapOf(
                    "path" to target.path,
                    "name" to target.name,
                    "size" to target.length(),
                    "pages" to pdf.pageCount,
                ),
            )
        }
    }

    /**
     * The camera app says only whether it wrote the file. An empty file is
     * a camera that gave up, and is treated like backing out. The photo's
     * time is when the camera wrote the file, which the file itself
     * remembers, with now as a fallback.
     */
    private fun onPhoto(ok: Boolean) {
        val target = photoTarget
        photoTarget = null
        if (target == null) {
            deliver(null)
            return
        }
        io.execute {
            val size = target.length()
            deliver(
                if (ok && size > 0) {
                    mapOf(
                        "path" to target.path,
                        "name" to target.name,
                        "size" to size,
                        "takenAt" to (target.lastModified().takeIf { it > 0 } ?: System.currentTimeMillis()),
                    )
                } else {
                    target.parentFile?.deleteRecursively()
                    null
                },
            )
        }
    }

    /** One capture at a time: a second call while one is out is refused. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "A scan or photo is already under way", null)
            return false
        }
        pending = result
        return true
    }

    /**
     * Answers the waiting call on the main thread, where a channel result
     * must be given. With no call waiting, a file that did arrive is handed
     * to [onOrphan] and a cancel is dropped.
     */
    private fun deliver(file: Map<String, Any>?) {
        main.post {
            val waiting = pending
            pending = null
            when {
                waiting != null -> waiting.success(file)
                file != null -> onOrphan(file)
            }
        }
    }

    /** Refuses the waiting call. Only ever reached on the main thread. */
    private fun fail(code: String, message: String?) {
        val waiting = pending ?: return
        pending = null
        waiting.error(code, message, null)
    }

    /**
     * The scanner leaves its PDF in Telegrive's cache. Once copied it is
     * only taking room, so it goes when it really is a file there; a
     * content URI, or a path outside the cache, is left to its owner.
     */
    private fun discardScannerFile(uri: Uri) {
        if (uri.scheme != "file") return
        val path = uri.path ?: return
        try {
            val file = File(path).canonicalFile
            if (file.startsWith(activity.cacheDir.canonicalFile)) file.delete()
        } catch (e: IOException) {
            // Left where it is; Android clears the cache when it must.
        }
    }

    /** The same stamp a shared note gets, so captures sort in with them. */
    private fun stamp(): String = SimpleDateFormat("yyyy-MM-dd HH.mm", Locale.US).format(Date())

    private companion object {
        const val PHOTO_TARGET = "dev.ragoose.telegrive.capture.photoTarget"
    }
}
