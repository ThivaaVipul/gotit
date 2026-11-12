package app.gotit

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.concurrent.Executors

/**
 * Files from the PC, written straight into Download/Gotit through MediaStore,
 * on the app.gotit/received channel. Each is hidden (pending) until it
 * arrived whole, and deleted if it didn't; MediaStore names it, making a
 * clashing name unique ("name (1).ext"). Writes run in order on one thread,
 * and answers come back on the main thread. Nothing is logged.
 */
object PhoneSaves {
    private const val FOLDER = "Download/Gotit"

    /** Room left free on the phone, beyond the file itself. */
    private const val SPARE = 64L * 1024 * 1024

    private class Saving(val uri: Uri, val stream: OutputStream)

    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()

    // Only touched on the writer thread.
    private val open = HashMap<Int, Saving>()
    private var next = 1

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "app.gotit/received").setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> {
                    val name = call.argument<String>("name") ?: "file"
                    val size = call.argument<Number>("size")?.toLong() ?: -1L
                    answer(result) { create(app, name, size) }
                }
                "write" -> {
                    val handle = call.argument<Int>("handle")
                    val bytes = call.argument<ByteArray>("bytes")
                    answer(result) { handle != null && bytes != null && write(handle, bytes) }
                }
                "keep" -> {
                    val handle = call.argument<Int>("handle")
                    answer(result) { handle?.let { keep(app, it) } }
                }
                "discard" -> {
                    val handle = call.argument<Int>("handle")
                    answer(result) { handle?.let { discard(app, it) }; null }
                }
                "arrived" -> {
                    val files = call.argument<List<Map<String, Any?>>>("files").orEmpty().mapNotNull {
                        val uri = it["uri"] as? String
                        val name = it["name"] as? String
                        if (uri == null) null else Arrivals.File(Uri.parse(uri), name ?: "file")
                    }
                    Arrivals.show(
                        app,
                        from = call.argument<String>("from") ?: "your PC",
                        files = files,
                        clip = call.argument<Boolean>("clip") == true,
                    )
                    result.success(null)
                }
                "open" -> {
                    call.argument<String>("uri")?.let { Arrivals.open(app, Uri.parse(it)) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Runs [work] on the writer thread and answers with what it returns, or an error. */
    private fun answer(result: MethodChannel.Result, work: () -> Any?) {
        writer.execute {
            val outcome = try {
                Result.success(work())
            } catch (e: Exception) {
                Result.failure(e)
            }
            main.post {
                outcome.fold(
                    { result.success(it) },
                    { result.error("save", it.javaClass.simpleName, null) },
                )
            }
        }
    }

    private fun create(context: Context, name: String, size: Long): Int {
        if (size > 0) {
            @Suppress("DEPRECATION")
            val free = StatFs(Environment.getExternalStorageDirectory().path).availableBytes
            if (size + SPARE > free) throw IllegalStateException("No room")
        }
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeOf(name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, FOLDER)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Not created")
        val stream = try {
            resolver.openOutputStream(uri, "w")
        } catch (e: Exception) {
            null
        }
        if (stream == null) {
            resolver.delete(uri, null, null)
            throw IllegalStateException("Not opened")
        }
        val handle = next++
        open[handle] = Saving(uri, stream)
        return handle
    }

    private fun write(handle: Int, bytes: ByteArray): Boolean {
        val saving = open[handle] ?: return false
        saving.stream.write(bytes)
        return true
    }

    /** Shows the whole file under its final name; a failure leaves it for [discard]. */
    private fun keep(context: Context, handle: Int): Map<String, String> {
        val saving = open[handle] ?: throw IllegalStateException("Unknown file")
        saving.stream.close()
        val resolver = context.contentResolver
        resolver.update(
            saving.uri,
            ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
            null,
            null,
        )
        var name: String? = null
        resolver.query(saving.uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) name = it.getString(0) }
        open.remove(handle)
        return mapOf("uri" to saving.uri.toString(), "name" to (name ?: ""))
    }

    private fun discard(context: Context, handle: Int) {
        val saving = open.remove(handle) ?: return
        try {
            saving.stream.close()
        } catch (e: Exception) {
            // Closed anyway.
        }
        try {
            context.contentResolver.delete(saving.uri, null, null)
        } catch (e: Exception) {
            // MediaStore drops a pending file left behind after a week.
        }
    }

    fun mimeOf(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
    }
}
