package app.gotit

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle

/** Text on the phone's clipboard. Nothing read or written is kept or logged. */
object PhoneClipboard {
    /** Gotit's own writes carry this label. */
    private const val LABEL = "Gotit"

    /**
     * What was copied: text, whether the copying app marked it sensitive,
     * when, and whether Gotit itself wrote it (text from the PC).
     */
    data class Copy(val text: String, val sensitive: Boolean, val copiedAt: Long, val ours: Boolean)

    /** Null when Android refuses (Gotit isn't focused) or there is no text. */
    fun read(context: Context): Copy? {
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        val clip = try {
            clipboard.primaryClip
        } catch (e: SecurityException) {
            null
        } ?: return null
        if (clip.itemCount == 0) return null
        val description = clip.description
        val item = clip.getItemAt(0)
        // Text only: styled copies carry plain text too. Images and files come later.
        val text = item.text?.toString()
        if (text.isNullOrEmpty()) return null
        val sensitive = Build.VERSION.SDK_INT >= 33 &&
            description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true
        return Copy(text, sensitive, description.timestamp, description.label?.toString() == LABEL)
    }

    /** Background apps may write the clipboard; this is how text from the PC arrives. */
    fun write(context: Context, text: String, sensitive: Boolean) {
        val clip = ClipData.newPlainText(LABEL, text)
        if (sensitive) {
            // Android 13 and later hide a sensitive clip's preview.
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }
}
