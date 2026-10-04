package dev.ragoose.telegrive.picker

import android.database.Cursor
import android.database.MatrixCursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import dev.ragoose.telegrive.R
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.Locale

/**
 * The drive in Android's file picker: one root, Telegrive, holding the
 * folders and files the Files tab shows, searchable by name and read-only.
 *
 * It runs in the ':picker' process and reads the index straight from
 * telegrive.sqlite with Android's SQLite, one short read-only connection
 * per call and no transaction, so browsing needs neither Flutter nor
 * TDLib. The process of its own is what keeps the index safe: Android's
 * SQLite and Drift's are two copies of SQLite, and two copies in one
 * process drop each other's file locks. The app's writes wait out these
 * reads. An index that can't be read, after a sign-out or under a schema
 * this doesn't know, makes a listing say to open Telegrive instead of
 * failing.
 *
 * A file opens from a copy on the phone when there is one, kept offline or
 * downloaded. Anything else streams from the app's stream server through
 * [BridgeReader], which needs Telegrive running with the drive open.
 *
 * Document ids are 'root', 'd:<folder id>' and 'f:<file id>', using the
 * drive's own ids, so they stay the same across a rebuilt index or a
 * reinstall.
 */
class DriveDocumentsProvider : DocumentsProvider() {
    private val authority: String
        get() = "${context!!.packageName}.documents"

    /** Opens nothing: each call reads the index for itself. */
    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val summary = try {
            readIndex { db ->
                db.rawQuery(SHOWN_TOTALS, null).use { row ->
                    if (row.moveToFirst()) summaryOf(row.getLong(0), row.getLong(1)) else null
                }
            }
        } catch (e: SQLiteException) {
            null
        }
        return MatrixCursor(projection ?: ROOT_COLUMNS).apply {
            newRow()
                .add(Root.COLUMN_ROOT_ID, ROOT_ID)
                .add(Root.COLUMN_DOCUMENT_ID, ROOT)
                .add(Root.COLUMN_TITLE, TITLE)
                .add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
                // No Recents, so drive files never show on the picker's
                // first screen. Not local-only either, since most files
                // download when opened, so apps that ask for files already
                // on the phone don't see it.
                .add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_SEARCH or Root.FLAG_SUPPORTS_IS_CHILD)
                .add(Root.COLUMN_SUMMARY, summary)
        }
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        if (documentId == ROOT) {
            cursor.newRow()
                .add(Document.COLUMN_DOCUMENT_ID, ROOT)
                .add(Document.COLUMN_DISPLAY_NAME, TITLE)
                .add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
                .add(Document.COLUMN_FLAGS, 0)
            return cursor
        }
        val running = documentId.startsWith(FILE) && telegriveRunning()
        try {
            readIndex { db ->
                when {
                    documentId.startsWith(FOLDER) -> {
                        val folderId = documentId.removePrefix(FOLDER)
                        db.rawQuery(FOLDER_BY_ID, arrayOf(folderId)).use { addFolders(cursor, it) }
                    }
                    documentId.startsWith(FILE) -> {
                        val fileId = documentId.removePrefix(FILE)
                        val copies = localCopies(db, fileId)
                        db.rawQuery(FILE_BY_ID, arrayOf(fileId)).use { addFiles(cursor, it, copies, running) }
                    }
                }
            }
        } catch (e: SQLiteException) {
            return unreadable(projection)
        }
        if (cursor.count == 0) throw FileNotFoundException("Telegrive has no $documentId")
        return cursor
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val folderId = when {
            parentDocumentId == ROOT -> null
            parentDocumentId.startsWith(FOLDER) -> parentDocumentId.removePrefix(FOLDER)
            else -> throw FileNotFoundException("Not a folder: $parentDocumentId")
        }
        val running = telegriveRunning()
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        try {
            readIndex { db ->
                val args = folderId?.let { arrayOf(it) }
                db.rawQuery(if (folderId == null) FOLDERS_AT_ROOT else FOLDERS_IN, args).use { addFolders(cursor, it) }
                val copies = localCopies(db)
                db.rawQuery(if (folderId == null) FILES_AT_ROOT else FILES_IN, args).use {
                    addFiles(cursor, it, copies, running)
                }
            }
        } catch (e: SQLiteException) {
            return unreadable(projection)
        }
        if (!running) cursor.extras = Bundle().apply { putString(DocumentsContract.EXTRA_INFO, NEEDS_TELEGRIVE) }
        cursor.setNotificationUri(
            context!!.contentResolver,
            DocumentsContract.buildChildDocumentsUri(authority, parentDocumentId),
        )
        return cursor
    }

    override fun querySearchDocuments(rootId: String, query: String, projection: Array<out String>?): Cursor {
        val running = telegriveRunning()
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        // The name as typed, with LIKE's own characters taken literally.
        val pattern = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        try {
            readIndex { db ->
                db.rawQuery(SEARCH_FOLDERS, arrayOf(pattern)).use { addFolders(cursor, it) }
                val copies = localCopies(db)
                db.rawQuery(SEARCH_FILES, arrayOf(pattern)).use { addFiles(cursor, it, copies, running) }
            }
        } catch (e: SQLiteException) {
            return unreadable(projection)
        }
        return cursor
    }

    /**
     * Walks up the folders from [documentId] until it meets [parentDocumentId]
     * or the root. A folder that is gone counts as the root, as it does in
     * listings, and a loop in the tree ends the walk.
     */
    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        if (documentId == ROOT || documentId == parentDocumentId) return false
        return try {
            readIndex { db ->
                val seen = mutableSetOf<String>()
                var above = containerOf(db, documentId)
                while (above != null && above != parentDocumentId) {
                    if (above == ROOT || !seen.add(above)) return@readIndex false
                    above = containerOf(db, above)
                }
                above != null
            }
        } catch (e: SQLiteException) {
            false
        }
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        if (mode != "r") throw UnsupportedOperationException("Telegrive is read-only here")
        if (!documentId.startsWith(FILE)) throw FileNotFoundException("Not a file: $documentId")
        val fileId = documentId.removePrefix(FILE)
        val found = try {
            readIndex { db ->
                db.rawQuery(FILE_BY_ID, arrayOf(fileId)).use { row ->
                    if (row.moveToFirst()) {
                        Openable(row.getString(1), row.getLong(3), localCopies(db, fileId).onPhone(fileId))
                    } else {
                        null
                    }
                }
            }
        } catch (e: SQLiteException) {
            throw FileNotFoundException(UNREADABLE)
        }
        val file = found ?: throw FileNotFoundException("Telegrive has no $documentId")

        file.copy?.let { return ParcelFileDescriptor.open(it, ParcelFileDescriptor.MODE_READ_ONLY) }
        val context = context!!
        val endpoint = BridgeReader.endpoint(context)?.takeIf { BridgeReader.alive(it) }
            ?: throw FileNotFoundException("Open Telegrive to get ${file.name}")
        return try {
            BridgeReader.open(context, endpoint, fileId, file.name, file.size, signal)
        } catch (e: IOException) {
            throw FileNotFoundException("Couldn't get ${file.name}: ${e.message}")
        }
    }

    /** A file to open: its name and size, and a copy on the phone when there is one. */
    private class Openable(val name: String, val size: Long, val copy: File?)

    /**
     * Runs [block] on a read-only connection to the index that is closed
     * straight after. Without localized collators, Android leaves the file
     * as it is rather than adding a table of its own to it.
     */
    private fun <T> readIndex(block: (SQLiteDatabase) -> T): T {
        val db = SQLiteDatabase.openDatabase(
            File(context!!.filesDir, DATABASE).path,
            null,
            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
        )
        try {
            return block(db)
        } finally {
            db.close()
        }
    }

    /** Whether Telegrive is running with the drive open, so a file not on the phone can stream. */
    private fun telegriveRunning(): Boolean = BridgeReader.endpoint(context!!)?.let(BridgeReader::alive) ?: false

    /**
     * Each file's copies on this phone, kept offline or downloaded, by file
     * id; only the one file's when [fileId] is given. [onPhone] checks
     * which are still there.
     */
    private fun localCopies(db: SQLiteDatabase, fileId: String? = null): Map<String, List<String>> {
        val copies = HashMap<String, MutableList<String>>()
        val rows = if (fileId == null) db.rawQuery(LOCAL_COPIES, null) else db.rawQuery(LOCAL_COPIES_OF, arrayOf(fileId))
        rows.use {
            while (it.moveToNext()) copies.getOrPut(it.getString(0)) { mutableListOf() }.add(it.getString(1))
        }
        return copies
    }

    private fun Map<String, List<String>>.onPhone(fileId: String): File? =
        this[fileId]?.map(::File)?.firstOrNull { it.isFile }

    /**
     * The document id of the folder [documentId] sits in: the root for one
     * in no folder or in a folder that is gone, and null for a document the
     * drive doesn't show.
     */
    private fun containerOf(db: SQLiteDatabase, documentId: String): String? {
        val (sql, id) = when {
            documentId.startsWith(FILE) -> FILE_FOLDER to documentId.removePrefix(FILE)
            documentId.startsWith(FOLDER) -> FOLDER_PARENT to documentId.removePrefix(FOLDER)
            else -> return null
        }
        val parent = db.rawQuery(sql, arrayOf(id)).use { row ->
            if (!row.moveToFirst()) return null
            if (row.isNull(0)) null else row.getString(0)
        } ?: return ROOT
        val exists = db.rawQuery(FOLDER_EXISTS, arrayOf(parent)).use { it.moveToFirst() }
        return if (exists) FOLDER + parent else ROOT
    }

    private fun addFolders(cursor: MatrixCursor, rows: Cursor) {
        while (rows.moveToNext()) {
            cursor.newRow()
                .add(Document.COLUMN_DOCUMENT_ID, FOLDER + rows.getString(0))
                .add(Document.COLUMN_DISPLAY_NAME, rows.getString(1))
                .add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
                .add(Document.COLUMN_LAST_MODIFIED, rows.getLong(2) * 1000)
                .add(Document.COLUMN_FLAGS, 0)
        }
    }

    /**
     * Adds a row per file in [rows]. A file on the phone says so; one that
     * isn't says Telegrive needs to be open while it is not [running], and
     * nothing while it is, since it opens as it downloads.
     */
    private fun addFiles(cursor: MatrixCursor, rows: Cursor, copies: Map<String, List<String>>, running: Boolean) {
        while (rows.moveToNext()) {
            val id = rows.getString(0)
            cursor.newRow()
                .add(Document.COLUMN_DOCUMENT_ID, FILE + id)
                .add(Document.COLUMN_DISPLAY_NAME, rows.getString(1))
                .add(Document.COLUMN_MIME_TYPE, rows.getString(2)?.takeIf { it.isNotBlank() } ?: ANY_FILE)
                .add(Document.COLUMN_SIZE, rows.getLong(3))
                .add(Document.COLUMN_LAST_MODIFIED, rows.getLong(4) * 1000)
                .add(Document.COLUMN_FLAGS, 0)
                .add(
                    Document.COLUMN_SUMMARY,
                    when {
                        copies.onPhone(id) != null -> "On this phone"
                        !running -> "Open Telegrive to get this file"
                        else -> null
                    },
                )
        }
    }

    private fun unreadable(projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: DOCUMENT_COLUMNS).apply {
            extras = Bundle().apply { putString(DocumentsContract.EXTRA_ERROR, UNREADABLE) }
        }

    companion object {
        private const val DATABASE = "telegrive.sqlite"
        private const val TITLE = "Telegrive"
        private const val ROOT_ID = "drive"
        private const val ROOT = "root"
        private const val FOLDER = "d:"
        private const val FILE = "f:"
        private const val ANY_FILE = "application/octet-stream"
        private const val NEEDS_TELEGRIVE = "Files not on this phone need Telegrive open. Open it, then come back."
        private const val UNREADABLE = "Open Telegrive, then try again."

        // What the index is read with. test/picker_contract_test.dart keeps
        // a copy of each statement, runs it against the app's schema and
        // fails when a statement here and its copy differ; keep the two in
        // step. The listings follow AppDatabase's _shown and _inFolder: a
        // file shows once all its parts are in and while it isn't hidden
        // (in the trash or in a trashed folder), and anything whose folder
        // is gone shows at the root. Dates are Unix seconds and flags 0 or
        // 1, as Drift keeps them.
        private const val SHOWN_TOTALS = "SELECT COUNT(*), COALESCE(SUM(size), 0) FROM drive_files WHERE parts_present >= part_count AND hidden = 0"
        private const val FOLDERS_IN = "SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND parent_id = ?"
        private const val FOLDERS_AT_ROOT = "SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND (parent_id IS NULL OR parent_id NOT IN (SELECT id FROM folders))"
        private const val FILES_IN = "SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND folder_id = ?"
        private const val FILES_AT_ROOT = "SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND (folder_id IS NULL OR folder_id NOT IN (SELECT id FROM folders))"
        private const val FOLDER_BY_ID = "SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND id = ?"
        private const val FILE_BY_ID = "SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND id = ?"
        private const val SEARCH_FOLDERS = "SELECT id, name, modified_at FROM folders WHERE hidden = 0 AND name LIKE ? ESCAPE '\\' ORDER BY modified_at DESC LIMIT 20"
        private const val SEARCH_FILES = "SELECT id, name, mime_type, size, modified_at FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND name LIKE ? ESCAPE '\\' ORDER BY modified_at DESC LIMIT 100"
        private const val FOLDER_PARENT = "SELECT parent_id FROM folders WHERE hidden = 0 AND id = ?"
        private const val FILE_FOLDER = "SELECT folder_id FROM drive_files WHERE hidden = 0 AND parts_present >= part_count AND id = ?"
        private const val FOLDER_EXISTS = "SELECT 1 FROM folders WHERE id = ?"
        private const val LOCAL_COPIES = "SELECT file_id, path FROM offline_copies UNION ALL SELECT file_id, result_path FROM transfers WHERE kind = 'download' AND status = 'completed' AND result_path IS NOT NULL"
        private const val LOCAL_COPIES_OF = "SELECT file_id, path FROM ($LOCAL_COPIES) WHERE file_id = ?"

        private val ROOT_COLUMNS = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_TITLE,
            Root.COLUMN_ICON,
            Root.COLUMN_FLAGS,
            Root.COLUMN_SUMMARY,
        )

        private val DOCUMENT_COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SUMMARY,
        )

        /** '1,204 files · 38.2 GB', in the words and units Home uses. */
        private fun summaryOf(count: Long, bytes: Long): String =
            "${String.format(Locale.US, "%,d", count)} ${if (count == 1L) "file" else "files"} · ${bytes(bytes)}"

        private val UNITS = arrayOf("B", "KB", "MB", "GB", "TB", "PB")

        /**
         * Formatters.bytes from lib/core/format/formatters.dart: binary
         * multiples, one decimal below 100 of a unit and none in bytes, so
         * the picker's total reads as Home's does.
         */
        private fun bytes(value: Long): String {
            if (value <= 0) return "0 B"
            var size = value.toDouble()
            var unit = 0
            while (size >= 1024 && unit < UNITS.size - 1) {
                size /= 1024
                unit++
            }
            val digits = if (unit == 0 || size >= 100) 0 else 1
            return String.format(Locale.ROOT, "%.${digits}f %s", size, UNITS[unit])
        }
    }
}
