package com.mediahub.app.crossover

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mediahub.core.CrossoverBus
import com.mediahub.netflix.NetflixAppScreen
import com.mediahub.spotify.PendingAudioImport
import com.mediahub.spotify.SpotifyAppScreen
import com.mediahub.youtube.YouTubeAppScreen

enum class AppMode(val title: String, val subtitle: String, val accent: Color, val logoRes: Int) {
    YOUTUBE("YouTube", "Vidéos, Shorts & Abonnements", Color(0xFFFF0000), R.drawable.logo_youtube),
    NETFLIX("Netflix", "Films & Séries (Movix)", Color(0xFFE50914), R.drawable.logo_netflix),
    SPOTIFY("Spotify", "Musique, Podcasts & Skyrock", Color(0xFF1ED760), R.drawable.logo_spotify)
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val hasAudioImport = handleAudioIntent(intent)
        enableEdgeToEdge()
        setContent {
            val ctx = LocalContext.current
            val prefs = remember { ctx.getSharedPreferences("crossover_prefs", Context.MODE_PRIVATE) }
            var activeMode by remember {
                val saved = if (hasAudioImport) AppMode.SPOTIFY.name else prefs.getString("active_app", AppMode.YOUTUBE.name)
                mutableStateOf(AppMode.entries.firstOrNull { it.name == saved } ?: AppMode.YOUTUBE)
            }
            var showSwitcher by remember { mutableStateOf(false) }

            LaunchedEffect(Unit) {
                CrossoverBus.openSwitcherEvents.collect {
                    showSwitcher = true
                }
            }

            Box(modifier = Modifier.fillMaxSize()) {
                key(activeMode) {
                    when (activeMode) {
                        AppMode.YOUTUBE -> YouTubeAppScreen()
                        AppMode.NETFLIX -> NetflixAppScreen()
                        AppMode.SPOTIFY -> SpotifyAppScreen()
                    }
                }

                if (showSwitcher) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.78f))
                            .clickable { showSwitcher = false },
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            modifier = Modifier
                                .widthIn(max = 420.dp)
                                .padding(horizontal = 24.dp)
                                .clip(RoundedCornerShape(24.dp))
                                .background(Color(0xFF141414))
                                .clickable(enabled = false) {}
                                .padding(22.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text("Changer d'application", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(4.dp))
                            Text("Appui long sur Accueil à tout moment", color = Color(0xFFB3B3B3), fontSize = 12.sp)
                            Spacer(Modifier.height(18.dp))

                            AppMode.entries.forEach { mode ->
                                val isCurrent = mode == activeMode
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 6.dp)
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(Color(if (isCurrent) 0xFF2B2B2B else 0xFF1E1E1E))
                                        .border(1.5.dp, if (isCurrent) mode.accent else Color.White.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
                                        .clickable {
                                            activeMode = mode
                                            prefs.edit().putString("active_app", mode.name).apply()
                                            showSwitcher = false
                                        }
                                        .padding(14.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Image(
                                        painter = painterResource(mode.logoRes),
                                        contentDescription = mode.title,
                                        modifier = Modifier.size(48.dp).clip(RoundedCornerShape(12.dp))
                                    )
                                    Spacer(Modifier.width(16.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(mode.title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                                        Text(mode.subtitle, color = Color(0xFFB3B3B3), fontSize = 12.sp)
                                    }
                                    if (isCurrent) {
                                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = mode.accent)
                                    }
                                }
                            }

                            Spacer(Modifier.height(10.dp))
                            TextButton(onClick = { showSwitcher = false }) {
                                Text("Fermer", color = Color.White.copy(alpha = 0.8f), fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAudioIntent(intent)
    }

    private fun handleAudioIntent(intent: Intent?): Boolean {
        if (intent?.action == Intent.ACTION_VIEW) {
            intent.data?.let {
                PendingAudioImport.pendingUri = it
                return true
            }
        }
        return false
    }
}
