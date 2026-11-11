package app.gotit

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/** Why the clipboard is being read: a signal the watcher caught, or Send. */
data class CopyTrigger(
    val kind: String,
    /** The app the signal came from, as far as known. */
    val app: String,
    /** SystemClock.uptimeMillis() of the signal. */
    val uptime: Long,
    /** System.currentTimeMillis() of the signal. */
    val wallTime: Long,
    val attempt: Int = 1,
) {
    val manual: Boolean get() = kind == SEND

    fun putInto(intent: Intent): Intent = intent
        .putExtra(EXTRA_KIND, kind)
        .putExtra(EXTRA_APP, app)
        .putExtra(EXTRA_UPTIME, uptime)
        .putExtra(EXTRA_WALL, wallTime)
        .putExtra(EXTRA_ATTEMPT, attempt)

    companion object {
        /** The notification's Send button. */
        const val SEND = "send"

        /** A tap on a Copy button or menu item. */
        const val TAP = "tap"

        /** A "Copied" notice. */
        const val NOTICE = "notice"

        /** A Copy item inside the screen went away: maybe tapped, maybe dismissed. */
        const val GONE = "gone"

        /** A popup window with a Copy item closed: maybe tapped, maybe dismissed. */
        const val POPUP = "popup"

        private const val EXTRA_KIND = "gotit.kind"
        private const val EXTRA_APP = "gotit.app"
        private const val EXTRA_UPTIME = "gotit.uptime"
        private const val EXTRA_WALL = "gotit.wall"
        private const val EXTRA_ATTEMPT = "gotit.attempt"

        fun now(kind: String, app: String) =
            CopyTrigger(kind, app, SystemClock.uptimeMillis(), System.currentTimeMillis())

        /** An intent without extras is a tap on Send. */
        fun from(intent: Intent): CopyTrigger = CopyTrigger(
            kind = intent.getStringExtra(EXTRA_KIND) ?: SEND,
            app = intent.getStringExtra(EXTRA_APP) ?: "",
            uptime = intent.getLongExtra(EXTRA_UPTIME, SystemClock.uptimeMillis()),
            wallTime = intent.getLongExtra(EXTRA_WALL, System.currentTimeMillis()),
            attempt = intent.getIntExtra(EXTRA_ATTEMPT, 1),
        )
    }
}

/**
 * Decides what a read found and hands real copies to Dart. The log holds
 * kinds, lengths and timings only, never what was copied.
 */
object CopyReads {
    private const val TAG = "Gotit"

    /** A clip copied longer than this before the signal is the previous one. */
    private const val FRESH_MS = 3000L

    private var lastFingerprint: Int? = null

    fun report(context: Context, trigger: CopyTrigger, via: String, copy: PhoneClipboard.Copy?) {
        val after = SystemClock.uptimeMillis() - trigger.uptime
        if (trigger.manual) {
            copy?.let { Channels.copied(it.text, it.sensitive, it.copiedAt, manual = true) }
            return
        }
        if (copy == null) {
            Log.d(TAG, "watch: ${trigger.kind}, nothing read via $via after ${after}ms")
            return
        }
        // Text from the PC, written here by Gotit: never send it back.
        if (copy.ours) return
        if (copy.copiedAt < trigger.wallTime - FRESH_MS) {
            // The app may set its clip a moment after the signal: one more look.
            if (trigger.attempt == 1) CopyWatchService.instance?.retry(trigger.copy(attempt = 2))
            return
        }
        // One copy can fire several signals.
        val fingerprint = 31 * copy.text.hashCode() + copy.copiedAt.hashCode()
        if (fingerprint == lastFingerprint) return
        lastFingerprint = fingerprint
        if (trigger.kind == CopyTrigger.GONE) WatchedApps.needsCheck(context, trigger.app)
        Log.d(TAG, "watch: ${trigger.kind}, caught via $via after ${after}ms, ${copy.text.length} chars")
        Channels.copied(copy.text, copy.sensitive, copy.copiedAt, manual = false)
    }
}
