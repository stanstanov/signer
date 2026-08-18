package lt.turron.signer.pdf

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.File

class PdfPageRenderer(file: File) : AutoCloseable {
    private val lock = Any()
    private val descriptor: ParcelFileDescriptor =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    private val renderer = PdfRenderer(descriptor)
    private val sizes = HashMap<Int, Pair<Float, Float>>()
    private val bitmaps = HashMap<String, Bitmap>()

    val pageCount: Int get() = synchronized(lock) { renderer.pageCount }

    fun pageSize(index: Int): Pair<Float, Float> = synchronized(lock) {
        sizes.getOrPut(index) {
            renderer.openPage(index).use { page ->
                page.width.toFloat() to page.height.toFloat()
            }
        }
    }

    fun render(index: Int, maxWidthPx: Int): Bitmap = synchronized(lock) {
        val key = "$index-$maxWidthPx"
        bitmaps[key]?.takeUnless { it.isRecycled }?.let { return it }
        renderer.openPage(index).use { page ->
            val scale = maxWidthPx.toFloat() / page.width.coerceAtLeast(1)
            val w = (page.width * scale).toInt().coerceAtLeast(1)
            val h = (page.height * scale).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            bitmaps[key] = bitmap
            bitmap
        }
    }

    override fun close() {
        synchronized(lock) {
            bitmaps.clear()
            renderer.close()
            descriptor.close()
        }
    }
}
