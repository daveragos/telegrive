package dev.ragoose.telegrive

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.ParcelFileDescriptor
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min

/**
 * Reads the words on PDF pages that are pictures, such as scans, so search
 * finds them. Android draws each page asked for, and the text recognition
 * Play services keeps on the phone reads it; nothing leaves the phone. The
 * recognizer's model arrives with Play services, so until it has, a read
 * answers 'unavailable' and the document is tried again later. A PDF that
 * can't be opened, or anything else that goes wrong, answers 'failed'.
 * Reading runs on a thread of its own, one page at a time, so it never
 * holds up the app's other work.
 */
class TextChannel(private val main: Handler) {
    private val worker = Executors.newSingleThreadExecutor()
    private val recognizer: TextRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "telegrive/text").setMethodCallHandler { call, result ->
            when (call.method) {
                "readPdfPages" -> {
                    val path = call.argument<String>("path")
                    val pages = call.argument<List<Int>>("pages")
                    val maxChars = call.argument<Int>("maxChars") ?: Int.MAX_VALUE
                    if (path == null || pages == null) {
                        result.error("failed", "Missing path or pages", null)
                    } else {
                        worker.execute { readPdfPages(path, pages, maxChars, result) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The text on [pages] of the PDF at [path], up to [maxChars]. */
    private fun readPdfPages(
        path: String,
        pages: List<Int>,
        maxChars: Int,
        result: MethodChannel.Result,
    ) {
        try {
            val text = StringBuilder()
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { renderer ->
                    for (index in pages) {
                        if (index !in 0 until renderer.pageCount || text.length >= maxChars) break
                        val bitmap = renderer.openPage(index).use { page -> draw(page) }
                        try {
                            val found = Tasks.await(
                                recognizer.process(InputImage.fromBitmap(bitmap, 0)),
                                PAGE_TIMEOUT_SECONDS,
                                TimeUnit.SECONDS,
                            )
                            text.appendLine(found.text)
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
            }
            main.post { result.success(text.toString()) }
        } catch (e: ExecutionException) {
            val cause = e.cause
            val code = if (cause is MlKitException && cause.errorCode == MlKitException.UNAVAILABLE) {
                "unavailable"
            } else {
                "failed"
            }
            main.post { result.error(code, cause?.message ?: e.message, null) }
        } catch (e: Exception) {
            main.post { result.error("failed", e.message, null) }
        }
    }

    /**
     * The page on white, its longer side [PAGE_PIXELS] long: sharp enough for
     * print, and small enough that a page never needs much memory.
     */
    private fun draw(page: PdfRenderer.Page): Bitmap {
        val scale = min(MAX_SCALE, PAGE_PIXELS.toFloat() / max(page.width, page.height))
        val bitmap = Bitmap.createBitmap(
            max(1, (page.width * scale).toInt()),
            max(1, (page.height * scale).toInt()),
            Bitmap.Config.ARGB_8888,
        )
        bitmap.eraseColor(Color.WHITE)
        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        return bitmap
    }

    private companion object {
        const val PAGE_PIXELS = 2000
        const val MAX_SCALE = 4f
        const val PAGE_TIMEOUT_SECONDS = 30L
    }
}
