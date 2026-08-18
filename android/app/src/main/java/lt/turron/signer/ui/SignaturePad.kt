package lt.turron.signer.ui

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Path as AndroidPath
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
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
import kotlin.math.max

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
    var hue by remember { mutableStateOf(0f) }
    val showingPreview = preview != null && strokes.isEmpty() && current.isEmpty()
    val hasInk = strokes.isNotEmpty() || current.isNotEmpty()

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
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
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
                    val selectedSwatch = selected == index && !showingPreview
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
                            .clickable(enabled = !showingPreview) {
                                selected = index
                                ink = color
                            },
                    )
                }
            }
            if (!showingPreview) {
                Text(stringResource(R.string.color_custom), Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.labelMedium)
                Slider(
                    value = hue,
                    onValueChange = {
                        hue = it
                        selected = -1
                        ink = Color.hsv(it, 0.85f, 0.75f)
                    },
                    valueRange = 0f..360f,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }
    }
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
