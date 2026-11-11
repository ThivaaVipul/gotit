package app.gotit

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Invisible: takes focus for a moment, which is when Android lets an app
 * read the clipboard, reads it once and closes. The notification's Send
 * button opens it.
 */
class ReadClipActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private var done = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
        // Never stay around if focus doesn't come.
        main.postDelayed({
            if (!done) {
                done = true
                close()
            }
        }, FOCUS_WAIT_MS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !done) {
            done = true
            PhoneClipboard.read(this)?.let {
                Channels.copied(it.text, it.sensitive, it.copiedAt, manual = true)
            }
            close()
        }
    }

    private fun close() {
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    private companion object {
        const val FOCUS_WAIT_MS = 1500L
    }
}
