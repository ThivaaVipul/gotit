package app.gotit

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/**
 * Share > Gotit: files go to the PC, and links or text land on its
 * clipboard. Invisible; it says what happened in a toast, or asks once when
 * sharing is off.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uris = sharedUris(intent)
        val text = if (uris.isEmpty()) intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() else null
        // Open now: Android's permission to read them ends with this screen.
        val files = uris.mapNotNull { PhoneFiles.open(this, it) }
        if (files.isEmpty() && text.isNullOrBlank()) {
            say(getString(R.string.share_nothing))
            finish()
            return
        }
        hand(text, files, turnOn = false)
    }

    private fun hand(text: String?, files: List<PhoneFiles.Shared>, turnOn: Boolean) {
        ShareRelay.share(text, files, turnOn) { answer ->
            when {
                answer == "off" -> askToTurnOn(text, files)
                else -> {
                    val sending = answer.startsWith("sending:")
                    // Files on their way stay open for Dart to read.
                    if (!sending) files.forEach { PhoneFiles.close(it.handle) }
                    when {
                        sending -> {
                            val pc = answer.removePrefix("sending:")
                            say(
                                if (files.size == 1) {
                                    getString(R.string.share_sending_one, pc)
                                } else {
                                    getString(R.string.share_sending_many, files.size, pc)
                                },
                            )
                        }
                        answer == "sent" -> say(getString(R.string.share_sent))
                        answer == "unpaired" -> say(getString(R.string.share_unpaired))
                        answer.startsWith("away:") ->
                            say(getString(R.string.share_away, answer.removePrefix("away:")))
                        answer == "failed" -> say(getString(R.string.share_failed))
                    }
                    finish()
                }
            }
        }
    }

    /** Sharing is off for both devices: turn it on and send, or leave it. */
    private fun askToTurnOn(text: String?, files: List<PhoneFiles.Shared>) {
        if (isFinishing) return
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(R.string.share_off_title)
            .setPositiveButton(R.string.share_off_turn_on) { _, _ -> hand(text, files, turnOn = true) }
            .setNegativeButton(android.R.string.cancel) { _, _ ->
                files.forEach { PhoneFiles.close(it.handle) }
                finish()
            }
            .setOnCancelListener {
                files.forEach { PhoneFiles.close(it.handle) }
                finish()
            }
            .show()
    }

    private fun say(message: String) {
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            },
        )
        Intent.ACTION_SEND_MULTIPLE -> (
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            ).orEmpty()
        else -> emptyList()
    }
}
