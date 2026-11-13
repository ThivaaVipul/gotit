package app.gotit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.widget.Toast

/**
 * A link that arrived from the PC: one quiet notice with Open. No sound and
 * no pop-up; the newest link replaces the last, and it goes after 5 minutes.
 * Only web addresses ever open, never another app's scheme.
 */
object Links {
    private const val CHANNEL = "links"

    // One notice for links: 1 is the ongoing notification, and arrival
    // notices count up from 1000.
    private const val ID = 2
    private const val LIFETIME_MS = 5 * 60 * 1000L

    fun show(context: Context, title: String, text: String, url: String) {
        val uri = web(url) ?: return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    context.getString(R.string.links_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val open = PendingIntent.getActivity(
            context,
            ID,
            Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notice = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_gotit)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setTimeoutAfter(LIFETIME_MS)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, R.drawable.ic_stat_gotit),
                    context.getString(R.string.link_open),
                    open,
                ).build(),
            )
            .build()
        manager.notify(ID, notice)
    }

    /** Opens [url] in the browser. */
    fun open(context: Context, url: String) {
        val uri = web(url) ?: return
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(context.applicationContext, R.string.files_no_app, Toast.LENGTH_SHORT).show()
        }
    }

    private fun web(url: String): Uri? {
        val uri = Uri.parse(url.trim())
        val web = uri.scheme == "http" || uri.scheme == "https"
        return if (web && !uri.host.isNullOrEmpty()) uri else null
    }
}
