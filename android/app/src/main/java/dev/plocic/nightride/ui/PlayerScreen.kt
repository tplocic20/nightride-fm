package dev.plocic.nightride.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.plocic.nightride.BRAND
import dev.plocic.nightride.PlayerController
import dev.plocic.nightride.Stations

@Composable
fun PlayerScreen(player: PlayerController) {
    val gradient = Brush.linearGradient(listOf(NightTop, NightBottom))

    Box(
        modifier = Modifier.fillMaxSize().background(gradient),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 24.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceEvenly,
        ) {
            StationHeader(player)
            TransportControls(player)
            StationPicker(player)
        }
    }
}

@Composable
private fun StationHeader(player: PlayerController) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = if (player.isPlaying) Icons.Filled.GraphicEq else Icons.Filled.NightlightRound,
            contentDescription = null,
            tint = NeonPink,
            modifier = Modifier.size(96.dp),
        )
        Text(
            text = player.current?.name ?: "Tap play to start",
            color = Color.White,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Text(
            text = player.nowPlaying.ifEmpty { BRAND },
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun TransportControls(player: PlayerController) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = player::prev) {
            Icon(
                Icons.Filled.SkipPrevious, contentDescription = "Previous station",
                tint = Color.White, modifier = Modifier.size(40.dp),
            )
        }
        IconButton(onClick = player::togglePlayPause, modifier = Modifier.size(88.dp)) {
            Icon(
                imageVector = if (player.isPlaying) Icons.Filled.PauseCircle else Icons.Filled.PlayCircle,
                contentDescription = if (player.isPlaying) "Pause" else "Play",
                tint = Color.White,
                modifier = Modifier.size(88.dp),
            )
        }
        IconButton(onClick = player::next) {
            Icon(
                Icons.Filled.SkipNext, contentDescription = "Next station",
                tint = Color.White, modifier = Modifier.size(40.dp),
            )
        }
    }
}

@Composable
private fun StationPicker(player: PlayerController) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        Surface(
            color = Color.White.copy(alpha = 0.1f),
            shape = MaterialTheme.shapes.medium,
            onClick = { expanded = true },
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Filled.List, contentDescription = null, tint = Color.White)
                Text("Stations", color = Color.White)
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
