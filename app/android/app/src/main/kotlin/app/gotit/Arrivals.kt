package app.gotit

import android.app.Activity
import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.widget.Toast
import java.util.concurrent.atomic.AtomicInteger

/**
 * Files that arrived from the PC: a notice saying so, with Open (Open folder
 * for several) and Share, and a single image also on the clipboard.
 */
object Arrivals {
    /** A file kept in Download/Gotit. */
    data class File(val uri: Uri, val name: String)

    private const val CHANNEL = "files"

    // Notice IDs, each with its own buttons; 1 is the ongoing notification.
    private val ids = AtomicInteger(1000 + (System.currentTimeMillis() / 1000 % 100_000).toInt())

    fun show(context: Context, from: String, files: List<File>, clip: Boolean) {
        if (files.isEmpty()) return
        if (clip) PhoneClipboard.writeUri(context, files[0].uri)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    context.getString(R.string.files_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
        val id = ids.incrementAndGet()
        val one = files.size == 1
        val text = when {
            one && clip -> context.getString(R.string.files_on_clipboard, files[0].name)
            one -> files[0].name
            else -> context.getString(R.string.files_count, files.size)
        }
        val uris = ArrayList(files.map { it.uri.toString() })
        val open = action(context, id, 0, if (one) FileActionActivity.OPEN else FileActionActivity.FOLDER, uris)
        val share = action(context, id, 1, FileActionActivity.SHARE, uris)
        val notice = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_gotit)
            .setContentTitle(context.getString(R.string.files_from, from))
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(open)
            .addAction(button(context, if (one) R.string.files_open else R.string.files_open_folder, open))
            .addAction(button(context, R.string.files_share, share))
            .build()
        manager.notify(id, notice)
    }

    /** Opens [uri] with its usual app. */
    fun open(context: Context, uri: Uri) {
        val type = context.contentResolver.getType(uri) ?: "*/*"
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (!start(context, view)) say(context, R.string.files_no_app)
    }

    /** Shows Download/Gotit in the Files app, or the downloads list. */
    fun openFolder(context: Context) {
        val folder = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Download/Gotit",
        )
        val files = Intent(Intent.ACTION_VIEW).setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
        if (!start(context, files) && !start(context, Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))) {
            say(context, R.string.files_no_app)
        }
    }

    /** Android's share sheet, for [uris]. */
    fun share(context: Context, uris: List<Uri>) {
        if (uris.isEmpty()) return
        val types = uris.map { context.contentResolver.getType(it) ?: "*/*" }
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).setType(types[0]).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE)
                .setType(if (types.all { it.startsWith("image/") }) "image/*" else "*/*")
                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        }
        // The chooser passes read access on to the app that is picked.
        send.clipData = ClipData.newRawUri(null, uris[0]).apply {
            uris.drop(1).forEach { addItem(ClipData.Item(it)) }
        }
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        start(context, Intent.createChooser(send, null))
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    private fun say(context: Context, text: Int) {
        Toast.makeText(context.applicationContext, text, Toast.LENGTH_SHORT).show()
    }

    private fun action(context: Context, notice: Int, slot: Int, what: String, uris: ArrayList<String>): PendingIntent =
        PendingIntent.getActivity(
            context,
            notice * 2 + slot,
            Intent(context, FileActionActivity::class.java)
                .putExtra(FileActionActivity.ACTION, what)
                .putExtra(FileActionActivity.NOTICE, notice)
                .putStringArrayListExtra(FileActionActivity.URIS, uris)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                ),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun button(context: Context, label: Int, intent: PendingIntent) =
        Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_stat_gotit),
            context.getString(label),
            intent,
        ).build()
}

/**
 * An arrival notice's Open, Open folder and Share. Invisible: it closes the
 * notice, opens what was asked, and closes.
 */
class FileActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val notice = intent.getIntExtra(NOTICE, 0)
        if (notice != 0) getSystemService(NotificationManager::class.java).cancel(notice)
        val uris = intent.getStringArrayListExtra(URIS).orEmpty().map(Uri::parse)
        when (intent.getStringExtra(ACTION)) {
            OPEN -> uris.firstOrNull()?.let { Arrivals.open(this, it) }
            FOLDER -> Arrivals.openFolder(this)
            SHARE -> Arrivals.share(this, uris)
        }
        finish()
    }

    companion object {
        const val ACTION = "action"
        const val NOTICE = "notice"
        const val URIS = "uris"
        const val OPEN = "open"
        const val FOLDER = "folder"
        const val SHARE = "share"
    }
}
