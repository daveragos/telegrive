package dev.ragoose.telegrive

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.Executor
import java.util.zip.CRC32
import java.util.zip.DataFormatException
import java.util.zip.Inflater

/**
 * Zip files on this phone that the person picks, the parts of a Google
 * Photos export, read where they lie: Dart reads each part's list of files
 * and the small files in it through [read], and takes the photos and
 * videos out one at a time through [extract], so a part is never copied
 * whole. A picked part stays readable after a restart through a
 * persistable grant, as a watched folder does, taken only while a Dart
 * call is waiting for the pick. Reads ask the part's provider, another
 * process, so they run off the main thread. A part Android won't let
 * Telegrive read answers an error named 'no_access', a part cut short
 * 'incomplete', a file that fails its checksum 'damaged', and anything else
 * 'failed'.
 */
class ArchivesChannel(
    private val activity: FlutterFragmentActivity,
    private val io: Executor,
    private val main: Handler,
) {
    private val launcher: ActivityResultLauncher<Array<String>> =
        activity.registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { onPicked(it) }

    /** The Dart call waiting for a pick. */
    private var pending: MethodChannel.Result? = null

    /**
     * Parts held open between calls, the one used last at the end, so the
     * many small reads of one part don't each open it again.
     */
    private val open = object : LinkedHashMap<String, Opened>(4, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Opened>): Boolean {
            if (size <= MAX_OPEN) return false
            eldest.value.close()
            return true
        }
    }

    /**
     * A part held open. The channel reads by position and doesn't own the
     * descriptor, so closing the descriptor is what lets the part go.
     */
    private class Opened(val descriptor: ParcelFileDescriptor) {
        val channel: FileChannel = FileInputStream(descriptor.fileDescriptor).channel

        fun close() {
            runCatching { descriptor.close() }
        }
    }

    private class ArchiveException(val code: String, message: String) : IOException(message)

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "telegrive/archives").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(result)
                "read" -> answer(result) { read(Uri.parse(call.text("uri")), call.ranges()) }
                "extract" -> answer(result) {
                    extract(
                        Uri.parse(call.text("uri")),
                        offset = call.long("offset"),
                        compressedSize = call.long("compressedSize"),
                        method = call.long("method").toInt(),
                        size = call.long("size"),
                        crc = call.long("crc"),
                        path = call.text("path"),
                    )
                }
                "release" -> answer(result) { release(Uri.parse(call.text("uri"))) }
                "canRead" -> answer(result) { canRead(Uri.parse(call.text("uri"))) }
                "delete" -> answer(result) { delete(Uri.parse(call.text("uri"))) }
                "closeAll" -> answer(result) { closeAll() }
                else -> result.notImplemented()
            }
        }
    }

    /** Opens the picker for zip files; a phone without one refuses. */
    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Files are already being picked", null)
            return
        }
        pending = result
        try {
            launcher.launch(ZIP_TYPES)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("failed", e.message, null)
        }
    }

    /**
     * Keeps access to each picked file beyond this process, with the right
     * to delete it too where its provider gives that, then names and sizes
     * them. Backing out answers an empty list. A file Android won't keep
     * access to is left out, since the import couldn't carry on with it
     * after a restart.
     */
    private fun onPicked(uris: List<Uri>) {
        val waiting = pending ?: return
        pending = null
        io.execute {
            val picked = uris.mapNotNull { uri ->
                if (!persist(uri)) return@mapNotNull null
                val (name, size) = describe(uri)
                mapOf("uri" to uri.toString(), "name" to name, "size" to size)
            }
            main.post { waiting.success(picked) }
        }
    }

    private fun persist(uri: Uri): Boolean {
        val resolver = activity.contentResolver
        return try {
            resolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            true
        } catch (e: SecurityException) {
            try {
                resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                true
            } catch (e: SecurityException) {
                false
            }
        }
    }

    /** The file's name and size as its provider gives them; a size it leaves out is read from the file. */
    private fun describe(uri: Uri): Pair<String, Long> {
        var name: String? = null
        var size: Long? = null
        try {
            val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
            activity.contentResolver.query(uri, columns, null, null, null)?.use {
                if (it.moveToFirst()) {
                    if (!it.isNull(0)) name = it.getString(0)
                    if (!it.isNull(1)) size = it.getLong(1)
                }
            }
        } catch (e: Exception) {
            // Named from the URI below.
        }
        val known = size ?: runCatching { opened(uri).descriptor.statSize }.getOrNull()?.takeIf { it >= 0 } ?: 0L
        return (name?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment.orEmpty().substringAfterLast('/')) to known
    }

    /** Runs [work] on [io] and answers with what it returns, or an error named for what went wrong. */
    private fun answer(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: ArchiveException) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: FileNotFoundException) {
                main.post { result.error("no_access", e.message, null) }
            } catch (e: SecurityException) {
                main.post { result.error("no_access", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    private fun opened(uri: Uri): Opened = synchronized(open) {
        open[uri.toString()] ?: Opened(
            activity.contentResolver.openFileDescriptor(uri, "r")
                ?: throw FileNotFoundException("Can't open $uri"),
        ).also { open[uri.toString()] = it }
    }

    private fun channel(uri: Uri): FileChannel = opened(uri).channel

    /**
     * The bytes of each range, `[offset, length]`, in order. A range that
     * runs past the end comes back short. Reads go by position, so the two
     * threads of [io] can read one part at once.
     */
    private fun read(uri: Uri, ranges: List<Pair<Long, Int>>): List<ByteArray> {
        val channel = channel(uri)
        return ranges.map { (offset, length) ->
            val buffer = ByteBuffer.allocate(length)
            var at = offset
            while (buffer.hasRemaining()) {
                val n = channel.read(buffer, at)
                if (n <= 0) break
                at += n
            }
            if (buffer.position() == length) buffer.array() else buffer.array().copyOf(buffer.position())
        }
    }

    /**
     * Writes the file whose data starts at [offset] to [path], unpacking it
     * when [method] says it is deflated, and checks it against [size] and
     * [crc]. It is written under a ".part" name and renamed once whole and
     * checked, so a file cut short or damaged is never taken for it.
     */
    private fun extract(
        uri: Uri,
        offset: Long,
        compressedSize: Long,
        method: Int,
        size: Long,
        crc: Long,
        path: String,
    ): Long {
        if (method != STORED && method != DEFLATED) throw ArchiveException("unsupported", "Packed with method $method")
        val target = File(path)
        val partial = File("$path.part")
        target.parentFile?.mkdirs()
        val channel = channel(uri)
        val checksum = CRC32()
        val inflater = if (method == DEFLATED) Inflater(true) else null
        val input = ByteBuffer.allocate(CHUNK)
        val output = ByteArray(CHUNK)
        var written = 0L
        try {
            partial.outputStream().buffered(CHUNK).use { out ->
                fun emit(bytes: ByteArray, count: Int) {
                    checksum.update(bytes, 0, count)
                    out.write(bytes, 0, count)
                    written += count
                }
                var at = offset
                val end = offset + compressedSize
                while (at < end) {
                    input.clear()
                    input.limit(minOf(CHUNK.toLong(), end - at).toInt())
                    val n = channel.read(input, at)
                    if (n <= 0) throw ArchiveException("incomplete", "The part is cut short")
                    at += n
                    if (inflater == null) {
                        emit(input.array(), n)
                        continue
                    }
                    inflater.setInput(input.array(), 0, n)
                    while (!inflater.needsInput() && !inflater.finished()) {
                        val count = inflater.inflate(output)
                        if (count == 0 && inflater.needsDictionary()) throw ArchiveException("damaged", "Damaged data")
                        if (count > 0) emit(output, count)
                    }
                }
                if (inflater != null) {
                    while (!inflater.finished()) {
                        val count = inflater.inflate(output)
                        if (count == 0) break
                        emit(output, count)
                    }
                }
            }
            if (written != size || checksum.value != crc) throw ArchiveException("damaged", "The file doesn't match its checksum")
            if (!partial.renameTo(target)) throw IOException("Can't finish ${target.name}")
        } catch (e: DataFormatException) {
            partial.delete()
            throw ArchiveException("damaged", e.message ?: "Damaged data")
        } catch (e: Exception) {
            partial.delete()
            throw e
        } finally {
            inflater?.end()
        }
        return written
    }

    /**
     * Gives back the access kept for [uri]; one already gone is fine. Answers
     * how many grants Telegrive still holds, which the Dart side logs.
     */
    private fun release(uri: Uri): Int {
        forget(uri)
        for (flags in listOf(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )) {
            try {
                activity.contentResolver.releasePersistableUriPermission(uri, flags)
                break
            } catch (e: Exception) {
                // Not held with these flags, or not at all.
            }
        }
        return activity.contentResolver.persistedUriPermissions.size
    }

    /** Whether Telegrive still holds access to [uri] and the file is still there. */
    private fun canRead(uri: Uri): Boolean {
        val granted = activity.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
        if (!granted) return false
        return try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { it.moveToFirst() } == true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Deletes the file from the phone and gives back the access to it.
     * Answers false when its provider won't, which the person is told.
     */
    private fun delete(uri: Uri): Boolean {
        forget(uri)
        val deleted = try {
            DocumentsContract.deleteDocument(activity.contentResolver, uri)
        } catch (e: Exception) {
            false
        }
        if (deleted) release(uri)
        return deleted
    }

    private fun forget(uri: Uri) {
        synchronized(open) { open.remove(uri.toString()) }?.close()
    }

    private fun closeAll(): Boolean {
        val all = synchronized(open) { open.values.toList().also { open.clear() } }
        all.forEach { it.close() }
        return true
    }

    private fun MethodCall.text(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing $key")

    private fun MethodCall.long(key: String): Long =
        (argument<Any>(key) as? Number)?.toLong() ?: throw IllegalArgumentException("Missing $key")

    private fun MethodCall.ranges(): List<Pair<Long, Int>> =
        (argument<List<Any?>>("ranges") ?: throw IllegalArgumentException("Missing ranges")).map {
            val pair = it as List<*>
            (pair[0] as Number).toLong() to (pair[1] as Number).toInt()
        }

    private companion object {
        val ZIP_TYPES = arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")
        const val STORED = 0
        const val DEFLATED = 8
        const val CHUNK = 1 shl 20

        /** Parts held open at once. */
        const val MAX_OPEN = 4
    }
}
