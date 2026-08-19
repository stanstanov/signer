package lt.turron.sivelo.ui.theme

import android.content.Context
import android.util.TypedValue
import android.view.ContextThemeWrapper
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext

@Composable
fun SignerTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    MaterialTheme(
        colorScheme = systemColorScheme(context, dark),
        content = content,
    )
}

private fun systemColorScheme(context: Context, dark: Boolean): ColorScheme {
    val themed = ContextThemeWrapper(
        context,
        if (dark) android.R.style.Theme_DeviceDefault else android.R.style.Theme_DeviceDefault_Light,
    )
    val accent = themed.themeColor(
        android.R.attr.colorControlActivated,
        themed.themeColor(android.R.attr.colorAccent),
    )
    val onAccent = if (accent.luminance() > 0.5f) Color.Black else Color.White
    return if (dark) {
        darkColorScheme(
            primary = accent,
            onPrimary = onAccent,
            primaryContainer = accent,
            onPrimaryContainer = onAccent,
            secondary = accent,
            onSecondary = onAccent,
            tertiary = accent,
            onTertiary = onAccent,
        )
    } else {
        lightColorScheme(
            primary = accent,
            onPrimary = onAccent,
            primaryContainer = accent,
            onPrimaryContainer = onAccent,
            secondary = accent,
            onSecondary = onAccent,
            tertiary = accent,
            onTertiary = onAccent,
        )
    }
}

private fun Context.themeColor(attr: Int, fallback: Color = Color.Unspecified): Color {
    val array = obtainStyledAttributes(intArrayOf(attr))
    val color = try {
        if (array.hasValue(0)) {
            Color(array.getColor(0, 0))
        } else {
            fallback
        }
    } finally {
        array.recycle()
    }
    if (color != Color.Unspecified) return color
    val value = TypedValue()
    return if (theme.resolveAttribute(attr, value, true) && value.type >= TypedValue.TYPE_FIRST_COLOR_INT) {
        Color(value.data)
    } else {
        fallback
    }
}
