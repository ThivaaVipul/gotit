package app.gotit

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.provider.MediaStore
import android.util.Log

/**
 * New phone screenshots go to the PC's clipboard. Android has no screenshot
 * event for other apps, so Gotit watches the photo library for new files in a
 * Screenshots folder and opens only those, once each. It needs Photos access,
 * and does nothing while unpaired, while sharing is off, or when its Settings
 * switch is off.
 */
object Screenshots {
    private const val TAG = "Gotit"

    /** A screenshot older than this when noticed isn't new. */
    private const val NEW_FOR_SECONDS = 20L

    /** Let the file finish being written before it is read. */
    private const val SETTLE_MS = 600L

    private val worker = HandlerThread("gotit-screenshots").apply { start() }
    private val handler = Handler(worker.looper)
    private var watching = false

    /** The newest screenshot already seen; set at start, then on the worker thread. */
    @Volatile
    private var lastId = -1L

    private val permission: String
        get() = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    /** Android lets Gotit open the photo library. */
    fun allowed(context: Context): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun permissionName(): String = permission

    /** Starts watching once Photos access is there. Safe to call again. */
    fun start(context: Context) {
        val app = context.applicationContext
        if (watching || !allowed(app)) return
        watching = true
        app.contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    // A new screenshot changes the library several times: look once it settles.
                    handler.removeCallbacksAndMessages(LOOK)
                    handler.postAtTime({ look(app) }, LOOK, android.os.SystemClock.uptimeMillis() + SETTLE_MS)
                }
            },
        )
        // What is already there isn't new.
        lastId = newest(app)?.id ?: -1L
    }

    private val LOOK = Any()

    private data class Shot(val id: Long, val addedSeconds: Long, val size: Long)

    /** Worker thread. */
    private fun look(context: Context) {
        if (!allowed(context)) return
        val shot = newest(context) ?: return
        if (shot.id <= lastId || shot.size <= 0) return
        lastId = shot.id
        // Taken while sharing was off, unpaired or with the switch off: it
        // stays on the phone, even if sharing comes back on a moment later.
        if (!(Sharing.screenshots && Sharing.on && LinkService.running)) return
        if (System.currentTimeMillis() / 1000 - shot.addedSeconds > NEW_FOR_SECONDS) return
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, shot.id)
        val png = PhoneClipboard.toPng(context, uri)
        if (png == null) {
            Log.d(TAG, "screenshot: unreadable or too big")
            return
        }
        Log.d(TAG, "screenshot: new, ${png.size / 1024} KB")
        Channels.copiedImage(png, shot.addedSeconds * 1000, manual = false)
    }

    /** The newest image in a Screenshots folder that has finished being written. */
    private fun newest(context: Context): Shot? {
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.SIZE,
        )
        val selection = "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ? AND ${MediaStore.MediaColumns.IS_PENDING} = 0"
        return try {
            context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                arrayOf("%Screenshots%"),
                "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                Shot(cursor.getLong(0), cursor.getLong(1), cursor.getLong(2))
            }
        } catch (e: RuntimeException) {
            null
        }
    }
}
