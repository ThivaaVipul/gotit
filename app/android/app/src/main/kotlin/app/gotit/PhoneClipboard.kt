package app.gotit

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream

/** The phone's clipboard: text, and images. Nothing read or written is kept or logged. */
object PhoneClipboard {
    /** Gotit's own writes carry this label. */
    private const val LABEL = "Gotit"

    /** The biggest image that crosses; Dart checks the same. */
    const val MAX_IMAGE_BYTES = 25 * 1024 * 1024

    /**
     * More pixels than this could never fit in [MAX_IMAGE_BYTES] as PNG, and
     * decoding them (a 108 MP photo needs about 430 MB) could run the app out
     * of memory, so they are skipped before decoding.
     */
    private const val MAX_PIXELS = 24_000_000L

    /**
     * What was copied: text, or an image (a link to it, read with [toPng]),
     * whether the copying app marked it sensitive, when, and whether Gotit
     * itself wrote it (something from the PC).
     */
    data class Copy(
        val text: String?,
        val image: Uri?,
        val sensitive: Boolean,
        val copiedAt: Long,
        val ours: Boolean,
    )

    /** Null when Android refuses (Gotit isn't focused) or there is nothing Gotit carries. */
    fun read(context: Context): Copy? {
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        val clip = try {
            clipboard.primaryClip
        } catch (e: SecurityException) {
            null
        } ?: return null
        if (clip.itemCount == 0) return null
        val description = clip.description
        val item = clip.getItemAt(0)
        val sensitive = Build.VERSION.SDK_INT >= 33 &&
            description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true
        val ours = description.label?.toString() == LABEL
        // An image: a link the clipboard lets Gotit read for now.
        val uri = item.uri
        if (uri != null && description.hasMimeType("image/*")) {
            return Copy(null, uri, sensitive, description.timestamp, ours)
        }
        // Text: styled copies carry plain text too.
        val text = item.text?.toString()
        if (text.isNullOrEmpty()) return null
        return Copy(text, null, sensitive, description.timestamp, ours)
    }

    /**
     * The image at [uri] as PNG, or null when it can't be read or is too big.
     * Slow for big images: never on the main thread.
     */
    fun toPng(context: Context, uri: Uri): ByteArray? = try {
        context.contentResolver.openInputStream(uri)?.use { toPng(it, context.contentResolver.getType(uri)) }
    } catch (e: Exception) {
        null
    } catch (e: OutOfMemoryError) {
        null
    }

    /** [input] as PNG: passed through when it already is one, re-encoded otherwise. */
    fun toPng(input: InputStream, mime: String?): ByteArray? {
        val bytes = input.readBytesUpTo(MAX_IMAGE_BYTES * 2) ?: return null
        if (mime == "image/png" || isPng(bytes)) return bytes.takeIf { it.size <= MAX_IMAGE_BYTES }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0 ||
            bounds.outWidth.toLong() * bounds.outHeight > MAX_PIXELS
        ) {
            return null
        }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        return try {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray().takeIf { it.size <= MAX_IMAGE_BYTES }
        } finally {
            bitmap.recycle()
        }
    }

    /** Background apps may write the clipboard; this is how text from the PC arrives. */
    fun write(context: Context, text: String, sensitive: Boolean) {
        val clip = ClipData.newPlainText(LABEL, text)
        if (sensitive) {
            // Android 13 and later hide a sensitive clip's preview.
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }

    /**
     * An image from the PC: saved to the cache, then put on the clipboard as a
     * link that apps accepting pasted images can read. Only the latest is kept.
     */
    fun writeImage(context: Context, png: ByteArray) {
        val folder = ClipProvider.folder(context).apply { mkdirs() }
        folder.listFiles()?.forEach { it.delete() }
        val file = File(folder, "clip-${System.currentTimeMillis()}.png")
        file.writeBytes(png)
        val clip = ClipData.newUri(context.contentResolver, LABEL, ClipProvider.uriFor(file))
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }

    /**
     * A file from the PC, already in Download/Gotit (an image): on the
     * clipboard as a link to it, which apps accepting pasted images can read.
     */
    fun writeUri(context: Context, uri: Uri) {
        val clip = ClipData.newUri(context.contentResolver, LABEL, uri)
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }

    private fun isPng(bytes: ByteArray) = bytes.size > 8 &&
        bytes[0] == 0x89.toByte() && bytes[1] == 'P'.code.toByte() &&
        bytes[2] == 'N'.code.toByte() && bytes[3] == 'G'.code.toByte()

    /** All of it, or null when it is longer than [limit]. */
    private fun InputStream.readBytesUpTo(limit: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val read = read(buffer)
            if (read < 0) break
            out.write(buffer, 0, read)
            if (out.size() > limit) return null
        }
        return out.toByteArray()
    }
}
