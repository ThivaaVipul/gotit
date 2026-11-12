package app.gotit

import android.app.NotificationManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The app-wide channels between Kotlin and Dart. They live with the engine,
 * not with a window, so they work while the app runs in the background.
 */
object Channels {
    private val main = Handler(Looper.getMainLooper())
    private var clipboard: MethodChannel? = null
    private var setup: MethodChannel? = null
    private var sharing: MethodChannel? = null

    // The setup steps you mark done yourself, and whether their page was opened.
    const val SETUP_PREFS = "setup"
    private const val PREFS = SETUP_PREFS
    private const val AUTOSTART = "autostartDone"
    private const val AUTOSTART_OPENED = "autostartOpened"
    private const val LOCKED = "lockedDone"

    // The quick settings tile: added, or Android's prompt answered either way.
    const val TILE_ADDED = "tileAdded"
    private const val TILE_ASKED = "tileAsked"

    fun register(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        val messenger = engine.dartExecutor.binaryMessenger

        // Updates: Dart downloads and checks the APK; Android's own installer installs it.
        MethodChannel(messenger, "app.gotit/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(app.packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    app.startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("args", "No APK path", null)
                    } else {
                        app.startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(ApkProvider.uriFor(File(path)), ApkProvider.MIME)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // The phone's name, which the PC shows, and sealing for the device key.
        MethodChannel(messenger, "app.gotit/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "name" -> result.success(DeviceName.of(app))
                "seal", "open" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.error("args", "No bytes", null)
                    } else {
                        try {
                            result.success(if (call.method == "seal") Sealer.seal(bytes) else Sealer.open(bytes))
                        } catch (e: Exception) {
                            result.error("sealer", e.javaClass.simpleName, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Copies: Dart writes what arrives from the PC; Kotlin hands up what was copied here.
        clipboard = MethodChannel(messenger, "app.gotit/clipboard").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "write" -> {
                        val text = call.argument<String>("text")
                        val image = call.argument<ByteArray>("image")
                        when {
                            image != null -> {
                                PhoneClipboard.writeImage(app, image)
                                result.success(null)
                            }
                            text != null -> {
                                PhoneClipboard.write(app, text, call.argument<Boolean>("sensitive") == true)
                                result.success(null)
                            }
                            else -> result.error("args", "No text or image", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // The ongoing notification: what it says, and whether it is there.
        MethodChannel(messenger, "app.gotit/service").setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> result.success(
                    LinkService.show(
                        app,
                        call.argument<String>("title") ?: "Gotit",
                        call.argument<String>("text"),
                        sharing = call.argument<Boolean>("sharing") ?: true,
                        percent = call.argument<Int>("percent"),
                        cancel = call.argument<String>("cancel"),
                    ),
                )
                "hide" -> {
                    LinkService.hide(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // The setup checklist: what is done, and the pages that do the rest.
        // Kotlin also calls "watcher" when the copy watcher starts or stops.
        setup = MethodChannel(messenger, "app.gotit/setup").apply {
            setMethodCallHandler { call, result -> onSetupCall(app, call, result) }
        }

        // Share > Gotit, and the notification's Cancel.
        ShareRelay.register(messenger)

        // Files from the PC: Download/Gotit, and the notice when they arrived.
        PhoneSaves.register(app, messenger)

        // The sharing switch: Dart sends it here for the tile and the copy
        // watcher; Kotlin sends back taps on the tile and the notification.
        sharing = MethodChannel(messenger, "app.gotit/sharing").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        Sharing.update(
                            app,
                            on = call.argument<Boolean>("on") ?: true,
                            paired = call.argument<Boolean>("paired") ?: false,
                            screenshots = call.argument<Boolean>("screenshots") ?: true,
                        )
                        result.success(null)
                    }
                    "ready" -> result.success(Sharing.dartReady())
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** The tile or a notification button asked to turn sharing on or off. */
    fun sharingRequested(on: Boolean) {
        main.post { sharing?.invokeMethod("set", on) }
    }

    private fun onSetupCall(app: Context, call: MethodCall, result: MethodChannel.Result) {
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        when (call.method) {
            "status" -> result.success(
                mapOf(
                    "notifications" to app.getSystemService(NotificationManager::class.java)
                        .areNotificationsEnabled(),
                    "battery" to app.getSystemService(PowerManager::class.java)
                        .isIgnoringBatteryOptimizations(app.packageName),
                    "watcher" to CopyWatchService.state(app),
                    // Android 13 and later grey out the accessibility switch of
                    // apps installed from outside a store until "Allow
                    // restricted settings" is chosen. Apps can't read that
                    // setting (a SecurityException), so Dart offers the way
                    // there whenever the watcher is off.
                    "restricted" to (Build.VERSION.SDK_INT >= 33),
                    "autostart" to prefs.getBoolean(AUTOSTART, false),
                    "autostartOpened" to prefs.getBoolean(AUTOSTART_OPENED, false),
                    "locked" to prefs.getBoolean(LOCKED, false),
                    // Android 13 and later can offer to add the tile.
                    "tileSupported" to (Build.VERSION.SDK_INT >= 33),
                    "tile" to (prefs.getBoolean(TILE_ADDED, false) || prefs.getBoolean(TILE_ASKED, false)),
                    "screenshots" to Sharing.screenshots,
                    "photos" to Screenshots.allowed(app),
                    "maker" to Build.MANUFACTURER,
                ),
            )
            "battery" -> {
                // Android's own "let it run in the background" prompt; its list as a fallback.
                open(
                    app,
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${app.packageName}")),
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                )
                result.success(null)
            }
            "watcher" -> {
                // Apps can't open a service's own page (Settings guards it), so
                // the list, asking Settings to highlight Gotit where it can.
                val me = ComponentName(app, CopyWatchService::class.java).flattenToString()
                open(
                    app,
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .putExtra(":settings:fragment_args_key", me)
                        .putExtra(":settings:show_fragment_args", Bundle().apply {
                            putString(":settings:fragment_args_key", me)
                        }),
                    Intent(Settings.ACTION_SETTINGS),
                )
                result.success(null)
            }
            "appInfo" -> {
                // "Allow restricted settings": a switch at the bottom of MIUI's
                // app info page, in the menu on other phones.
                open(app, appInfo(app), Intent(Settings.ACTION_SETTINGS))
                result.success(null)
            }
            "autostart" -> {
                // MIUI's Autostart list (in its Security app); app info otherwise.
                prefs.edit().putBoolean(AUTOSTART_OPENED, true).apply()
                open(
                    app,
                    Intent().setComponent(
                        ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity",
                        ),
                    ),
                    appInfo(app),
                )
                result.success(null)
            }
            "mark" -> {
                when (call.argument<String>("step")) {
                    "autostart" -> prefs.edit().putBoolean(AUTOSTART, true).apply()
                    "locked" -> prefs.edit().putBoolean(LOCKED, true).apply()
                }
                result.success(null)
            }
            "tile" -> {
                // Android's own "Add tile?" prompt. Answers once it was answered.
                if (Build.VERSION.SDK_INT < 33) {
                    result.success(false)
                } else {
                    app.getSystemService(StatusBarManager::class.java).requestAddTileService(
                        ComponentName(app, SharingTile::class.java),
                        app.getString(R.string.tile_label),
                        Icon.createWithResource(app, R.drawable.ic_stat_gotit),
                        app.mainExecutor,
                    ) { answer ->
                        // 0 not added, 1 already there, 2 added; below 0 the prompt never showed.
                        if (answer >= 0) prefs.edit().putBoolean(TILE_ASKED, true).apply()
                        if (answer == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                            answer == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
                        ) {
                            prefs.edit().putBoolean(TILE_ADDED, true).apply()
                        }
                        result.success(answer >= 0)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** The copy watcher started or stopped. */
    fun watcherChanged(context: Context) {
        val state = CopyWatchService.state(context.applicationContext)
        main.post { setup?.invokeMethod("watcher", state) }
    }

    private fun appInfo(context: Context) =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))

    private fun open(context: Context, page: Intent, fallback: Intent) {
        try {
            context.startActivity(page.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: RuntimeException) {
            context.startActivity(fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /** An image copied here, or a new screenshot, as PNG. Any thread. */
    fun copiedImage(png: ByteArray, copiedAt: Long, manual: Boolean) {
        main.post {
            clipboard?.invokeMethod(
                "copied",
                mapOf("image" to png, "at" to copiedAt, "manual" to manual),
            )
        }
    }

    /** Hands a copy made on this phone to Dart, which decides whether it crosses. */
    fun copied(text: String, sensitive: Boolean, copiedAt: Long, manual: Boolean) {
        main.post {
            clipboard?.invokeMethod(
                "copied",
                mapOf("text" to text, "sensitive" to sensitive, "at" to copiedAt, "manual" to manual),
            )
        }
    }
}
