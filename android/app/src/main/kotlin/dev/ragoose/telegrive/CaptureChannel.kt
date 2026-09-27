package dev.ragoose.telegrive

import androidx.core.content.FileProvider

/**
 * Hands the camera app the file a photo is taken into. A subclass of its
 * own, so the merged manifest keeps it apart from the FileProviders that
 * share_plus and open_filex declare, and so the provider the manifest
 * names exists from the first launch on.
 */
class CaptureFileProvider : FileProvider()
