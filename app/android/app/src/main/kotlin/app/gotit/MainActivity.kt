package app.gotit

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * The app's window. It shows the engine GotitApplication keeps for the
 * process, and leaves it running when it closes.
 */
class MainActivity : FlutterActivity() {
    private var windowChannel: MethodChannel? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(GotitApplication.ENGINE)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Things only a visible window can do.
        windowChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.gotit/activity").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "notifications" -> {
                        askForNotifications()
                        result.success(null)
                    }
                    "photos" -> {
                        askForPhotos()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // A notification posted while notifications were off never shows,
        // so post it again on the way back from the prompt or settings.
        LinkService.repost()
        // Photos access may have just been allowed.
        Screenshots.start(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        windowChannel?.setMethodCallHandler(null)
        windowChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Android's prompt the first time; its settings page once that was answered no. */
    private fun askForNotifications() {
        val prefs = getSharedPreferences("setup", MODE_PRIVATE)
        val granted = Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT >= 33 && !granted && !prefs.getBoolean(ASKED, false)) {
            prefs.edit().putBoolean(ASKED, true).apply()
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        } else {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
            )
        }
    }

    /** For screenshots: Android's prompt the first time; Gotit's app info page after that. */
    private fun askForPhotos() {
        val prefs = getSharedPreferences("setup", MODE_PRIVATE)
        if (!Screenshots.allowed(this) && !prefs.getBoolean(PHOTOS_ASKED, false)) {
            prefs.edit().putBoolean(PHOTOS_ASKED, true).apply()
            requestPermissions(arrayOf(Screenshots.permissionName()), 2)
        } else {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
            )
        }
    }

    private companion object {
        const val ASKED = "notificationsAsked"
        const val PHOTOS_ASKED = "photosAsked"
    }
}
