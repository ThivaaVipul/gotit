package app.gotit

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import java.io.InputStream
import java.util.concurrent.Executors

/**
 * Files shared to Gotit, read in pieces for Dart to send. Each is opened the
 * moment it is shared, because Android's permission to read it ends with the
 * share screen; an open file stays readable. Nothing is copied first, so a big
 * video costs no extra room.
 */
object PhoneFiles {
    /** A shared file, open and ready to read. */
    data class Shared(val handle: Int, val name: String, val size: Long)

    private val main = Handler(Looper.getMainLooper())
    private val reader = Executors.newSingleThreadExecutor()
    private val open = HashMap<Int, InputStream>()
    private var next = 1

    /** Opens [uri]; null when it can't be read. Main thread. */
    fun open(context: Context, uri: Uri): Shared? {
        val resolver = context.contentResolver
        var name: String? = null
        var size = -1L
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        name = cursor.getString(0)
                        if (!cursor.isNull(1)) size = cursor.getLong(1)
                    }
                }
        } catch (e: RuntimeException) {
            // Name and size stay unknown.
        }
        val stream = try {
            resolver.openInputStream(uri)
        } catch (e: Exception) {
            null
        } ?: return null
        val handle = next++
        synchronized(open) { open[handle] = stream }
        return Shared(handle, name ?: uri.lastPathSegment ?: "file", size)
    }

    /** Up to [max] bytes of [handle]'s file, or null at its end, on [done] (main thread). */
    fun read(handle: Int, max: Int, done: (ByteArray?) -> Unit) {
        reader.execute {
            val stream = synchronized(open) { open[handle] }
            val bytes = try {
                stream?.let { readUpTo(it, max) }
            } catch (e: Exception) {
                null
            }
            if (bytes == null) close(handle)
            main.post { done(bytes) }
        }
    }

    fun close(handle: Int) {
        val stream = synchronized(open) { open.remove(handle) }
        try {
            stream?.close()
        } catch (e: Exception) {
            // Closed anyway.
        }
    }

    /** Fills [max] bytes where the file has them; null at its end. */
    private fun readUpTo(stream: InputStream, max: Int): ByteArray? {
        val buffer = ByteArray(max)
        var filled = 0
        while (filled < max) {
            val read = stream.read(buffer, filled, max - filled)
            if (read < 0) break
            filled += read
        }
        return when (filled) {
            0 -> null
            max -> buffer
            else -> buffer.copyOf(filled)
        }
    }
}
