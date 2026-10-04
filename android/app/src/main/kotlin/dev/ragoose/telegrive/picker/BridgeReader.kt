package dev.ragoose.telegrive.picker

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.SystemClock
import android.os.storage.StorageManager
import android.system.ErrnoException
import android.system.OsConstants
import androidx.annotation.RequiresApi
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * The file picker's way to the app's stream server, for files that aren't
 * on the phone. While the drive is open, the app keeps the server's port
 * and token in picker/bridge.json among its private files, and deletes the
 * file otherwise. A file left behind by an app that has since gone is
 * caught by [alive], which asks the server itself.
 *
 * On Android 8 and later the reading app gets a file it can seek in: a
 * read that doesn't carry on from the last one asks the server for a range
 * from where it starts, so a video starts at once and jumps to the middle.
 * Android 7 gets a pipe that streams the file from its start, which apps
 * that jump around in a file may not be able to read.
 */
object BridgeReader {
    data class Endpoint(val port: Int, val token: String)

    private const val CONNECT_TIMEOUT_MS = 2_000

    /**
     * Longer than the stream server waits for Telegram without data, two
     * minutes, so the server gives up first and a slow start isn't cut off.
     */
    private const val READ_TIMEOUT_MS = 150_000
    private const val PING_TIMEOUT_MS = 300

    /** How long an answer from [alive] holds, since every listing asks. */
    private const val ALIVE_FOR_MS = 5_000L

    private var lastAsked: Endpoint? = null
    private var lastAnswer = false
    private var lastAskedAt = 0L

    /** The server the app last pointed the picker at, or null while the drive is closed. */
    fun endpoint(context: Context): Endpoint? = try {
        val file = File(context.filesDir, "picker/bridge.json")
        if (file.isFile) {
            val json = JSONObject(file.readText())
            Endpoint(json.getInt("port"), json.getString("token"))
        } else {
            null
        }
    } catch (e: Exception) {
        null
    }

    /** Whether [endpoint]'s server answers, so Telegrive is running with the drive open. */
    @Synchronized
    fun alive(endpoint: Endpoint): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (endpoint == lastAsked && now - lastAskedAt < ALIVE_FOR_MS) return lastAnswer
        lastAnswer = ping(endpoint)
        lastAsked = endpoint
        lastAskedAt = now
        return lastAnswer
    }

    private fun ping(endpoint: Endpoint): Boolean {
        var connection: HttpURLConnection? = null
        return try {
            connection = (urlOf(endpoint, "ping").openConnection() as HttpURLConnection).apply {
                connectTimeout = PING_TIMEOUT_MS
                readTimeout = PING_TIMEOUT_MS
            }
            connection.responseCode == HttpURLConnection.HTTP_NO_CONTENT
        } catch (e: IOException) {
            false
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * A file descriptor that reads the drive file [fileId] from the server
     * at [endpoint], as the file comes down from Telegram. [size] is the
     * file's whole length, which a seekable reader is told up front.
     */
    fun open(
        context: Context,
        endpoint: Endpoint,
        fileId: String,
        name: String,
        size: Long,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        // The path StreamServer.urlFor makes; the name only helps a reader
        // that looks at it.
        val url = urlOf(endpoint, fileId, name)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            seekable(context, url, size, signal)
        } else {
            streamed(url, name, signal)
        }
    }

    private fun urlOf(endpoint: Endpoint, vararg segments: String): URL =
        URL("http://127.0.0.1:${endpoint.port}/" + listOf(endpoint.token, *segments).joinToString("/") { Uri.encode(it) })

    private fun connect(url: URL, from: Long?): HttpURLConnection =
        (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            // The bytes as they are, so offsets mean what the reader asked.
            setRequestProperty("Accept-Encoding", "identity")
            if (from != null) setRequestProperty("Range", "bytes=$from-")
        }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun seekable(context: Context, url: URL, size: Long, signal: CancellationSignal?): ParcelFileDescriptor {
        val thread = HandlerThread("picker-read").apply { start() }
        val reader = RangeReader(url, size, thread)
        signal?.setOnCancelListener { reader.hangUp() }
        return try {
            context.getSystemService(StorageManager::class.java)
                .openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY, reader, Handler(thread.looper))
        } catch (e: Exception) {
            thread.quitSafely()
            throw e
        }
    }

    /**
     * Answers reads of a proxy file descriptor from one request to the
     * server at a time. Reads that follow on from each other share the
     * request; any other read hangs it up and starts one at its own offset.
     * Android calls it on [thread] alone, which ends with the descriptor.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private class RangeReader(
        private val url: URL,
        private val size: Long,
        private val thread: HandlerThread,
    ) : ProxyFileDescriptorCallback() {
        @Volatile private var connection: HttpURLConnection? = null

        @Volatile private var body: InputStream? = null

        /** Where [body] reads next, or -1 with no request open. */
        @Volatile private var position = -1L

        override fun onGetSize(): Long = size

        override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
            if (offset >= this.size) return 0
            try {
                val stream = body?.takeIf { offset == position } ?: from(offset)
                var read = 0
                while (read < size) {
                    val count = stream.read(data, read, size - read)
                    if (count < 0) break
                    read += count
                }
                position = offset + read
                return read
            } catch (e: IOException) {
                hangUp()
                throw ErrnoException("onRead", OsConstants.EIO)
            }
        }

        private fun from(offset: Long): InputStream {
            hangUp()
            val opened = connect(url, offset)
            connection = opened
            if (opened.responseCode != HttpURLConnection.HTTP_PARTIAL) {
                throw IOException("The stream server answered ${opened.responseCode}")
            }
            return opened.inputStream.also {
                body = it
                position = offset
            }
        }

        override fun onRelease() {
            hangUp()
            thread.quitSafely()
        }

        /** Ends the request under way; from any thread, since cancelling comes from another. */
        fun hangUp() {
            connection?.disconnect()
            connection = null
            body = null
            position = -1
        }
    }

    /**
     * A pipe the file streams into from its start, on a thread of its own.
     * A transfer that breaks closes the pipe with an error, so the reading
     * app sees a failed read rather than a short file.
     */
    private fun streamed(url: URL, name: String, signal: CancellationSignal?): ParcelFileDescriptor {
        val (read, write) = ParcelFileDescriptor.createReliablePipe()
        val connection = connect(url, null)
        signal?.setOnCancelListener { connection.disconnect() }
        Thread({
            val out = ParcelFileDescriptor.AutoCloseOutputStream(write)
            try {
                connection.inputStream.use { it.copyTo(out, 128 * 1024) }
                out.close()
            } catch (e: IOException) {
                try {
                    write.closeWithError("Telegrive stopped sending $name")
                } catch (closing: IOException) {
                    // The reading app has gone already.
                }
            } finally {
                connection.disconnect()
            }
        }, "picker-read").start()
        return read
    }
}
