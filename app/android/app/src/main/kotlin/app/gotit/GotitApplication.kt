package app.gotit

import android.app.Application
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Starts Gotit's Flutter engine with the process and keeps it for the
 * process's whole life, so the link to the PC runs whether or not the app's
 * window is open. MainActivity shows this same engine when it opens.
 */
class GotitApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // The switch as last known, before Dart has started.
        Sharing.load(this)
        val engine = FlutterEngine(this)
        Channels.register(this, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE, engine)
        // A copy watcher that is switched on but never started (MIUI marked it
        // crashed) shows only once Android had its chance to start it.
        Handler(Looper.getMainLooper()).postDelayed(
            { Channels.watcherChanged(this) },
            CopyWatchService.STARTUP_GRACE_MS + 1000,
        )
    }

    companion object {
        const val ENGINE = "gotit"
    }
}
