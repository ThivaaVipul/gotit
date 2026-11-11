package app.gotit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** The notification's Turn on and Turn off buttons. */
class SharingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Sharing.request(context, intent.getBooleanExtra(ON, true))
    }

    companion object {
        const val ON = "on"
    }
}
