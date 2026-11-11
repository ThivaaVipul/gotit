package app.gotit

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Invisible: takes focus for a moment, which is when Android lets an app
 * read the clipboard, reads it once and closes. The notification's Send
 * button opens it, and so does the copy watcher when its overlay gets no
 * focus (the phone is still busy just after a restart).
 */
class ReadClipActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private var done = false
    private lateinit var trigger: CopyTrigger

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
        trigger = CopyTrigger.from(intent)
        // Never stay around if focus doesn't come.
        main.postDelayed({
            if (!done) {
                done = true
                CopyReads.report(this, trigger, "activity", null)
                close()
            }
        }, FOCUS_WAIT_MS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !done) {
            done = true
            CopyReads.report(this, trigger, "activity", PhoneClipboard.read(this))
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
