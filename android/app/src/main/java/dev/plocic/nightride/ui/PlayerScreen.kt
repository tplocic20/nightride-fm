package dev.plocic.nightride.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.NightlightRound
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.plocic.nightride.Artwork
import dev.plocic.nightride.BRAND
import dev.plocic.nightride.MusicSearch
import dev.plocic.nightride.MusicService
import dev.plocic.nightride.PlayerController
import dev.plocic.nightride.Stations
import kotlinx.coroutines.delay

@Composable
fun PlayerScreen(player: PlayerController) {
    // Current station's accent, eased on change like the iOS client; the
    // Nightride magenta before anything plays.
    val accent by animateColorAsState(
        targetValue = player.current.accentColor(),
        animationSpec = tween(350),
        label = "accent",
    )
    val radiusPx = with(LocalDensity.current) { 440.dp.toPx() }

    // Brief "copied" confirmation, mirroring the iOS toast.
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(1400)
            copied = false
        }
    }

    Box(
        modifier = Modifier.fillMaxSize().background(NightGround),
        contentAlignment = Alignment.Center,
    ) {
        // Subtle per-station radial glow over the dark ground.
        Box(
            modifier = Modifier.fillMaxSize().background(
                Brush.radialGradient(
                    colors = listOf(accent.copy(alpha = 0.22f), Color.Transparent),
                    radius = radiusPx,
                )
            )
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 24.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceEvenly,
        ) {
            StationHeader(player, accent) { copied = true }
            TransportControls(player, accent)
            StationPicker(player, accent)
        }

        AnimatedVisibility(
            visible = copied,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 36.dp),
        ) {
            Toast("copied to clipboard", accent)
        }
    }
}

@Composable
private fun StationHeader(player: PlayerController, accent: Color, onCopied: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Cover(player, accent)

        Text(
            text = player.current?.name ?: "Tap play to start",
            color = Color.White,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )

        // Reserve both lines so a wrapping title doesn't nudge the cover up and
        // down as tracks change.
        Text(
            text = player.nowPlaying.ifEmpty { BRAND },
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            minLines = 2,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        TrackActions(player, accent, onCopied)
    }
}

@Composable
private fun Cover(player: PlayerController, accent: Color) {
    val station = player.current
    val resId = station?.let { Artwork.resId(it) }
    if (station != null && resId != null) {
        Image(
            bitmap = ImageBitmap.imageResource(resId),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            filterQuality = FilterQuality.None,  // keep the pixel art crisp when scaled
            modifier = Modifier
                .size(224.dp)
                .shadow(24.dp, RectangleShape, clip = false, ambientColor = accent, spotColor = accent)
                .border(1.dp, accent.copy(alpha = 0.6f)),
        )
    } else {
        Icon(
            imageVector = if (player.isPlaying) Icons.Filled.GraphicEq else Icons.Filled.NightlightRound,
            contentDescription = null,
            tint = accent,
            modifier = Modifier.size(96.dp),
        )
    }
}

/**
 * Quick "I love this song" row — search the live track on a streaming service or
 * copy "Artist — Title". Only shown once a real track is known.
 */
@Composable
private fun TrackActions(player: PlayerController, accent: Color, onCopied: () -> Unit) {
    val raw = player.nowPlaying
    if (raw.isBlank()) return

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        MusicService.values().forEach { service ->
            ActionChip(service.label, accent) {
                MusicSearch.open(context, scope, service, raw)
            }
        }
        ActionChip("copy", accent) {
            MusicSearch.copy(context, raw)
            onCopied()
        }
    }
}

@Composable
private fun ActionChip(label: String, accent: Color, onClick: () -> Unit) {
    Text(
        text = label,
        color = Color.White.copy(alpha = 0.85f),
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Monospace,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .border(1.dp, accent.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

@Composable
private fun TransportControls(player: PlayerController, accent: Color) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(36.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = player::prev) {
            Icon(
                Icons.Filled.SkipPrevious, contentDescription = "Previous station",
                tint = Color.White, modifier = Modifier.size(36.dp),
            )
        }
        IconButton(onClick = player::togglePlayPause, modifier = Modifier.size(88.dp)) {
            Icon(
                imageVector = if (player.isPlaying) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle,
                contentDescription = if (player.isPlaying) "Pause" else "Play",
                tint = accent,
                modifier = Modifier.size(72.dp),
            )
        }
        IconButton(onClick = player::next) {
            Icon(
                Icons.Filled.SkipNext, contentDescription = "Next station",
                tint = Color.White, modifier = Modifier.size(36.dp),
            )
        }
    }
}

@Composable
private fun StationPicker(player: PlayerController, accent: Color) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        Surface(
            onClick = { expanded = true },
            color = Color.White.copy(alpha = 0.08f),
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, accent.copy(alpha = 0.4f)),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.List, contentDescription = null, tint = Color.White)
                Spacer(Modifier.size(12.dp))
                Text("Stations", color = Color.White)
                Spacer(Modifier.weight(1f))
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null, tint = Color.White)
            }
        }

        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Stations.all.forEach { station ->
                val selected = player.current?.id == station.id
                DropdownMenuItem(
                    text = { Text(station.name) },
                    onClick = {
                        player.play(station)
                        expanded = false
                    },
                    leadingIcon = if (selected) {
                        { Icon(Icons.Filled.VolumeUp, contentDescription = null) }
                    } else null,
                )
            }
        }
    }
}

/** Tiny non-intrusive confirmation pill (after copying), part of the CRT chrome. */
@Composable
private fun Toast(text: String, accent: Color) {
    Text(
        text = text,
        color = Color.White,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Monospace,
        modifier = Modifier
            .clip(CircleShape)
            .background(Color(0x1D, 0x14, 0x22).copy(alpha = 0.92f))
            .border(1.dp, accent.copy(alpha = 0.6f), CircleShape)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    )
}
