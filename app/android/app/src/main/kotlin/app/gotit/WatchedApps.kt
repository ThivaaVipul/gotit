package app.gotit

import android.content.Context

/**
 * Which apps the copy watcher checks the screen of, learned per app.
 *
 * Checking the screen a few times a second costs about 6% of a CPU core, so
 * it is only for apps that may copy without telling: those that never report
 * taps (Jetpack Compose and Flutter apps), and those where a copy was only
 * ever caught by the screen check. An app that reports taps is left alone
 * unless it is known to need the check.
 */
object WatchedApps {
    private const val PREFS = "watcher"
    private const val TAPS = "reportsTaps"
    private const val CHECK = "needsCheck"

    /** Known to copy from a menu that announces nothing at all. */
    private val alwaysChecked = setOf("com.google.android.apps.messaging")

    private var taps: MutableSet<String>? = null
    private var check: MutableSet<String>? = null

    @Synchronized
    fun shouldCheck(context: Context, app: String): Boolean {
        load(context)
        return app in alwaysChecked || app in check!! || app !in taps!!
    }

    /** The app reported a tap, so a tap on its Copy items will be seen. */
    @Synchronized
    fun reportsTaps(context: Context, app: String) {
        load(context)
        if (taps!!.add(app)) save(context, TAPS, taps!!)
    }

    /** A copy here was caught only by the screen check: keep checking it. */
    @Synchronized
    fun needsCheck(context: Context, app: String) {
        load(context)
        if (check!!.add(app)) save(context, CHECK, check!!)
    }

    private fun load(context: Context) {
        if (taps != null) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        taps = prefs.getStringSet(TAPS, emptySet())!!.toMutableSet()
        check = prefs.getStringSet(CHECK, emptySet())!!.toMutableSet()
    }

    private fun save(context: Context, key: String, apps: Set<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet(key, apps.toSet()).apply()
    }
}
