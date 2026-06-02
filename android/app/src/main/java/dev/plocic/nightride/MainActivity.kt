package dev.plocic.nightride

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import dev.plocic.nightride.ui.NightrideTheme
import dev.plocic.nightride.ui.PlayerScreen

class MainActivity : ComponentActivity() {

    private lateinit var player: PlayerController

    private val requestNotifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* optional */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        player = PlayerController(this)

        // Android 13+ needs runtime consent to show the playback notification.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        setContent {
            NightrideTheme {
                PlayerScreen(player)
            }
        }
    }

    // Bind only while the UI is visible; playback (and the service) outlive it.
    override fun onStart() {
        super.onStart()
        player.connect()
    }

    override fun onStop() {
        super.onStop()
        player.release()
    }
}
