package dev.plocic.nightride.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import dev.plocic.nightride.Station

// Synthwave palette, shared with the Apple clients: a dark ground with a
// per-station neon accent (default magenta when idle), mirroring ios/ContentView.
val NightGround = Color(0xFF0E0A12)
val DefaultAccent = Color(0xFFCC55FF)

/** Opaque Compose colour for a station's accent, or the Nightride magenta. */
fun Station?.accentColor(): Color = this?.let {
    Color(
        red = (it.accentHex shr 16) and 0xFF,
        green = (it.accentHex shr 8) and 0xFF,
        blue = it.accentHex and 0xFF,
    )
} ?: DefaultAccent

private val NightColors = darkColorScheme(
    primary = DefaultAccent,
    background = NightGround,
    surface = NightGround,
    onPrimary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun NightrideTheme(content: @Composable () -> Unit) {
    // Always dark — the synthwave look doesn't have a light variant.
    MaterialTheme(colorScheme = NightColors, content = content)
}
