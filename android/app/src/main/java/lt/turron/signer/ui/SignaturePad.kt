package lt.turron.signer.ui

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Path as AndroidPath
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import lt.turron.signer.InkSwatches
import lt.turron.signer.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SignaturePadSheet(
    existing: Bitmap?,
    onSave: (Bitmap) -> Unit,
    onCancel: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val strokes = remember { mutableStateListOf<List<Offset>>() }
    var current by remember { mutableStateOf<List<Offset>>(emptyList()) }
    var canvasSize by remember { mutableStateOf(IntSize.Zero) }
    var ink by remember { mutableStateOf(InkSwatches.first().first) }
    var selected by remember { mutableStateOf(0) }
    var preview by remember { mutableStateOf(existing) }
    var showColorPicker by remember { mutableStateOf(false) }
    val showingPreview = preview != null && strokes.isEmpty() && current.isEmpty()
    val hasInk = strokes.isNotEmpty() || current.isNotEmpty()
    fun applyInk(color: Color, swatchIndex: Int) {
        ink = color
        selected = swatchIndex
        if (showingPreview) {
            preview = preview?.let { recolorSignature(it, color) }
        }
    }

    ModalBottomSheet(onDismissRequest = onCancel, sheetState = sheetState) {
        Column(Modifier.padding(bottom = 24.dp)) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onCancel) { Text(stringResource(R.string.action_cancel)) }
                Text(stringResource(R.string.action_signature), style = MaterialTheme.typography.titleMedium)
                TextButton(
                    onClick = {
                        if (hasInk) renderSignature(strokes + listOfNotNull(current.takeIf { it.isNotEmpty() }), canvasSize, ink)?.let(onSave)
                        else preview?.let(onSave)
                    },
                    enabled = showingPreview || hasInk,
                ) { Text(stringResource(R.string.action_done)) }
            }
            Text(
                stringResource(if (showingPreview) R.string.pad_preview_hint else R.string.pad_draw_hint),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            Box(
                Modifier
                    .padding(horizontal = 16.dp)
                    .fillMaxWidth()
                    .height(220.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White)
                    .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
                    .onSizeChanged { canvasSize = it },
            ) {
                if (showingPreview && preview != null) {
                    Image(
                        preview!!.asImageBitmap(),
                        stringResource(R.string.a11y_signature_preview),
                        Modifier.align(Alignment.Center).padding(12.dp).fillMaxWidth().height(196.dp),
                    )
                } else {
                    SignatureCanvas(
                        strokes = strokes,
                        current = current,
                        color = ink,
                        onDragStart = { current = listOf(it) },
                        onDrag = { current = current + it },
                        onDragEnd = {
                            if (current.isNotEmpty()) strokes.add(current)
                            current = emptyList()
                        },
                    )
                }
            }
            val colorRowLabel = stringResource(R.string.a11y_signature_color)
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .semantics { contentDescription = colorRowLabel },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(
                    onClick = {
                        strokes.clear()
                        current = emptyList()
                        preview = null
                    },
                    enabled = showingPreview || hasInk,
                ) { Text(stringResource(R.string.action_clear)) }
                Spacer(Modifier.weight(1f))
                InkSwatches.forEachIndexed { index, (color, label) ->
                    val name = stringResource(label)
                    val selectedSwatch = selected == index
                    Box(
                        Modifier
                            .padding(4.dp)
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(color)
                            .border(2.dp, Color.White, CircleShape)
                            .border(
                                if (selectedSwatch) 2.5.dp else 1.dp,
                                if (selectedSwatch) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                                CircleShape,
                            )
                            .semantics { contentDescription = name }
                            .clickable {
                                applyInk(color, index)
                            },
                    )
                }
                ColorPickerButton(
                    color = ink,
                    selected = selected < 0,
                    onClick = { showColorPicker = true },
                )
            }
        }
    }
    if (showColorPicker) {
        ColorPickerDialog(
            color = ink,
            onConfirm = {
                applyInk(it, -1)
                showColorPicker = false
            },
            onDismiss = { showColorPicker = false },
        )
    }
}

private val SpectrumColors = listOf(
    Color.Red,
    Color.Yellow,
    Color.Green,
    Color.Cyan,
    Color.Blue,
    Color.Magenta,
    Color.Red,
)

@Composable
private fun ColorPickerButton(
    color: Color,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val label = stringResource(R.string.color_custom)
    Box(
        Modifier
            .padding(start = 6.dp, top = 4.dp, bottom = 4.dp)
            .size(28.dp)
            .clip(CircleShape)
            .semantics { contentDescription = label }
            .clickable(onClick = onClick),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Brush.sweepGradient(SpectrumColors))
            drawCircle(Color.White, radius = size.minDimension / 2f - 5.dp.toPx())
            drawCircle(color, radius = size.minDimension / 2f - 7.dp.toPx())
        }
        Box(
            Modifier
                .matchParentSize()
                .border(
                    if (selected) 2.5.dp else 1.dp,
                    if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                    CircleShape,
                ),
        )
    }
}

@Composable
private fun ColorPickerDialog(
    color: Color,
    onConfirm: (Color) -> Unit,
    onDismiss: () -> Unit,
) {
    val start = remember(color) { color.toHsv() }
    var hue by remember { mutableStateOf(start[0]) }
    var saturation by remember { mutableStateOf(start[1]) }
    var value by remember { mutableStateOf(start[2]) }
    val current = Color.hsv(hue, saturation.coerceIn(0f, 1f), value.coerceIn(0f, 1f))
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.color_custom)) },
        text = {
            Column {
                SaturationValueBox(
                    hue = hue,
                    saturation = saturation,
                    value = value,
                    onChange = { sat, v ->
                        saturation = sat
                        value = v
                    },
                )
                Spacer(Modifier.height(16.dp))
                HueBar(hue = hue, onChange = { hue = it })
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(current) }) { Text(stringResource(R.string.action_done)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
        },
    )
}

@Composable
private fun SaturationValueBox(
    hue: Float,
    saturation: Float,
    value: Float,
    onChange: (Float, Float) -> Unit,
) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(12.dp))
            .pointerInput(hue) {
                fun emit(position: Offset) {
                    val sat = (position.x / size.width).coerceIn(0f, 1f)
                    val v = 1f - (position.y / size.height).coerceIn(0f, 1f)
                    onChange(sat, v)
                }
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    emit(down.position)
                    drag(down.id) { change ->
                        change.consume()
                        emit(change.position)
                    }
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Brush.horizontalGradient(listOf(Color.White, Color.hsv(hue, 1f, 1f))))
            drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
        }
        Canvas(Modifier.fillMaxSize()) {
            val cx = saturation * size.width
            val cy = (1f - value) * size.height
            drawCircle(Color.White, radius = 8.dp.toPx(), center = Offset(cx, cy))
            drawCircle(Color.hsv(hue, saturation, value), radius = 5.dp.toPx(), center = Offset(cx, cy))
        }
    }
}

@Composable
private fun HueBar(hue: Float, onChange: (Float) -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .pointerInput(Unit) {
                fun emit(position: Offset) {
                    onChange((position.x / size.width).coerceIn(0f, 1f) * 360f)
                }
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    emit(down.position)
                    drag(down.id) { change ->
                        change.consume()
                        emit(change.position)
                    }
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Brush.horizontalGradient(SpectrumColors))
        }
        Canvas(Modifier.fillMaxSize()) {
            val cx = (hue / 360f) * size.width
            drawCircle(Color.White, radius = 8.dp.toPx(), center = Offset(cx, size.height / 2f))
            drawCircle(Color.hsv(hue, 1f, 1f), radius = 5.dp.toPx(), center = Offset(cx, size.height / 2f))
        }
    }
}

private fun Color.toHsv(): FloatArray {
    val hsv = FloatArray(3)
    android.graphics.Color.colorToHSV(toArgb(), hsv)
    return hsv
}

@Composable
private fun SignatureCanvas(
    strokes: List<List<Offset>>,
    current: List<Offset>,
    color: Color,
    onDragStart: (Offset) -> Unit,
    onDrag: (Offset) -> Unit,
    onDragEnd: () -> Unit,
) {
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(220.dp)
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    onDragStart(down.position)
                    drag(down.id) { change ->
                        change.consume()
                        onDrag(change.position)
                    }
                    onDragEnd()
                }
            },
    ) {
        val draw: (List<Offset>) -> Unit = { stroke ->
            if (stroke.size > 1) {
                val path = androidx.compose.ui.graphics.Path()
                path.moveTo(stroke.first().x, stroke.first().y)
                stroke.drop(1).forEach { path.lineTo(it.x, it.y) }
                drawPath(
                    path,
                    color,
                    style = androidx.compose.ui.graphics.drawscope.Stroke(
                        width = 3.dp.toPx(),
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round,
                    ),
                )
            }
        }
        strokes.forEach(draw)
        draw(current)
    }
}

private fun renderSignature(strokes: List<List<Offset>>, canvasSize: IntSize, color: Color): Bitmap? {
    if (strokes.isEmpty() || canvasSize.width == 0) return null
    val width = 600
    val height = 220
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    bitmap.eraseColor(android.graphics.Color.TRANSPARENT)
    val canvas = android.graphics.Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color.toArgb()
        style = Paint.Style.STROKE
        strokeWidth = 3.5f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    val scaleX = width / canvasSize.width.toFloat()
    val scaleY = height / canvasSize.height.toFloat()
    strokes.filter { it.size > 1 }.forEach { stroke ->
        val path = AndroidPath()
        path.moveTo(stroke[0].x * scaleX, stroke[0].y * scaleY)
        stroke.drop(1).forEach { path.lineTo(it.x * scaleX, it.y * scaleY) }
        canvas.drawPath(path, paint)
    }
    return bitmap
}

private fun recolorSignature(source: Bitmap, color: Color): Bitmap {
    val result = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(result)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        colorFilter = PorterDuffColorFilter(color.toArgb(), PorterDuff.Mode.SRC_IN)
    }
    canvas.drawBitmap(source, 0f, 0f, paint)
    return result
}
