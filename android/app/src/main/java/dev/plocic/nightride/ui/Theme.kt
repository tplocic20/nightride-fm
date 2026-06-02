package dev.plocic.nightride.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Synthwave palette — neon pink on deep indigo, shared with the Apple clients.
val NightTop = Color(0xFF0D0526)
val NightBottom = Color(0xFF331452)
val NeonPink = Color(0xFFFF4D9D)

private val NightColors = darkColorScheme(
    primary = NeonPink,
    background = NightTop,
    surface = NightTop,
    onPrimary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun NightrideTheme(content: @Composable () -> Unit) {
    // Always dark — the synthwave look doesn't have a light variant.
    MaterialTheme(colorScheme = NightColors, content = content)
}
