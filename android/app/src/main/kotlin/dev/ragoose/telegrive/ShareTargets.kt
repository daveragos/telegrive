package dev.ragoose.telegrive

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * Recent drive folders as sharing shortcuts, which Android offers as
 * targets of their own in its share sheet, each named after its folder.
 * Sharing to one opens MainActivity with the shared files and the
 * shortcut's id, which carries the folder's id.
 */
object ShareTargets {
    /** The share-target category in res/xml/shortcuts.xml. */
    const val CATEGORY = "dev.ragoose.telegrive.category.FOLDER"

    /** Starts the id of every shortcut that stands for a folder. */
    const val PREFIX = "folder:"

    /**
     * Makes [targets], each an "id" and a "name", the folders the share
     * sheet offers, in that order, up to four, and takes out any other.
     * A shortcut Android already has as it should be is left alone, and
     * only a new one is pushed: a push also counts as a use, and uses are
     * what Android ranks the targets by.
     */
    fun publish(context: Context, targets: List<Map<String, String>>) {
        val max = minOf(4, ShortcutManagerCompat.getMaxShortcutCountPerActivity(context))
        val wanted = targets.take(max).mapIndexedNotNull { rank, target ->
            val id = target["id"] ?: return@mapIndexedNotNull null
            val name = target["name"] ?: return@mapIndexedNotNull null
            shortcut(context, id, name, rank)
        }
        val wantedIds = wanted.map { it.id }.toSet()
        val current = ShortcutManagerCompat.getDynamicShortcuts(context)
            .filter { it.id.startsWith(PREFIX) }
            .associateBy { it.id }
        val stale = current.keys.filter { it !in wantedIds }
        if (stale.isNotEmpty()) {
            ShortcutManagerCompat.removeDynamicShortcuts(context, stale)
            ShortcutManagerCompat.removeLongLivedShortcuts(context, stale)
        }
        for (shortcut in wanted) {
            val known = current[shortcut.id]
            when {
                known == null -> ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
                known.shortLabel.toString() != shortcut.shortLabel.toString() ||
                    known.rank != shortcut.rank ->
                    ShortcutManagerCompat.updateShortcuts(context, listOf(shortcut))
            }
        }
    }

    /** Tells Android the folder [folderId]'s target was just used. */
    fun reportUsed(context: Context, folderId: String) =
        ShortcutManagerCompat.reportShortcutUsed(context, PREFIX + folderId)

    /** The folder the share in [intent] was sent to, or null for the plain target. */
    fun folderOf(intent: Intent): String? =
        intent.getStringExtra(ShortcutManagerCompat.EXTRA_SHORTCUT_ID)
            ?.takeIf { it.startsWith(PREFIX) }
            ?.removePrefix(PREFIX)

    /**
     * A target for the folder [id] called [name]. Opened from anywhere but
     * the share sheet, it just opens the app. It stays off the launcher's
     * long-press menu from Android 13 on; before that, androidx leaves out
     * a shortcut kept off the launcher altogether, share sheet included.
     */
    private fun shortcut(context: Context, id: String, name: String, rank: Int): ShortcutInfoCompat =
        ShortcutInfoCompat.Builder(context, PREFIX + id)
            .setShortLabel(name)
            .setLongLabel("Save to $name")
            .setIcon(IconCompat.createWithResource(context, R.drawable.ic_share_folder))
            .setIntent(Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW))
            .setCategories(setOf(CATEGORY))
            .setLongLived(true)
            .setRank(rank)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    setExcludedFromSurfaces(ShortcutInfoCompat.SURFACE_LAUNCHER)
                }
            }
            .build()
}
