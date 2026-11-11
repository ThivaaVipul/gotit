package app.gotit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder

/**
 * Keeps Gotit running while it is paired, and shows how the link stands in
 * a quiet ongoing notification with a Send button. Dart sets what it says.
 */
class LinkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // After Android restarts the service, the intent is empty: show the
        // last text until Dart sets a new one.
        intent?.getStringExtra(TITLE)?.let { title = it }
        text = intent?.getStringExtra(TEXT) ?: text
        val notification = build(this)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(ID, notification)
        }
        return START_STICKY
    }

    private fun refresh() {
        getSystemService(NotificationManager::class.java).notify(ID, build(this))
    }

    companion object {
        private const val ID = 1
        private const val CHANNEL = "link"
        private const val TITLE = "title"
        private const val TEXT = "text"

        private var instance: LinkService? = null
        private var title = "Gotit"
        private var text: String? = null

        /**
         * Shows or updates the notification. False when Android won't let the
         * service start from the background (the battery exemption allows it).
         */
        fun show(context: Context, newTitle: String, newText: String?): Boolean {
            title = newTitle
            text = newText
            instance?.let {
                it.refresh()
                return true
            }
            val intent = Intent(context, LinkService::class.java)
                .putExtra(TITLE, newTitle)
                .putExtra(TEXT, newText)
            return try {
                context.startForegroundService(intent)
                true
            } catch (e: IllegalStateException) {
                // Android 12 and later: not allowed from the background
                // (ForegroundServiceStartNotAllowedException).
                if (Build.VERSION.SDK_INT >= 31) false else throw e
            }
        }

        /** Posts the notification again, for when notifications were just allowed. */
        fun repost() {
            instance?.refresh()
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }

        private fun build(context: Context): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Connection to your PC", NotificationManager.IMPORTANCE_LOW).apply {
                        setShowBadge(false)
                    },
                )
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val send = PendingIntent.getActivity(
                context,
                1,
                Intent(context, ReadClipActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                ),
                PendingIntent.FLAG_IMMUTABLE,
            )
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_gotit)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setShowWhen(false)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setContentIntent(open)
                .addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(context, R.drawable.ic_stat_gotit),
                        "Send",
                        send,
                    ).build(),
                )
                .apply {
                    if (Build.VERSION.SDK_INT >= 31) {
                        setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                    }
                }
                .build()
        }
    }
}
