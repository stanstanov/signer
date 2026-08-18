package lt.turron.signer

import android.app.Application
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import lt.turron.signer.pdf.PdfPageRenderer
import lt.turron.signer.pdf.PdfSignatureService
import java.io.File
import java.util.UUID

data class SignerUiState(
    val hasDocument: Boolean = false,
    val sourceName: String = "signed",
    val signature: Bitmap? = null,
    val placed: List<PlacedSignature> = emptyList(),
    val allowsMultiple: Boolean = false,
    val status: StatusKey = StatusKey.Initial,
    val statusCount: Int = 0,
    val statusPage: Int = 1,
    val error: String? = null,
    val menuSignatureId: String? = null,
    val zoomSignatureId: String? = null,
    val zoomScale: Float = 1f,
    val exportedFile: File? = null,
)

enum class StatusKey {
    Initial,
    PdfLoaded,
    DrawFirst,
    ReadyMulti,
    UpdatedMulti,
    UpdatedSingle,
    ReadySingle,
    CountAddDrag,
    OnPage,
    CountDrag,
    Removed,
    CountAdd,
    MultiEmpty,
    MultiHas,
    SingleKeptLast,
    SingleHas,
    SingleEmpty,
    Exported,
}

class SignerViewModel(application: Application) : AndroidViewModel(application) {
    private val _state = MutableStateFlow(SignerUiState())
    val state: StateFlow<SignerUiState> = _state.asStateFlow()

    private var sourceFile: File? = null
    private var zoomBase: FloatArray? = null // left, bottom, width, height
    var pageRenderer: PdfPageRenderer? = null
        private set

    fun openPdf(uri: Uri) {
        viewModelScope.launch {
            val context = getApplication<Application>()
            try {
                val dest = File(context.cacheDir, "source.pdf")
                withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        dest.outputStream().use { output -> input.copyTo(output) }
                    } ?: error(context.getString(R.string.error_read_pdf))
                }
                pageRenderer?.close()
                pageRenderer = withContext(Dispatchers.IO) { PdfPageRenderer(dest) }
                sourceFile = dest
                val name = uri.lastPathSegment
                    ?.substringAfterLast('/')
                    ?.substringBeforeLast('.')
                    ?.replace("/", "-")
                    ?.trim()
                    .orEmpty()
                    .ifEmpty { "signed" }
                _state.update {
                    it.copy(
                        hasDocument = true,
                        sourceName = name,
                        signature = null,
                        placed = emptyList(),
                        allowsMultiple = false,
                        status = StatusKey.PdfLoaded,
                        menuSignatureId = null,
                        zoomSignatureId = null,
                        exportedFile = null,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        error = e.localizedMessage ?: context.getString(R.string.error_read_pdf),
                    )
                }
            }
        }
    }

    fun setSignature(bitmap: Bitmap) {
        val current = _state.value
        if (current.allowsMultiple) {
            _state.update {
                it.copy(
                    signature = bitmap,
                    status = if (it.placed.isEmpty()) StatusKey.ReadyMulti else StatusKey.UpdatedMulti,
                )
            }
        } else if (current.placed.isNotEmpty()) {
            val first = current.placed.first()
            val aspect = bitmap.height.toFloat() / bitmap.width.coerceAtLeast(1)
            val size = pageRenderer?.pageSize(first.pageIndex)
            val clamped = if (size != null) {
                clampSignature(first.left, first.bottom, first.width, first.width * aspect, size.first, size.second)
            } else {
                floatArrayOf(first.left, first.bottom, first.width, first.width * aspect)
            }
            _state.update {
                it.copy(
                    signature = bitmap,
                    placed = listOf(
                        first.copy(
                            image = bitmap,
                            width = clamped[2],
                            height = clamped[3],
                            left = clamped[0],
                            bottom = clamped[1],
                        )
                    ),
                    status = StatusKey.UpdatedSingle,
                )
            }
        } else {
            _state.update { it.copy(signature = bitmap, status = StatusKey.ReadySingle) }
        }
    }

    fun place(pageIndex: Int, pdfX: Float, pdfY: Float) {
        val bitmap = _state.value.signature
        val size = pageRenderer?.pageSize(pageIndex)
        if (bitmap == null) {
            _state.update { it.copy(status = StatusKey.DrawFirst) }
            return
        }
        if (size == null) return
        val targetWidth = minOf(size.first * 0.28f, 180f)
        val aspect = bitmap.height.toFloat() / bitmap.width.coerceAtLeast(1)
        val targetHeight = targetWidth * aspect
        val clamped = clampSignature(
            pdfX - targetWidth / 2f,
            pdfY,
            targetWidth,
            targetHeight,
            size.first,
            size.second,
        )
        val placed = PlacedSignature(
            id = UUID.randomUUID().toString(),
            pageIndex = pageIndex,
            left = clamped[0],
            bottom = clamped[1],
            width = clamped[2],
            height = clamped[3],
            image = bitmap,
        )
        _state.update { current ->
            if (current.allowsMultiple) {
                val next = current.placed + placed
                current.copy(
                    placed = next,
                    status = StatusKey.CountAddDrag,
                    statusCount = next.size,
                )
            } else {
                current.copy(
                    placed = listOf(placed),
                    status = StatusKey.OnPage,
                    statusPage = pageIndex + 1,
                )
            }
        }
    }

    fun move(id: String, pageIndex: Int, left: Float, bottom: Float, width: Float, height: Float) {
        val size = pageRenderer?.pageSize(pageIndex) ?: return
        val clamped = clampSignature(left, bottom, width, height, size.first, size.second)
        _state.update { current ->
            current.copy(
                placed = current.placed.map { sig ->
                    if (sig.id != id) sig else sig.copy(
                        pageIndex = pageIndex,
                        left = clamped[0],
                        bottom = clamped[1],
                        width = clamped[2],
                        height = clamped[3],
                    )
                },
                status = if (current.allowsMultiple) StatusKey.CountDrag else StatusKey.OnPage,
                statusCount = current.placed.size,
                statusPage = pageIndex + 1,
            )
        }
    }

    fun openMenu(id: String) {
        _state.update { it.copy(menuSignatureId = id, zoomSignatureId = null) }
    }

    fun dismissMenu() {
        _state.update { it.copy(menuSignatureId = null) }
    }

    fun beginZoom() {
        val id = _state.value.menuSignatureId ?: return
        val sig = _state.value.placed.firstOrNull { it.id == id } ?: return
        zoomBase = floatArrayOf(sig.left, sig.bottom, sig.width, sig.height)
        _state.update { it.copy(zoomSignatureId = id, zoomScale = 1f, menuSignatureId = null) }
    }

    fun applyZoom(scale: Float) {
        val id = _state.value.zoomSignatureId ?: return
        val base = zoomBase ?: return
        val sig = _state.value.placed.firstOrNull { it.id == id } ?: return
        val size = pageRenderer?.pageSize(sig.pageIndex) ?: return
        val centerX = base[0] + base[2] / 2f
        val centerY = base[1] + base[3] / 2f
        val w = base[2] * scale
        val h = base[3] * scale
        val clamped = clampSignature(centerX - w / 2f, centerY - h / 2f, w, h, size.first, size.second)
        _state.update { current ->
            current.copy(
                zoomScale = scale,
                placed = current.placed.map {
                    if (it.id != id) it else it.copy(
                        left = clamped[0],
                        bottom = clamped[1],
                        width = clamped[2],
                        height = clamped[3],
                    )
                },
            )
        }
    }

    fun endZoom() {
        _state.update { it.copy(zoomSignatureId = null) }
        zoomBase = null
    }

    fun deleteFromMenu() {
        val id = _state.value.menuSignatureId ?: return
        delete(id)
        _state.update { it.copy(menuSignatureId = null) }
    }

    fun delete(id: String) {
        _state.update { current ->
            val next = current.placed.filterNot { it.id == id }
            current.copy(
                placed = next,
                zoomSignatureId = if (current.zoomSignatureId == id) null else current.zoomSignatureId,
                status = when {
                    next.isEmpty() -> StatusKey.Removed
                    current.allowsMultiple -> StatusKey.CountAdd
                    else -> StatusKey.Removed
                },
                statusCount = next.size,
            )
        }
    }

    fun setMultiple(enabled: Boolean) {
        _state.update { current ->
            if (enabled) {
                current.copy(
                    allowsMultiple = true,
                    status = if (current.placed.isEmpty()) StatusKey.MultiEmpty else StatusKey.MultiHas,
                )
            } else {
                val kept = current.placed.takeLast(1)
                current.copy(
                    allowsMultiple = false,
                    placed = kept,
                    zoomSignatureId = current.zoomSignatureId?.takeIf { id -> kept.any { it.id == id } },
                    status = when {
                        current.placed.size > 1 -> StatusKey.SingleKeptLast
                        kept.size == 1 -> StatusKey.SingleHas
                        else -> StatusKey.SingleEmpty
                    },
                )
            }
        }
    }

    fun export() {
        val source = sourceFile ?: return
        val placed = _state.value.placed
        val name = _state.value.sourceName
        val context = getApplication<Application>()
        viewModelScope.launch {
            try {
                val out = File(context.cacheDir, "$name-signed.pdf")
                withContext(Dispatchers.IO) {
                    PdfSignatureService.stamp(source, out, placed)
                }
                _state.update { it.copy(exportedFile = out, status = StatusKey.Exported) }
            } catch (e: Exception) {
                _state.update {
                    it.copy(error = e.localizedMessage ?: context.getString(R.string.error_write_pdf))
                }
            }
        }
    }

    fun consumeError() {
        _state.update { it.copy(error = null) }
    }

    fun consumeExport() {
        _state.update { it.copy(exportedFile = null) }
    }

    fun writeExportedTo(uri: Uri) {
        val file = _state.value.exportedFile ?: return
        val context = getApplication<Application>()
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { output ->
                        file.inputStream().use { input -> input.copyTo(output) }
                    } ?: error(context.getString(R.string.error_write_pdf))
                }
                _state.update { it.copy(exportedFile = null) }
            } catch (e: Exception) {
                _state.update {
                    it.copy(error = e.localizedMessage ?: context.getString(R.string.error_write_pdf))
                }
            }
        }
    }

    override fun onCleared() {
        pageRenderer?.close()
        super.onCleared()
    }
}

val InkSwatches = listOf(
    Color(0xFF000000) to R.string.color_black,
    Color(0xFF616166) to R.string.color_gray,
    Color(0xFF1F57C2) to R.string.color_blue,
    Color(0xFF142E6B) to R.string.color_navy,
    Color(0xFFC21F24) to R.string.color_red,
    Color(0xFF1A7547) to R.string.color_green,
)
