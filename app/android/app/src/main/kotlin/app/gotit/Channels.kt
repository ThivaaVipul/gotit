package app.gotit

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The app-wide channels between Kotlin and Dart. They live with the engine,
 * not with a window, so they work while the app runs in the background.
 */
object Channels {
    private val main = Handler(Looper.getMainLooper())
    private var clipboard: MethodChannel? = null

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
                        if (text == null) {
                            result.error("args", "No text", null)
                        } else {
                            PhoneClipboard.write(app, text, call.argument<Boolean>("sensitive") == true)
                            result.success(null)
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
                    LinkService.show(app, call.argument<String>("title") ?: "Gotit", call.argument<String>("text")),
                )
                "hide" -> {
                    LinkService.hide(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // The setup checklist: what is done, and the pages that do the rest.
        MethodChannel(messenger, "app.gotit/setup").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "notifications" to app.getSystemService(NotificationManager::class.java)
                            .areNotificationsEnabled(),
                        "battery" to app.getSystemService(PowerManager::class.java)
                            .isIgnoringBatteryOptimizations(app.packageName),
                        "maker" to Build.MANUFACTURER,
                    ),
                )
                "battery" -> {
                    // Android's own "let it run in the background" prompt; its list as a fallback.
                    val asked = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:${app.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        app.startActivity(asked)
                    } catch (e: RuntimeException) {
                        app.startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
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
