package dev.ragoose.telegrive

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executor

/**
 * Android's folder picker, and the folders picked with it, for a phone
 * folder whose new files are to upload by themselves. The pick comes back
 * as an activity result, which an activity can only register for before it
 * is started, so MainActivity creates this in onCreate and the Flutter
 * engine attaches to it later. A picked folder stays readable after a
 * restart through a persistable grant, taken only while a Dart call is
 * waiting for it: a pick that comes back to a new process with nothing
 * waiting is dropped, so no grant is kept that no rule refers to. Listing,
 * copying and checking a folder ask its provider, another process, so they
 * run off the main thread, and anything that goes wrong answers an error
 * named 'failed'.
 */
class FoldersChannel(
    private val activity: FlutterFragmentActivity,
    private val io: Executor,
    private val main: Handler,
) {
    private val treeLauncher: ActivityResultLauncher<Uri?> =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { onTree(it) }

    /** The Dart call waiting for a pick. */
    private var pending: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "telegrive/folders").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(result)
                "list" -> answer(result) {
                    list(Uri.parse(call.text("uri")), call.argument<Boolean>("recursive") == true)
                }
                "copy" -> answer(result) {
                    copy(Uri.parse(call.text("uri")), call.text("documentId"), call.text("name"))
                }
                "release" -> answer(result) { release(Uri.parse(call.text("uri"))) }
                "canRead" -> answer(result) { canRead(Uri.parse(call.text("uri"))) }
                else -> result.notImplemented()
            }
        }
    }

    /** Opens the picker where it was last; a phone without one refuses. */
    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A folder is already being picked", null)
            return
        }
        pending = result
        try {
            treeLauncher.launch(null)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("failed", e.message, null)
        }
    }

    /**
     * Keeps read access to the picked tree beyond this process, then names
     * it for the sheet. Backing out answers null. Android can refuse to keep
     * the grant, which the person is told about, and the name is read off
     * the main thread, as anything asked of a provider is.
     */
    private fun onTree(uri: Uri?) {
        val waiting = pending ?: return
        pending = null
        if (uri == null) {
            waiting.success(null)
            return
        }
        io.execute {
            try {
                activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (e: SecurityException) {
                main.post { waiting.error("not_persisted", e.message, null) }
                return@execute
            }
            val picked = mapOf("uri" to uri.toString(), "name" to displayName(uri))
            main.post { waiting.success(picked) }
        }
    }

    /**
     * The folder's own name, as the picker showed it. When the provider
     * won't say, the tail of the tree's document id is the next best thing:
     * "primary:Download/Bank" is Bank.
     */
    private fun displayName(tree: Uri): String {
        val treeId = DocumentsContract.getTreeDocumentId(tree)
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
        val named = try {
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            activity.contentResolver.query(document, columns, null, null, null)
                ?.use { if (it.moveToFirst() && !it.isNull(0)) it.getString(0) else null }
        } catch (e: Exception) {
            null
        }
        return named?.takeIf { it.isNotBlank() }
            ?: treeId.substringAfterLast('/').substringAfterLast(':').ifBlank { "Folder" }
    }

    /** Runs [work] on [io] and answers with what it returns, or 'failed'. */
    private fun answer(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    /**
     * Every file in the [tree], breadth first, and with [recursive] in its
     * folders too, down to [MAX_DEPTH] levels. A huge tree stops at
     * [MAX_FILES], and the answer says it was cut short. A size or date the
     * provider leaves out is 0.
     */
    private fun list(tree: Uri, recursive: Boolean): Map<String, Any> {
        val columns = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
        )
        val files = mutableListOf<Map<String, Any>>()
        val folders = ArrayDeque(listOf(DocumentsContract.getTreeDocumentId(tree) to 0))
        while (folders.isNotEmpty()) {
            val (folderId, depth) = folders.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, folderId)
            val cursor = activity.contentResolver.query(children, columns, null, null, null)
                ?: throw IOException("Can't read the folder")
            cursor.use {
                while (it.moveToNext()) {
                    val id = it.getString(0) ?: continue
                    val mime = it.getString(2).orEmpty()
                    if (mime == Document.MIME_TYPE_DIR) {
                        if (recursive && depth < MAX_DEPTH) folders.addLast(id to depth + 1)
                        continue
                    }
                    if (files.size >= MAX_FILES) return mapOf("files" to files, "truncated" to true)
                    files.add(
                        mapOf(
                            "id" to id,
                            "name" to it.getString(1).orEmpty(),
                            "mime" to mime,
                            "size" to if (it.isNull(3)) 0L else it.getLong(3),
                            "modified" to if (it.isNull(4)) 0L else it.getLong(4),
                        ),
                    )
                }
            }
        }
        return mapOf("files" to files, "truncated" to false)
    }

    /**
     * Copies one document of the [tree] into the cache for the upload
     * queue, which deletes it once it is sent. It is written under a
     * ".part" name and renamed when complete, so a copy cut short is never
     * taken for the file.
     */
    private fun copy(tree: Uri, documentId: String, name: String): Map<String, Any> {
        val clean = name.replace(Regex("[\\\\/:\\u0000-\\u001f]"), "_").ifBlank { "File" }
        val dir = File(activity.cacheDir, "watched/${System.nanoTime()}").apply { mkdirs() }
        val target = File(dir, clean)
        val partial = File(dir, "$clean.part")
        try {
            val document = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
            val input = activity.contentResolver.openInputStream(document)
                ?: throw IOException("Can't read $clean")
            input.use { source -> partial.outputStream().use { source.copyTo(it, 1 shl 20) } }
            if (!partial.renameTo(target)) throw IOException("Can't finish the copy of $clean")
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
        return mapOf("path" to target.path, "size" to target.length())
    }

    /**
     * Gives back the read access kept for [tree]; one already gone is fine.
     * Answers how many folders Telegrive can still read, which the Dart
     * side logs, so a grant left behind shows.
     */
    private fun release(tree: Uri): Int {
        try {
            activity.contentResolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: Exception) {
            // Not held any more, which is what releasing asks for.
        }
        return activity.contentResolver.persistedUriPermissions.size
    }

    /**
     * Whether Telegrive still holds read access to [tree] and the folder is
     * still there: a folder renamed, deleted or on a removed card keeps its
     * grant but answers no query.
     */
    private fun canRead(tree: Uri): Boolean {
        val granted = activity.contentResolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission }
        if (!granted) return false
        val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        return try {
            activity.contentResolver.query(root, arrayOf(Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { it.moveToFirst() } == true
        } catch (e: Exception) {
            false
        }
    }

    private fun MethodCall.text(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing $key")

    private companion object {
        /** How many levels of subfolders a listing goes into. */
        const val MAX_DEPTH = 10

        /** Where a listing stops, so a huge tree can't hold the check up. */
        const val MAX_FILES = 20_000
    }
}
