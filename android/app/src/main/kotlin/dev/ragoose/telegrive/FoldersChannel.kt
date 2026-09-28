package dev.ragoose.telegrive

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.provider.DocumentsContract
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * Android's folder picker, for a phone folder whose new files are to upload
 * by themselves. The pick comes back as an activity result, which an
 * activity can only register for before it is started, so MainActivity
 * creates this in onCreate and the Flutter engine attaches to it later. A
 * picked folder stays readable after a restart through a persistable
 * grant, taken only while a Dart call is waiting for it: a pick that comes
 * back to a new process with nothing waiting is dropped, so no grant is
 * kept that no rule refers to.
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
}
