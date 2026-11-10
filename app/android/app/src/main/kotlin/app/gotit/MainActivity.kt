package app.gotit

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Updates: Dart downloads and checks the APK; Android's own installer installs it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.gotit/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                    "openInstallSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
                        )
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("args", "No APK path", null)
                        } else {
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(ApkProvider.uriFor(File(path)), ApkProvider.MIME)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // The phone's name as set in Settings > About phone, which the PC shows,
        // and sealing for the device key (see Sealer).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.gotit/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "name" -> result.success(deviceName())
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
    }

    /**
     * A name the user set wins. Some makers leave the standard setting at the
     * model code and keep the friendly name elsewhere (MIUI: the Bluetooth
     * name), so try that, then the marketing name, then the model code.
     */
    private fun deviceName(): String {
        val set = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)?.trim()
        if (!set.isNullOrEmpty() && set != Build.MODEL) return set
        val bluetooth = try {
            Settings.Secure.getString(contentResolver, "bluetooth_name")?.trim()
        } catch (e: SecurityException) {
            null
        }
        if (!bluetooth.isNullOrEmpty()) return bluetooth
        val market = systemProperty("ro.product.marketname")?.trim()
        if (!market.isNullOrEmpty()) return market
        return set?.takeIf { it.isNotEmpty() } ?: Build.MODEL
    }

    private fun systemProperty(key: String): String? = try {
        Class.forName("android.os.SystemProperties")
            .getMethod("get", String::class.java)
            .invoke(null, key) as? String
    } catch (e: Exception) {
        null
    }
}
