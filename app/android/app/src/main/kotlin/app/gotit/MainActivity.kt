package app.gotit

import android.content.Intent
import android.net.Uri
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
    }
}
