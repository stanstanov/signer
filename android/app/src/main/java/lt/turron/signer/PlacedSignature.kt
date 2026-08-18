package lt.turron.signer

data class PlacedSignature(
    val id: String,
    val pageIndex: Int,
    /** PDF page space, origin bottom-left, in points. */
    val left: Float,
    val bottom: Float,
    val width: Float,
    val height: Float,
    val image: android.graphics.Bitmap,
)

fun clampSignature(
    left: Float,
    bottom: Float,
    width: Float,
    height: Float,
    pageWidth: Float,
    pageHeight: Float,
): FloatArray {
    var w = width
    var h = height
    var x = left
    var y = bottom
    if (w > pageWidth) {
        w = pageWidth
        x = 0f
    } else {
        x = x.coerceIn(0f, pageWidth - w)
    }
    if (h > pageHeight) {
        h = pageHeight
        y = 0f
    } else {
        y = y.coerceIn(0f, pageHeight - h)
    }
    return floatArrayOf(x, y, w, h)
}
