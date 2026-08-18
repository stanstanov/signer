package lt.turron.signer.ui

import android.content.Intent
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Draw
import androidx.compose.material.icons.outlined.SaveAlt
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ZoomIn
import androidx.compose.material.icons.outlined.ZoomOut
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import lt.turron.signer.PlacedSignature
import lt.turron.signer.R
import lt.turron.signer.SignerUiState
import lt.turron.signer.SignerViewModel
import lt.turron.signer.StatusKey
import lt.turron.signer.pdf.PdfPageRenderer
import kotlin.math.max
import kotlin.math.roundToInt

private val ToolbarBlue = Color(0xFF1F57C2)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: SignerViewModel) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var showPad by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }

    val openPdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) viewModel.openPdf(uri)
    }

    LaunchedEffect(state.exportedFile) {
        val file = state.exportedFile ?: return@LaunchedEffect
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.action_save)))
        viewModel.consumeExport()
    }

    Scaffold(
        containerColor = if (state.hasDocument) {
            MaterialTheme.colorScheme.surfaceVariant
        } else {
            MaterialTheme.colorScheme.background
        },
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = {},
                windowInsets = WindowInsets(0, 0, 0, 0),
                modifier = Modifier.padding(top = 12.dp),
                navigationIcon = {
                    TextButton(
                        onClick = { openPdf.launch(arrayOf("application/pdf")) },
                        modifier = Modifier
                            .padding(start = 10.dp)
                            .background(ToolbarBlue, RoundedCornerShape(20.dp)),
                        colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    ) {
                        Icon(Icons.Outlined.Description, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.action_open))
                    }
                },
                actions = {
                    ToolbarIconButton(
                        onClick = { showSettings = true },
                        icon = Icons.Outlined.Settings,
                        contentDescription = stringResource(R.string.action_settings),
                    )
                    ToolbarIconButton(
                        onClick = { showPad = true },
                        enabled = state.hasDocument,
                        icon = Icons.Outlined.Draw,
                        contentDescription = stringResource(R.string.action_signature),
                    )
                    ToolbarIconButton(
                        onClick = { viewModel.export() },
                        enabled = state.hasDocument,
                        icon = Icons.Outlined.SaveAlt,
                        contentDescription = stringResource(R.string.action_save),
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    navigationIconContentColor = Color.White,
                    actionIconContentColor = Color.White,
                ),
            )
        },
    ) { _ ->
        Box(Modifier.fillMaxSize()) {
            if (!state.hasDocument) {
                Column(
                    Modifier.align(Alignment.Center).padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(Icons.Outlined.Description, null, Modifier.size(48.dp))
                    Spacer(Modifier.height(12.dp))
                    Text(stringResource(R.string.empty_no_pdf), style = MaterialTheme.typography.titleLarge)
                    Text(stringResource(R.string.empty_tap_open), style = MaterialTheme.typography.bodyMedium)
                }
            } else {
                PdfPages(viewModel, state)
            }

            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            ) {
                if (state.zoomSignatureId != null) {
                    ZoomPanel(state.zoomScale, { viewModel.applyZoom(it) }, { viewModel.endZoom() })
                } else {
                    StatusPanel(statusText(state))
                }
            }
        }
    }

    if (showPad) {
        SignaturePadSheet(
            existing = state.signature,
            onSave = {
                viewModel.setSignature(it)
                showPad = false
            },
            onCancel = { showPad = false },
        )
    }
    if (showSettings) {
        SettingsSheet(
            allowsMultiple = state.allowsMultiple,
            hasDocument = state.hasDocument,
            onChange = viewModel::setMultiple,
            onClose = { showSettings = false },
        )
    }
    if (state.menuSignatureId != null) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissMenu() },
            title = { Text(stringResource(R.string.action_signature)) },
            confirmButton = {
                TextButton(onClick = { viewModel.beginZoom() }) { Text(stringResource(R.string.action_zoom)) }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = { viewModel.deleteFromMenu() }) {
                        Text(stringResource(R.string.action_delete), color = MaterialTheme.colorScheme.error)
                    }
                    TextButton(onClick = { viewModel.dismissMenu() }) {
                        Text(stringResource(R.string.action_cancel))
                    }
                }
            },
        )
    }
    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = { viewModel.consumeError() },
            title = { Text(stringResource(R.string.error_title)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { viewModel.consumeError() }) { Text(stringResource(R.string.action_ok)) }
            },
        )
    }
}

@Composable
private fun statusText(state: SignerUiState): String = when (state.status) {
    StatusKey.Initial -> stringResource(R.string.status_initial)
    StatusKey.PdfLoaded -> stringResource(R.string.status_pdf_loaded)
    StatusKey.DrawFirst -> stringResource(R.string.status_draw_first)
    StatusKey.ReadyMulti -> stringResource(R.string.status_ready_multi)
    StatusKey.UpdatedMulti -> stringResource(R.string.status_updated_multi)
    StatusKey.UpdatedSingle -> stringResource(R.string.status_updated_single)
    StatusKey.ReadySingle -> stringResource(R.string.status_ready_single)
    StatusKey.CountAddDrag -> stringResource(R.string.status_count_add_drag, state.statusCount)
    StatusKey.OnPage -> stringResource(R.string.status_on_page, state.statusPage)
    StatusKey.CountDrag -> stringResource(R.string.status_count_drag, state.statusCount)
    StatusKey.Removed -> stringResource(R.string.status_removed)
    StatusKey.CountAdd -> stringResource(R.string.status_count_add, state.statusCount)
    StatusKey.MultiEmpty -> stringResource(R.string.status_multi_empty)
    StatusKey.MultiHas -> stringResource(R.string.status_multi_has)
    StatusKey.SingleKeptLast -> stringResource(R.string.status_single_kept_last)
    StatusKey.SingleHas -> stringResource(R.string.status_single_has)
    StatusKey.SingleEmpty -> stringResource(R.string.status_single_empty)
    StatusKey.Exported -> stringResource(R.string.status_exported)
}

@Composable
private fun ToolbarIconButton(
    onClick: () -> Unit,
    icon: ImageVector,
    contentDescription: String,
    enabled: Boolean = true,
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .padding(horizontal = 2.dp)
            .background(
                ToolbarBlue.copy(alpha = if (enabled) 1f else 0.4f),
                CircleShape,
            ),
        colors = IconButtonDefaults.iconButtonColors(
            contentColor = Color.White,
            disabledContentColor = Color.White.copy(alpha = 0.7f),
        ),
    ) {
        Icon(icon, contentDescription = contentDescription)
    }
}

@Composable
private fun StatusPanel(text: String) {
    Text(
        text = text,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = 13.sp,
        modifier = Modifier
            .fillMaxWidth()
            .shadow(8.dp, RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.92f), RoundedCornerShape(22.dp))
            .border(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), RoundedCornerShape(22.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
    )
}

@Composable
private fun ZoomPanel(scale: Float, onScale: (Float) -> Unit, onDone: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .shadow(8.dp, RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.92f), RoundedCornerShape(22.dp))
            .border(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), RoundedCornerShape(22.dp))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.ZoomOut, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Slider(scale, onScale, valueRange = 0.5f..2.5f, modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
        Icon(Icons.Outlined.ZoomIn, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton(onClick = onDone) { Text(stringResource(R.string.action_done)) }
    }
}

@Composable
private fun PdfPages(viewModel: SignerViewModel, state: SignerUiState) {
    val renderer = viewModel.pageRenderer ?: return
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    val scaleState = remember(renderer) { mutableFloatStateOf(1f) }
    val offsetState = remember(renderer) { mutableStateOf(Offset.Zero) }
    val viewportState = remember { mutableStateOf(IntSize.Zero) }
    val contentHeightState = remember { mutableFloatStateOf(0f) }
    val viewport = viewportState.value
    val pageWidthPx = viewport.width.coerceAtLeast(1)
    val scale = scaleState.floatValue
    val offset = offsetState.value
    val spacerPx = with(density) { 8.dp.toPx() }
    val estimatedHeight = remember(renderer, pageWidthPx, spacerPx) {
        var height = 0f
        repeat(renderer.pageCount) { index ->
            val (pageW, pageH) = renderer.pageSize(index)
            height += pageWidthPx * (pageH / pageW.coerceAtLeast(1f))
            height += spacerPx
        }
        height
    }
    SideEffect {
        if (estimatedHeight > contentHeightState.floatValue) {
            contentHeightState.floatValue = estimatedHeight
        }
    }

    fun clampOffset(value: Offset, zoom: Float): Offset {
        val view = viewportState.value
        val viewW = view.width.toFloat()
        val viewH = view.height.toFloat()
        if (viewW == 0f || viewH == 0f) return value
        val scaledW = view.width.coerceAtLeast(1) * zoom
        val scaledH = contentHeightState.floatValue * zoom
        val (minX, maxX) = if (scaledW <= viewW) {
            val x = (viewW - scaledW) / 2f
            x to x
        } else {
            (viewW - scaledW) to 0f
        }
        val (minY, maxY) = if (scaledH <= viewH) {
            val y = (viewH - scaledH) / 2f
            y to y
        } else {
            (viewH - scaledH) to 0f
        }
        return Offset(value.x.coerceIn(minX, maxX), value.y.coerceIn(minY, maxY))
    }

    LaunchedEffect(viewport.width, viewport.height, contentHeightState.floatValue) {
        if (viewport.width == 0 || contentHeightState.floatValue <= 0f) return@LaunchedEffect
        offsetState.value = clampOffset(offsetState.value, scaleState.floatValue)
    }

    Box(
        Modifier
            .fillMaxSize()
            .clipToBounds()
            .onSizeChanged { viewportState.value = it }
            .pointerInput(renderer) {
                fun clampPan(value: Offset, zoom: Float): Offset {
                    val view = viewportState.value
                    val viewW = view.width.toFloat()
                    val viewH = view.height.toFloat()
                    if (viewW == 0f || viewH == 0f) return value
                    val scaledW = view.width.coerceAtLeast(1) * zoom
                    val scaledH = contentHeightState.floatValue * zoom
                    val (minX, maxX) = if (scaledW <= viewW) {
                        val x = (viewW - scaledW) / 2f
                        x to x
                    } else {
                        (viewW - scaledW) to 0f
                    }
                    val (minY, maxY) = if (scaledH <= viewH) {
                        val y = (viewH - scaledH) / 2f
                        y to y
                    } else {
                        (viewH - scaledH) to 0f
                    }
                    return Offset(value.x.coerceIn(minX, maxX), value.y.coerceIn(minY, maxY))
                }
                awaitPointerEventScope {
                    var previousDistance = 0f
                    var lastCentroid = Offset.Unspecified
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val pressed = event.changes.filter { it.pressed }
                        if (pressed.size < 2) {
                            previousDistance = 0f
                            lastCentroid = Offset.Unspecified
                            continue
                        }
                        val centroid = Offset(
                            (pressed[0].position.x + pressed[1].position.x) / 2f,
                            (pressed[0].position.y + pressed[1].position.y) / 2f,
                        )
                        val distance = (pressed[0].position - pressed[1].position)
                            .getDistance()
                            .coerceAtLeast(0.01f)
                        if (previousDistance > 0f) {
                            val oldScale = scaleState.floatValue
                            val newScale = (oldScale * (distance / previousDistance)).coerceIn(1f, 5f)
                            val factor = if (oldScale == 0f) 1f else newScale / oldScale
                            val oldOffset = offsetState.value
                            var next = centroid - (centroid - oldOffset) * factor
                            if (lastCentroid != Offset.Unspecified) {
                                next += centroid - lastCentroid
                            }
                            scaleState.floatValue = newScale
                            offsetState.value = clampPan(next, newScale)
                        }
                        previousDistance = distance
                        lastCentroid = centroid
                        event.changes.forEach { it.consume() }
                    }
                }
            }
            .pointerInput(renderer) {
                fun clampPan(value: Offset, zoom: Float): Offset {
                    val view = viewportState.value
                    val viewW = view.width.toFloat()
                    val viewH = view.height.toFloat()
                    if (viewW == 0f || viewH == 0f) return value
                    val scaledW = view.width.coerceAtLeast(1) * zoom
                    val scaledH = contentHeightState.floatValue * zoom
                    val (minX, maxX) = if (scaledW <= viewW) {
                        val x = (viewW - scaledW) / 2f
                        x to x
                    } else {
                        (viewW - scaledW) to 0f
                    }
                    val (minY, maxY) = if (scaledH <= viewH) {
                        val y = (viewH - scaledH) / 2f
                        y to y
                    } else {
                        (viewH - scaledH) to 0f
                    }
                    return Offset(value.x.coerceIn(minX, maxX), value.y.coerceIn(minY, maxY))
                }
                val slop = viewConfiguration.touchSlop
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = true)
                    var last = down.position
                    var panning = false
                    drag(down.id) { change ->
                        val pos = change.position
                        if (!panning && (pos - down.position).getDistance() > slop) {
                            panning = true
                        }
                        if (panning) {
                            change.consume()
                            offsetState.value = clampPan(
                                offsetState.value + (pos - last),
                                scaleState.floatValue,
                            )
                        }
                        last = pos
                    }
                }
            },
    ) {
        if (viewport.width == 0) return@Box
        Column(
            Modifier
                .width(with(density) { pageWidthPx.toDp() })
                .onSizeChanged { contentHeightState.floatValue = max(it.height.toFloat(), estimatedHeight) }
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    translationX = offset.x
                    translationY = offset.y
                    transformOrigin = TransformOrigin(0f, 0f)
                },
        ) {
            repeat(renderer.pageCount) { index ->
                PdfPageItem(
                    renderer = renderer,
                    index = index,
                    containerWidth = pageWidthPx,
                    signatures = state.placed.filter { it.pageIndex == index },
                    canPlace = state.signature != null,
                    onPlace = { x, y ->
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        viewModel.place(index, x, y)
                    },
                    onMove = { id, left, bottom, w, h -> viewModel.move(id, index, left, bottom, w, h) },
                    onTapSignature = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        viewModel.openMenu(it)
                    },
                    onDragHaptic = { haptic.performHapticFeedback(HapticFeedbackType.LongPress) },
                )
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

@Composable
private fun PdfPageItem(
    renderer: PdfPageRenderer,
    index: Int,
    containerWidth: Int,
    signatures: List<PlacedSignature>,
    canPlace: Boolean,
    onPlace: (Float, Float) -> Unit,
    onMove: (String, Float, Float, Float, Float) -> Unit,
    onTapSignature: (String) -> Unit,
    onDragHaptic: () -> Unit,
) {
    val (pageW, pageH) = remember(index, renderer) { renderer.pageSize(index) }
    val pageBitmap by produceState<Bitmap?>(initialValue = null, index, containerWidth, renderer) {
        value = withContext(Dispatchers.IO) { renderer.render(index, containerWidth) }
    }
    PdfPageBox(
        pageBitmap = pageBitmap,
        pageWidthPt = pageW,
        pageHeightPt = pageH,
        signatures = signatures,
        canPlace = canPlace,
        onPlace = onPlace,
        onMove = onMove,
        onTapSignature = onTapSignature,
        onDragHaptic = onDragHaptic,
    )
}

@Composable
private fun PdfPageBox(
    pageBitmap: Bitmap?,
    pageWidthPt: Float,
    pageHeightPt: Float,
    signatures: List<PlacedSignature>,
    canPlace: Boolean,
    onPlace: (Float, Float) -> Unit,
    onMove: (String, Float, Float, Float, Float) -> Unit,
    onTapSignature: (String) -> Unit,
    onDragHaptic: () -> Unit,
) {
    var size by remember { mutableStateOf(IntSize.Zero) }
    val scaleX = if (size.width == 0) 1f else size.width / pageWidthPt
    val scaleY = if (size.height == 0) 1f else size.height / pageHeightPt
    val interactionSource = remember { MutableInteractionSource() }
    var press by remember { mutableStateOf(Offset.Zero) }
    LaunchedEffect(interactionSource) {
        interactionSource.interactions.collect { interaction ->
            if (interaction is PressInteraction.Press) {
                press = interaction.pressPosition
            }
        }
    }
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio((pageWidthPt / pageHeightPt).coerceAtLeast(0.01f))
            .background(Color.White)
            .onSizeChanged { size = it }
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = canPlace,
            ) {
                if (size.width == 0 || size.height == 0) return@clickable
                onPlace(press.x / scaleX, pageHeightPt - press.y / scaleY)
            },
    ) {
        pageBitmap?.let { bitmap ->
            Image(
                bitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.FillBounds,
            )
        }
        signatures.forEach { signature ->
            SignatureStamp(
                signature = signature,
                leftPx = signature.left * scaleX,
                topPx = (pageHeightPt - signature.bottom - signature.height) * scaleY,
                widthPx = signature.width * scaleX,
                heightPx = signature.height * scaleY,
                scaleX = scaleX,
                scaleY = scaleY,
                pageHeightPt = pageHeightPt,
                onMove = onMove,
                onTap = { onTapSignature(signature.id) },
                onDragHaptic = onDragHaptic,
            )
        }
    }
}

@Composable
private fun SignatureStamp(
    signature: PlacedSignature,
    leftPx: Float,
    topPx: Float,
    widthPx: Float,
    heightPx: Float,
    scaleX: Float,
    scaleY: Float,
    pageHeightPt: Float,
    onMove: (String, Float, Float, Float, Float) -> Unit,
    onTap: () -> Unit,
    onDragHaptic: () -> Unit,
) {
    val density = LocalDensity.current
    var drag by remember(signature.id, leftPx, topPx) { mutableStateOf(Offset.Zero) }
    Box(
        Modifier
            .offset { IntOffset((leftPx + drag.x).roundToInt(), (topPx + drag.y).roundToInt()) }
            .width(with(density) { widthPx.toDp() })
            .height(with(density) { heightPx.toDp() })
            .pointerInput(signature.id, scaleX, scaleY, leftPx, topPx) {
                awaitEachGesture {
                    val down = awaitFirstDown(
                        requireUnconsumed = false,
                        pass = PointerEventPass.Initial,
                    )
                    down.consume()
                    var total = Offset.Zero
                    var moved = false
                    val slop = viewConfiguration.touchSlop
                    val finished = drag(down.id) { change ->
                        total += change.positionChange()
                        change.consume()
                        if (!moved && total.getDistance() > slop) {
                            moved = true
                            onDragHaptic()
                        }
                        if (moved) drag = total
                    }
                    if (moved) {
                        val newLeft = signature.left + total.x / scaleX
                        val newTopPx = topPx + total.y
                        val newBottom = pageHeightPt - (newTopPx / scaleY) - signature.height
                        onMove(signature.id, newLeft, newBottom, signature.width, signature.height)
                        onDragHaptic()
                        drag = Offset.Zero
                    } else if (finished) {
                        onTap()
                    } else {
                        drag = Offset.Zero
                    }
                }
            },
    ) {
        Image(
            signature.image.asImageBitmap(),
            stringResource(R.string.a11y_signature_hint),
            Modifier.fillMaxSize(),
            contentScale = ContentScale.FillBounds,
        )
    }
}
