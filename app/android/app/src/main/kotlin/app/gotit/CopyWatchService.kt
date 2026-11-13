package app.gotit

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The copy watcher, as proven in M0. It notices a copy made on this phone,
 * then takes focus for a moment, which is when Android lets it read the
 * clipboard: with a 1-pixel invisible overlay, or with the invisible
 * [ReadClipActivity] when the overlay gets no focus. Signals:
 * - a tap on a Copy button or menu item;
 * - a "Copied" notice;
 * - a Copy item leaving the screen: in a separate window (popups), and inside
 *   the screen of apps that may copy without telling ([WatchedApps]), whose
 *   screen is also checked a few times a second while it is on.
 *
 * It reads only while paired (the link service runs then) and sharing is
 * on, and hands what it reads to [CopyReads].
 */
class CopyWatchService : AccessibilityService() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = HandlerThread("gotit-watch").apply { start() }
    private val scanner = Handler(worker.looper)
    private val scanQueued = AtomicBoolean(false)
    private var overlay: View? = null
    private var lastReadUptime = 0L

    /** Separate windows that opened with a Copy item: window id to app. Main thread only. */
    private val copyWindows = HashMap<Int, String>()

    /** A Copy item inside the screen, checked again until it goes. Set on the worker thread. */
    @Volatile
    private var copyNode: AccessibilityNodeInfo? = null
    private var copyNodeApp: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        prefs(this).edit().putBoolean(RAN, true).apply()
        copyWindows.clear()
        scanner.postDelayed(poll, POLL_MS)
        Channels.watcherChanged(this)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        instance = null
        scanner.removeCallbacksAndMessages(null)
        removeOverlay()
        worker.quitSafely()
        Channels.watcherChanged(this)
        super.onDestroy()
    }

    /** Some menus open without any event (Google Messages): look a few times a second. */
    private val poll = object : Runnable {
        override fun run() {
            if (watching() && !scanQueued.get() &&
                getSystemService(PowerManager::class.java).isInteractive &&
                (copyNode != null || frontNeedsCheck())
            ) {
                scanScreen()
            }
            scanner.postDelayed(this, POLL_MS)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!watching()) return
        val type = event.eventType
        if (type == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            onWindowsChanged(event)
            queueScreenScan()
            return
        }
        val app = event.packageName?.toString() ?: return
        if (app == packageName) return
        if (type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            if (copyNode != null || WatchedApps.shouldCheck(this, app)) queueScreenScan()
            return
        }
        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) queueScreenScan()
        val text = event.text.joinToString(" ")
        val desc = event.contentDescription?.toString().orEmpty()
        val clicked = type == AccessibilityEvent.TYPE_VIEW_CLICKED
        if (clicked) WatchedApps.reportsTaps(this, app)
        val isToast = type == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED &&
            event.parcelableData !is Notification
        val kind = when {
            clicked && (
                Words.isCopyLabel(text) || Words.isCopyLabel(desc) ||
                    sourceId(event)?.contains("copy", ignoreCase = true) == true
                ) -> CopyTrigger.TAP
            (isToast || type == AccessibilityEvent.TYPE_ANNOUNCEMENT ||
                type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) &&
                (Words.isCopiedNotice(text) || Words.isCopiedNotice(desc)) -> CopyTrigger.NOTICE
            else -> return
        }
        // Taking focus makes other windows redraw: never let that echo into another read.
        if (kind != CopyTrigger.TAP && cooling()) return
        trigger(kind, app)
    }

    // --- Copy items inside the screen ---

    /** Worker thread: is the app in front one whose screen is checked? */
    private fun frontNeedsCheck(): Boolean {
        val app = try {
            rootInActiveWindow?.packageName?.toString()
        } catch (e: RuntimeException) {
            null
        } ?: return false
        return app != packageName && WatchedApps.shouldCheck(this, app)
    }

    private fun queueScreenScan() {
        if (scanQueued.compareAndSet(false, true)) {
            scanner.postDelayed({ scanScreen() }, SCAN_DELAY_MS)
        }
    }

    /** Worker thread. While a Copy item is held, only check that one item again. */
    private fun scanScreen() {
        scanQueued.set(false)
        val held = copyNode
        if (held != null) {
            val still = try {
                held.refresh() && held.isVisibleToUser
            } catch (e: RuntimeException) {
                false
            }
            if (still) return
            val app = copyNodeApp.orEmpty()
            copyNode = null
            copyNodeApp = null
            main.post { copyItemGone(app, CopyTrigger.GONE) }
            return
        }
        // The focused window plus any other app windows on screen (sheets, dialogs, popups).
        val roots = try {
            val list = windows.filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
                .sortedByDescending { it.layer }
                .mapNotNull { it.root }
            val active = rootInActiveWindow
            if (active != null && list.none { it.windowId == active.windowId }) listOf(active) + list else list
        } catch (e: RuntimeException) {
            emptyList()
        }
        val app = roots.firstOrNull()?.packageName?.toString() ?: return
        if (app == packageName || !WatchedApps.shouldCheck(this, app)) return
        var seen = 0
        for (root in roots) {
            if (root.packageName?.toString() == packageName) continue
            val (found, count) = try {
                findCopyItem(root, MAX_SCREEN_NODES - seen)
            } catch (e: RuntimeException) {
                null to 0
            }
            seen += count
            if (found != null) {
                copyNode = found
                copyNodeApp = app
                return
            }
        }
    }

    // --- Copy items in separate windows (popups, toolbars) ---

    private fun onWindowsChanged(event: AccessibilityEvent) {
        val id = event.windowId
        val changes = event.windowChanges
        if ((changes and AccessibilityEvent.WINDOWS_CHANGE_REMOVED) != 0) {
            copyWindows.remove(id)?.let { copyItemGone(it, CopyTrigger.POPUP) }
        }
        if ((changes and AccessibilityEvent.WINDOWS_CHANGE_ADDED) != 0) {
            val window = try {
                windows.firstOrNull { it.id == id }
            } catch (e: RuntimeException) {
                null
            } ?: return
            // A system "copied to clipboard" window.
            if (window.title?.toString()?.contains("clip", ignoreCase = true) == true && !cooling()) {
                trigger(CopyTrigger.NOTICE, "")
            }
            scanner.postDelayed({ scanWindow(window, 1) }, FIRST_WINDOW_SCAN_MS)
        }
    }

    /** Worker thread: does this new window offer a Copy item? */
    private fun scanWindow(window: AccessibilityWindowInfo, attempt: Int) {
        val root = try {
            window.root
        } catch (e: RuntimeException) {
            null
        } ?: return
        val app = root.packageName?.toString() ?: return
        if (app == packageName) return
        val node = try {
            findCopyItem(root, MAX_WINDOW_NODES).first
        } catch (e: RuntimeException) {
            null
        }
        main.post {
            if (node != null) {
                copyWindows[window.id] = app
            } else if (attempt == 1) {
                scanner.postDelayed({ scanWindow(window, 2) }, SECOND_WINDOW_SCAN_MS)
            }
        }
    }

    /** Main thread. Tapped or dismissed: a read tells which. */
    private fun copyItemGone(app: String, kind: String) {
        if (!cooling() && watching()) trigger(kind, app)
    }

    /**
     * Depth first, newest layers first (menus and scrims are drawn last), so a
     * menu deep inside a busy screen is reached early. Matches a short visible
     * Copy label; nothing else is kept.
     */
    private fun findCopyItem(root: AccessibilityNodeInfo, limit: Int): Pair<AccessibilityNodeInfo?, Int> {
        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.addLast(root)
        var seen = 0
        while (stack.isNotEmpty() && seen < limit) {
            val node = stack.removeLast()
            seen++
            if (node.isVisibleToUser) {
                val desc = node.contentDescription?.toString().orEmpty()
                val text = node.text?.toString().orEmpty()
                if (Words.isCopyItem(desc) || Words.isCopyItem(text)) return node to seen
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let { stack.addLast(it) }
        }
        return null to seen
    }

    // --- Reading ---

    /** Only while paired (the link service runs then) and sharing is on. */
    private fun watching() = LinkService.running && Sharing.on

    private fun cooling(): Boolean = SystemClock.uptimeMillis() - lastReadUptime < COOLDOWN_MS

    /** Main thread. */
    private fun trigger(kind: String, app: String) {
        lastReadUptime = SystemClock.uptimeMillis()
        val t = CopyTrigger.now(kind, app)
        main.postDelayed({ read(t) }, READ_DELAY_MS)
    }

    /** Read again a little later: the app may set its clip after the signal. */
    fun retry(t: CopyTrigger) {
        main.postDelayed({ read(t) }, RETRY_DELAY_MS)
    }

    /**
     * Clears the clipboard if it still holds Gotit's own write of the text
     * whose SHA-256 is [sha]: a sensitive copy whose minute is up. Anything
     * copied since stays. Looked at the same invisible way as a copy.
     */
    fun wipe(sha: String) {
        main.post {
            read(null) { copy ->
                val text = copy?.text
                // Logged by outcome only, never what was there.
                val outcome = when {
                    copy == null -> "nothing to read"
                    !copy.ours || text == null || PhoneClipboard.sha256(text) != sha -> "kept, replaced since"
                    else -> {
                        PhoneClipboard.clear(this)
                        "cleared"
                    }
                }
                Log.d(TAG, "wipe: $outcome")
            }
        }
    }

    /**
     * Reads the clipboard during a moment of focus. With [then], what was
     * read goes there and nothing else happens; otherwise it is a copy to
     * report for [t].
     */
    private fun read(t: CopyTrigger?, then: ((PhoneClipboard.Copy?) -> Unit)? = null) {
        lastReadUptime = SystemClock.uptimeMillis()
        if (overlay != null) {
            if (t == null) Log.d(TAG, "wipe: busy reading, kept")
            return
        }
        val view = object : View(this) {
            private var done = false

            override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
                super.onWindowFocusChanged(hasWindowFocus)
                if (hasWindowFocus && !done) {
                    done = true
                    val copy = PhoneClipboard.read(this@CopyWatchService)
                    main.post { removeOverlay() }
                    if (then != null) {
                        then(copy)
                    } else if (t != null) {
                        CopyReads.report(this@CopyWatchService, t, "overlay", copy)
                    }
                }
            }
        }
        val params = WindowManager.LayoutParams(
            1,
            1,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }
        try {
            getSystemService(WindowManager::class.java).addView(view, params)
            overlay = view
        } catch (e: RuntimeException) {
            // A wipe isn't worth an activity: the clip just stays.
            if (t != null) readWithActivity(t) else Log.d(TAG, "wipe: no overlay, kept")
            return
        }
        // Just after a restart the overlay may get no focus: the activity then.
        main.postDelayed({
            if (overlay === view) {
                removeOverlay()
                if (t != null) readWithActivity(t) else Log.d(TAG, "wipe: no focus, kept")
            }
        }, FOCUS_WAIT_MS)
    }

    private fun readWithActivity(t: CopyTrigger) {
        val intent = t.putInto(Intent(this, ReadClipActivity::class.java)).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
        )
        try {
            startActivity(intent)
        } catch (e: RuntimeException) {
            CopyReads.report(this, t, "activity", null)
        }
    }

    private fun removeOverlay() {
        val view = overlay ?: return
        overlay = null
        try {
            getSystemService(WindowManager::class.java).removeView(view)
        } catch (e: RuntimeException) {
            // Already gone.
        }
    }

    private fun sourceId(event: AccessibilityEvent): String? = try {
        event.source?.viewIdResourceName
    } catch (e: RuntimeException) {
        null
    }

    companion object {
        @Volatile
        var instance: CopyWatchService? = null
            private set

        private const val TAG = "Gotit"

        const val ON = "on"
        const val OFF = "off"

        /** Switched on in Settings but not running: MIUI marks it crashed after the app is killed. */
        const val STOPPED = "stopped"

        /**
         * Switched off after it had run: Android turns it off when MIUI
         * force-stops the app (a swipe-away without Autostart).
         */
        const val TURNED_OFF = "turnedOff"

        private const val RAN = "watcherRan"

        /** Android binds the service a little while after the process starts. */
        const val STARTUP_GRACE_MS = 20_000L

        private const val READ_DELAY_MS = 250L
        private const val RETRY_DELAY_MS = 700L
        private const val FOCUS_WAIT_MS = 800L
        private const val COOLDOWN_MS = 1500L
        private const val SCAN_DELAY_MS = 200L
        private const val POLL_MS = 350L
        private const val FIRST_WINDOW_SCAN_MS = 150L
        private const val SECOND_WINDOW_SCAN_MS = 400L
        private const val MAX_SCREEN_NODES = 1500
        private const val MAX_WINDOW_NODES = 300

        fun state(context: Context): String {
            if (instance != null) return ON
            if (!switchedOn(context)) return if (prefs(context).getBoolean(RAN, false)) TURNED_OFF else OFF
            val age = SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()
            return if (age < STARTUP_GRACE_MS) ON else STOPPED
        }

        private fun prefs(context: Context) = context.getSharedPreferences("watcher", Context.MODE_PRIVATE)

        private fun switchedOn(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val me = ComponentName(context, CopyWatchService::class.java)
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
        }
    }
}
