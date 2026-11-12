package app.gotit

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Between the share sheet (and the notification's Cancel) and Dart, on the
 * app.gotit/share channel. A share that starts the app waits here until Dart
 * listens. Dart answers each share with what happened: "sending", "sent",
 * "off", "away:<PC name>" or "unpaired".
 */
object ShareRelay {
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var dartListening = false
    private val waiting = ArrayList<Pair<Map<String, Any?>, (String) -> Unit>>()

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "app.gotit/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        dartListening = true
                        result.success(null)
                        val pending = ArrayList(waiting)
                        waiting.clear()
                        pending.forEach { (share, answer) -> send(share, answer) }
                    }
                    "read" -> {
                        val handle = call.argument<Int>("handle")
                        val max = call.argument<Int>("max") ?: (256 * 1024)
                        if (handle == null) {
                            result.error("args", "No handle", null)
                        } else {
                            PhoneFiles.read(handle, max) { bytes -> result.success(bytes) }
                        }
                    }
                    "close" -> {
                        call.argument<Int>("handle")?.let { PhoneFiles.close(it) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Hands a share to Dart: [text], or [files] already open. [turnOn] turns
     * sharing on first ("Turn on and send"). [answer] runs on the main thread.
     */
    fun share(
        text: String?,
        files: List<PhoneFiles.Shared>,
        turnOn: Boolean,
        answer: (String) -> Unit,
    ) {
        val share = mapOf(
            "text" to text,
            "files" to files.map { mapOf("handle" to it.handle, "name" to it.name, "size" to it.size) },
            "turnOn" to turnOn,
        )
        main.post {
            if (dartListening) send(share, answer) else waiting.add(share to answer)
        }
    }

    /** The notification's Cancel: stops the file on its way. */
    fun cancel(id: String) {
        main.post { channel?.invokeMethod("cancel", id) }
    }

    private fun send(share: Map<String, Any?>, answer: (String) -> Unit) {
        val channel = channel
        if (channel == null) {
            answer("failed")
            return
        }
        channel.invokeMethod(
            "shared",
            share,
            object : MethodChannel.Result {
                override fun success(result: Any?) = answer(result as? String ?: "failed")

                override fun error(code: String, message: String?, details: Any?) = answer("failed")

                override fun notImplemented() = answer("failed")
            },
        )
    }
}

/** The notification's Cancel button. */
class CancelReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        intent.getStringExtra(ID)?.let { ShareRelay.cancel(it) }
    }

    companion object {
        const val ID = "id"
    }
}
