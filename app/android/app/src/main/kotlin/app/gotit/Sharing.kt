package app.gotit

import android.content.Context

/**
 * The sharing switch as Kotlin sees it. Dart owns the switch (both devices
 * share it); Kotlin keeps a copy for the quick settings tile and for the copy
 * watcher, which reads nothing while sharing is off. Taps on the tile and on
 * the notification's buttons go back to Dart. Main thread only, apart from
 * reading [on].
 */
object Sharing {
    private const val PREFS = "sharing"
    private const val ON = "on"
    private const val PAIRED = "paired"
    private const val SCREENSHOTS = "screenshots"

    @Volatile
    var on = true
        private set

    /** There is a PC to share with: the tile is unavailable until then. */
    @Volatile
    var paired = false
        private set

    /** New screenshots go to the PC (a Settings switch, on unless turned off). */
    @Volatile
    var screenshots = true
        private set

    private var loaded = false
    private var dartListening = false
    private var pending: Boolean? = null

    /** The last known switch, so the tile and the watcher are right from the start. */
    fun load(context: Context) {
        if (loaded) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        on = prefs.getBoolean(ON, true)
        paired = prefs.getBoolean(PAIRED, false)
        screenshots = prefs.getBoolean(SCREENSHOTS, true)
        loaded = true
    }

    /** From Dart: the switch, whether there is a PC to share with, and the screenshot switch. */
    fun update(context: Context, on: Boolean, paired: Boolean, screenshots: Boolean) {
        this.on = on
        this.paired = paired
        this.screenshots = screenshots
        loaded = true
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(ON, on)
            .putBoolean(PAIRED, paired)
            .putBoolean(SCREENSHOTS, screenshots)
            .apply()
        SharingTile.refresh(context)
    }

    /** The tile or a notification button: turn sharing on or off. */
    fun request(context: Context, on: Boolean) {
        load(context)
        if (dartListening) Channels.sharingRequested(on) else pending = on
        // Shown at once; Dart confirms with update().
        this.on = on
        SharingTile.refresh(context)
    }

    /** Dart now listens. Returns a request made before it did, if any. */
    fun dartReady(): Boolean? {
        dartListening = true
        return pending.also { pending = null }
    }
}
