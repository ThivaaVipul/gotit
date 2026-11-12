package app.gotit

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves the image Gotit last put on the clipboard (one from the PC), so an
 * app that pastes it gets read access through the clipboard. Read-only, and
 * only files named like Gotit's own (clip-123.png).
 */
class ClipProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = MIME

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = fileFor(uri)
        val columns: Array<String> = projection?.let { arrayOf(*it) }
            ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row: List<Any?> = columns.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns).apply { addRow(row.toTypedArray()) }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    private fun fileFor(uri: Uri): File {
        val name = uri.lastPathSegment ?: throw FileNotFoundException("No name")
        if (!NAME.matches(name)) throw FileNotFoundException(name)
        return File(folder(requireNotNull(context)), name)
    }

    companion object {
        const val MIME = "image/png"
        private const val AUTHORITY = "app.gotit.clips"
        private val NAME = Regex("clip-\\d+\\.png")

        fun folder(context: Context) = File(context.cacheDir, "clips")

        fun uriFor(file: File): Uri = Uri.parse("content://$AUTHORITY/${file.name}")
    }
}
