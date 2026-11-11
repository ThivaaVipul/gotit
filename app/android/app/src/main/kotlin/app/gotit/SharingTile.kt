package app.gotit

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * The quick settings tile: the sharing switch, one swipe away. Unavailable
 * until paired; it works while the PC is away, and the change reaches the PC
 * when they link again.
 */
class SharingTile : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        show()
    }

    override fun onClick() {
        super.onClick()
        Sharing.load(this)
        if (!Sharing.paired) return
        Sharing.request(this, !Sharing.on)
        show()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        getSharedPreferences(Channels.SETUP_PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(Channels.TILE_ADDED, true)
            .apply()
    }

    private fun show() {
        Sharing.load(this)
        val tile = qsTile ?: return
        tile.label = getString(R.string.tile_label)
        tile.state = when {
            !Sharing.paired -> Tile.STATE_UNAVAILABLE
            Sharing.on -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = when {
                !Sharing.paired -> getString(R.string.tile_not_paired)
                Sharing.on -> getString(R.string.tile_on)
                else -> getString(R.string.tile_off)
            }
        }
        tile.updateTile()
    }

    companion object {
        /** Asks Android to show the tile again, with the switch as it is now. */
        fun refresh(context: Context) {
            try {
                TileService.requestListeningState(context, ComponentName(context, SharingTile::class.java))
            } catch (e: RuntimeException) {
                // Not added, or the system is busy: it reads the switch when shown.
            }
        }
    }
}
