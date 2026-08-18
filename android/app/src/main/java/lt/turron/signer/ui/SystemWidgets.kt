package lt.turron.signer.ui

import android.content.Context
import android.view.ContextThemeWrapper
import android.widget.SeekBar
import android.widget.Switch
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

@Composable
fun SystemSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    modifier: Modifier = Modifier,
) {
    val steps = 1000
    val onValueChangeState = rememberUpdatedState(onValueChange)
    val rangeState = rememberUpdatedState(valueRange)
    val dark = isSystemInDarkTheme()
    key(dark) {
        AndroidView(
            modifier = modifier.height(48.dp),
            factory = { context ->
                SeekBar(deviceDefaultContext(context, dark)).apply {
                    max = steps
                    splitTrack = false
                    setOnSeekBarChangeListener(
                        object : SeekBar.OnSeekBarChangeListener {
                            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                                if (!fromUser) return
                                val range = rangeState.value
                                val span = range.endInclusive - range.start
                                onValueChangeState.value(range.start + span * progress / steps)
                            }
                            override fun onStartTrackingTouch(seekBar: SeekBar) = Unit
                            override fun onStopTrackingTouch(seekBar: SeekBar) = Unit
                        },
                    )
                }
            },
            update = { seekBar ->
                val range = valueRange
                val span = range.endInclusive - range.start
                val progress = (((value - range.start) / span) * steps).toInt().coerceIn(0, steps)
                if (!seekBar.isPressed && seekBar.progress != progress) {
                    seekBar.progress = progress
                }
            },
        )
    }
}

@Composable
fun SystemSwitch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val onCheckedChangeState = rememberUpdatedState(onCheckedChange)
    val dark = isSystemInDarkTheme()
    key(dark) {
        AndroidView(
            modifier = modifier,
            factory = { context ->
                Switch(deviceDefaultContext(context, dark)).apply {
                    isChecked = checked
                    isEnabled = enabled
                    setOnCheckedChangeListener { _, isChecked ->
                        onCheckedChangeState.value(isChecked)
                    }
                }
            },
            update = { view ->
                view.isEnabled = enabled
                if (view.isChecked != checked) {
                    view.setOnCheckedChangeListener(null)
                    view.isChecked = checked
                    view.setOnCheckedChangeListener { _, isChecked ->
                        onCheckedChangeState.value(isChecked)
                    }
                }
            },
        )
    }
}

private fun deviceDefaultContext(context: Context, dark: Boolean): ContextThemeWrapper {
    val theme = if (dark) {
        android.R.style.Theme_DeviceDefault
    } else {
        android.R.style.Theme_DeviceDefault_Light
    }
    return ContextThemeWrapper(context, theme)
}
