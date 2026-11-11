package app.gotit

import android.content.Context
import android.os.Build
import android.provider.Settings

/** The phone's name, as the PC shows it. */
object DeviceName {
    /**
     * A name the user set wins. Some makers leave the standard setting at the
     * model code and keep the friendly name elsewhere (MIUI: the Bluetooth
     * name), so try that, then the marketing name, then the model code.
     */
    fun of(context: Context): String {
        val resolver = context.contentResolver
        val set = Settings.Global.getString(resolver, Settings.Global.DEVICE_NAME)?.trim()
        if (!set.isNullOrEmpty() && set != Build.MODEL) return set
        val bluetooth = try {
            Settings.Secure.getString(resolver, "bluetooth_name")?.trim()
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
