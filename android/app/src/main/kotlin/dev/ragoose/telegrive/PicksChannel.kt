package dev.ragoose.telegrive

import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Handler
import android.provider.OpenableColumns
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * Android's document picker for files to upload, several at a time. The
 * pick comes back as content URIs with each file's name and size, and
 * nothing is copied then: the upload queue copies each file only when its
 * turn comes, after making sure the phone has room, so hundreds of files
 * picked at once never fill the phone with copies. Access to the files
 * lasts as long as this process. As with FoldersChannel, the pick is an
 * activity result, registered in onCreate, and reading a file asks its
 * provider, another process, so it runs off the main thread; anything that
 * goes wrong answers an error named 'failed'.
 */
class PicksChannel(
    private val activity: FlutterFragmentActivity,
    private val io: Executor,
    private val main: Handler,
) {
    private val launcher: ActivityResultLauncher<Array<String>> =
        activity.registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { onPicked(it) }

    /** The Dart call waiting for a pick. */
    private var pending: MethodChannel.Result? = null

    /**
     * Copies take as long as their files, so they run on threads of their
     * own rather than hold up everything else asked of [io].
     */
    private val copies: Executor = Executors.newCachedThreadPool()

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "telegrive/picks").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(result, media = call.argument<Boolean>("media") == true)
                "copy" -> answer(result, copies) { copy(Uri.parse(call.text("uri")), File(call.text("out"))) }
                else -> result.notImplemented()
            }
        }
    }

    /** Opens the picker, for photos and videos only with [media]. */
    private fun pick(result: MethodChannel.Result, media: Boolean) {
        if (pending != null) {
            result.error("busy", "Files are already being picked", null)
            return
        }
        pending = result
        try {
            launcher.launch(if (media) arrayOf("image/*", "video/*") else arrayOf("*/*"))
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("failed", e.message, null)
        }
    }

    /**
     * Names each picked file and gives its size, read off the main thread.
     * Backing out answers an empty list. A size the provider won't give is
     * -1, which the queue learns once the file is copied.
     */
    private fun onPicked(uris: List<Uri>) {
        val waiting = pending ?: return
        pending = null
        io.execute {
            val picked = uris.map { uri ->
                val (name, size) = describe(uri)
                mapOf("uri" to uri.toString(), "name" to name, "size" to size)
            }
            main.post { waiting.success(picked) }
        }
    }

    private fun describe(uri: Uri): Pair<String, Long> {
        val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val described = try {
            activity.contentResolver.query(uri, columns, null, null, null)?.use {
                if (!it.moveToFirst()) {
                    null
                } else {
                    val name = if (it.isNull(0)) null else it.getString(0)
                    val size = if (it.isNull(1)) -1L else it.getLong(1)
                    name to size
                }
            }
        } catch (e: Exception) {
            null
        }
        val name = described?.first?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "File"
        return name to (described?.second ?: -1L)
    }

    /**
     * Copies the file at [uri] to [out], which the queue names, and answers
     * its size. A copy cut short is deleted, and the queue renames a whole
     * one into place.
     */
    private fun copy(uri: Uri, out: File): Long {
        try {
            out.parentFile?.mkdirs()
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IOException("Can't read ${out.name}")
            input.use { source -> out.outputStream().use { source.copyTo(it, 1 shl 20) } }
        } catch (e: Exception) {
            out.delete()
            throw e
        }
        return out.length()
    }

    /** Runs [work] on [on] and answers with what it returns, or 'failed'. */
    private fun answer(result: MethodChannel.Result, on: Executor = io, work: () -> Any?) {
        on.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    private fun MethodCall.text(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing $key")
}
