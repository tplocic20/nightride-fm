package dev.plocic.nightride.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.NightlightRound
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.unit.sp
import dev.plocic.nightride.Artwork
import dev.plocic.nightride.BRAND
import dev.plocic.nightride.MusicSearch
import dev.plocic.nightride.MusicService
import dev.plocic.nightride.PlayerController
import dev.plocic.nightride.Station
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
    // Whether the "About" dialog (attribution + contact) is showing.
    var showAbout by remember { mutableStateOf(false) }
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

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing),
        ) {
            if (minOf(maxWidth, maxHeight) >= 600.dp) {
                // Tablet: Spotify-style split — a responsive grid of station covers
                // fills the left, the simple vertical "now playing" column on the right.
                Row(modifier = Modifier.fillMaxSize()) {
                    StationGrid(
                        player = player,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    )
                    Box(
                        Modifier
                            .width(1.dp)
                            .fillMaxHeight()
                            .background(accent.copy(alpha = 0.2f))
                    )
                    Column(
                        modifier = Modifier
                            .width(420.dp)
                            .fillMaxHeight()
                            .background(Color(0xFF140E1A).copy(alpha = 0.5f))
                            .padding(28.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
                    ) {
                        Cover(player, accent, 200.dp)
                        TrackInfo(player)
                        TrackActions(player, accent) { copied = true }
                        TransportControls(player, accent)
                    }
                }
            } else if (maxWidth > maxHeight) {
                // Landscape: cover on the left, controls on the right, so nothing
                // gets pushed off the short vertical axis.
                val coverSize = minOf(maxHeight * 0.82f, maxWidth * 0.42f)
                Row(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 24.dp),
                    horizontalArrangement = Arrangement.spacedBy(32.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        Cover(player, accent, coverSize)
                    }
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
                    ) {
                        TrackInfo(player)
                        TrackActions(player, accent) { copied = true }
                        TransportControls(player, accent)
                        StationPicker(player, accent)
                    }
                }
            } else {
                // Portrait: a single centred vertical stack.
                Column(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.SpaceEvenly,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Cover(player, accent, 224.dp)
                        TrackInfo(player)
                        TrackActions(player, accent) { copied = true }
                    }
                    TransportControls(player, accent)
                    StationPicker(player, accent)
                }
            }
        }

        AnimatedVisibility(
            visible = copied,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 36.dp),
        ) {
            Toast("copied to clipboard", accent)
        }

        // Discreet info button → "About" (attribution + contact).
        IconButton(
            onClick = { showAbout = true },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(4.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Info,
                contentDescription = "About",
                tint = Color.White.copy(alpha = 0.45f),
            )
        }

        if (showAbout) {
            AboutDialog(onDismiss = { showAbout = false })
        }
    }
}

/**
 * Small "About" dialog — personal attribution + where to reach the author.
 * The repo is public, so bug reports go to GitHub Issues.
 */
@Composable
private fun AboutDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val accent = Color(0xFFCC55FF)
    val version = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull().orEmpty()
    }

    fun open(url: String) {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            color = Color(0xFF15101C),
            shape = RoundedCornerShape(16.dp),
            border = BorderStroke(1.dp, accent.copy(alpha = 0.4f)),
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    text = "Nightride.fm Player",
                    color = Color.White,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                )
                if (version.isNotEmpty()) {
                    Text(
                        text = "v$version",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                    )
                }
                Text(
                    text = "Made by Tomasz Plocic",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = 14.sp,
                    fontFamily = FontFamily.Monospace,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AboutChip("plocic.dev", accent) { open("https://plocic.dev") }
                    AboutChip("report a bug ↗", accent) {
                        open("https://github.com/tplocic20/nightride-fm/issues")
                    }
                }
                Text(
                    text = "Unofficial fan project — not affiliated with Nightride FM.",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/** Bordered mono link chip used inside the About dialog. */
@Composable
private fun AboutChip(label: String, accent: Color, onClick: () -> Unit) {
    Text(
        text = label,
        color = accent,
        fontSize = 13.sp,
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
private fun TrackInfo(player: PlayerController) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = player.current?.name ?: "Tap play to start",
            color = Color.White,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        // Reserve both lines so a wrapping title doesn't nudge the layout as
        // tracks change.
        Text(
            text = player.nowPlaying.ifEmpty { BRAND },
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            minLines = 2,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun Cover(player: PlayerController, accent: Color, size: Dp) {
    val station = player.current
    val resId = station?.let { Artwork.resId(it) }
    if (station != null && resId != null) {
        Image(
            bitmap = ImageBitmap.imageResource(resId),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            filterQuality = FilterQuality.None,  // keep the pixel art crisp when scaled
            modifier = Modifier
                .size(size)
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
        maxLines = 1,
        softWrap = false,
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StationPicker(player: PlayerController, accent: Color) {
    var showSheet by remember { mutableStateOf(false) }

    Surface(
        onClick = { showSheet = true },
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

    if (showSheet) {
        ModalBottomSheet(
            onDismissRequest = { showSheet = false },
            containerColor = Color(0xFF15101C),
            dragHandle = { BottomSheetDefaults.DragHandle(color = Color.White.copy(alpha = 0.3f)) },
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .navigationBarsPadding()
                    .padding(bottom = 12.dp),
            ) {
                Text(
                    text = "Stations",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp),
                )
                Stations.all.forEach { station ->
                    StationRow(
                        station = station,
                        selected = player.current?.id == station.id,
                    ) {
                        player.play(station)
                        showSheet = false
                    }
                }
            }
        }
    }
}

/** One station row in the picker sheet — cover bordered in the station's own
 *  neon accent, with the live station highlighted. */
@Composable
private fun StationRow(station: Station, selected: Boolean, onClick: () -> Unit) {
    val rowAccent = station.accentColor()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(if (selected) rowAccent.copy(alpha = 0.12f) else Color.Transparent)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Artwork.resId(station)?.let { resId ->
            Image(
                bitmap = ImageBitmap.imageResource(resId),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                filterQuality = FilterQuality.None,
                modifier = Modifier
                    .size(44.dp)
                    .border(1.dp, rowAccent.copy(alpha = 0.7f)),
            )
        }
        Text(
            text = station.name,
            color = if (selected) rowAccent else Color.White,
            fontSize = 16.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            modifier = Modifier.weight(1f),
        )
        if (selected) {
            Icon(
                imageVector = Icons.Filled.GraphicEq,
                contentDescription = "Now playing",
                tint = rowAccent,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

/** Responsive grid of station covers — the tablet left pane. */
@Composable
private fun StationGrid(player: PlayerController, modifier: Modifier = Modifier) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 150.dp),
        modifier = modifier,
        contentPadding = PaddingValues(24.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        items(Stations.all) { station ->
            StationTile(station, selected = player.current?.id == station.id) {
                player.play(station)
            }
        }
    }
}

@Composable
private fun StationTile(station: Station, selected: Boolean, onClick: () -> Unit) {
    val accent = station.accentColor()
    Column(
        modifier = Modifier.clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val coverModifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) accent else Color.White.copy(alpha = 0.15f),
            )
        val resId = Artwork.resId(station)
        if (resId != null) {
            Image(
                bitmap = ImageBitmap.imageResource(resId),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                filterQuality = FilterQuality.None,
                modifier = coverModifier,
            )
        } else {
            Box(coverModifier.background(Color(0xFF140E1A)))
        }
        Spacer(Modifier.size(8.dp))
        Text(
            text = station.name.lowercase(),
            color = if (selected) accent else Color.White.copy(alpha = 0.8f),
            fontSize = 13.sp,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
        )
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
