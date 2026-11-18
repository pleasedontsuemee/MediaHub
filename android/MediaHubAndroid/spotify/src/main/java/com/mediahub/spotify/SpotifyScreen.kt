package com.mediahub.spotify

import android.app.Application
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.ExoPlayer
import coil.compose.AsyncImage
import com.mediahub.core.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

enum class SPTab(val label: String) {
    HOME("Accueil"),
    SEARCH("Rechercher"),
    LIBRARY("Bibliothèque"),
    SETTINGS("Réglages")
}

class SpotifyViewModel(app: Application) : AndroidViewModel(app) {
    val player: ExoPlayer = ExoPlayer.Builder(app).build()
    private var jinglePlayer: MediaPlayer? = null
    private var skyJob: Job? = null

    var selectedTab by mutableStateOf(SPTab.HOME)
    var homeData by mutableStateOf<SPHomeData?>(null)
    var searchQuery by mutableStateOf("")
    var searchData by mutableStateOf<SPSearchData?>(null)

    var likedTracks by mutableStateOf<List<SPTrack>>(emptyList())
    var downloadedTracks by mutableStateOf<List<SPTrack>>(emptyList())
    var userPlaylists by mutableStateOf<List<SPCollection>>(emptyList())

    var activeCollection by mutableStateOf<SPCollection?>(null)
    var activeArtistId by mutableStateOf<Pair<String, String>?>(null)
    var activeAlbumId by mutableStateOf<Pair<String, String>?>(null)

    var currentTrack by mutableStateOf<SPTrack?>(null)
    var queue by mutableStateOf<List<SPTrack>>(emptyList())
    var isPlaying by mutableStateOf(false)
    var isNowPlayingOpen by mutableStateOf(false)
    var isSkyrockMode by mutableStateOf(false)
    var streamLabel by mutableStateOf("")
    var trackOptionsTarget by mutableStateOf<SPTrack?>(null)
    var arlDraft by mutableStateOf("")
    var arlStatus by mutableStateOf("")
    var showCreatePlaylist by mutableStateOf(false)

    init {
        SpotifyEngine.init(app)
        arlDraft = SpotifyEngine.getARL()
        loadHome()
    }

    fun loadHome() {
        viewModelScope.launch {
            homeData = SpotifyEngine.fetchHome()
        }
    }

    fun performSearch(q: String) {
        searchQuery = q
        if (q.isBlank()) { searchData = null; return }
        viewModelScope.launch {
            delay(350)
            if (searchQuery == q) {
                searchData = SpotifyEngine.search(q)
            }
        }
    }

    fun playTrack(track: SPTrack, newQueue: List<SPTrack>? = null) {
        skyJob?.cancel()
        stopJingle()
        if (newQueue != null) queue = newQueue
        currentTrack = track
        isPlaying = true

        if (isSkyrockMode) {
            playWithSkyrock(track)
        } else {
            viewModelScope.launch { loadAndPlay(track, fadeIn = false) }
        }
    }

    fun toggleSkyrock() {
        isSkyrockMode = !isSkyrockMode
        if (isSkyrockMode) {
            currentTrack?.let { playWithSkyrock(it) }
        } else {
            skyJob?.cancel()
            stopJingle()
            player.volume = 1f
            player.playbackParameters = PlaybackParameters(1f, 1f)
        }
    }

    private fun playWithSkyrock(track: SPTrack) {
        skyJob?.cancel()
        stopJingle()
        val ctx = getApplication<Application>()
        val mp = MediaPlayer.create(ctx, R.raw.skyrock)
        if (mp == null) {
            viewModelScope.launch { loadAndPlay(track, fadeIn = false) }
            return
        }
        jinglePlayer = mp
        player.pause()
        player.volume = 0f
        mp.setVolume(1f, 1f)
        mp.start()

        val durMs = mp.duration.toLong().coerceAtLeast(1000L)
        val crossfadeMs = 650L
        val waitMs = (durMs - crossfadeMs).coerceAtLeast(200L)

        skyJob = viewModelScope.launch {
            val resolved = SpotifyEngine.resolvePlayableStream(track)
            delay(waitMs)
            if (resolved != null) {
                streamLabel = resolved.second
                player.setMediaItem(MediaItem.fromUri(resolved.first))
                player.playbackParameters = PlaybackParameters(1.025f, 1.025f)
                player.volume = 0f
                player.prepare()
                player.play()
                isPlaying = true
            }
            val steps = 16
            for (i in 1..steps) {
                val p = i.toFloat() / steps
                jinglePlayer?.setVolume(1f - p, 1f - p)
                player.volume = p
                delay(crossfadeMs / steps)
            }
            stopJingle()
            player.volume = 1f
        }
    }

    private suspend fun loadAndPlay(track: SPTrack, fadeIn: Boolean) {
        val resolved = SpotifyEngine.resolvePlayableStream(track) ?: return
        streamLabel = resolved.second
        player.setMediaItem(MediaItem.fromUri(resolved.first))
        player.playbackParameters = if (isSkyrockMode) PlaybackParameters(1.025f, 1.025f) else PlaybackParameters(1f, 1f)
        player.volume = if (fadeIn) 0f else 1f
        player.prepare()
        player.play()
        isPlaying = true
    }

    fun togglePlayPause() {
        if (player.isPlaying) {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    fun importAudioUris(uris: List<Uri>) {
        val ctx = getApplication<Application>()
        val dir = File(ctx.filesDir, "sp_imports").apply { mkdirs() }
        val imported = mutableListOf<SPTrack>()
        for (uri in uris) {
            try {
                val dest = File(dir, "local_${UUID.randomUUID().toString().take(8)}.mp3")
                ctx.contentResolver.openInputStream(uri)?.use { inp ->
                    dest.outputStream().use { out -> inp.copyTo(out) }
                }
                val mmr = MediaMetadataRetriever()
                mmr.setDataSource(dest.absolutePath)
                val title = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: uri.lastPathSegment ?: "Audio importé"
                val artist = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: "Fichier local"
                val dur = (mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull() ?: 180000) / 1000
                mmr.release()
                imported.add(SPTrack(dest.nameWithoutExtension, title, artist, albumTitle = "Fichiers importés", durationSec = dur, localFilePath = dest.absolutePath))
            } catch (_: Exception) {}
        }
        downloadedTracks = imported + downloadedTracks
    }

    private fun stopJingle() {
        try { jinglePlayer?.stop(); jinglePlayer?.release() } catch (_: Exception) {}
        jinglePlayer = null
    }

    override fun onCleared() {
        stopJingle()
        player.release()
    }
}

@Composable
fun SpotifyAppScreen(vm: SpotifyViewModel = viewModel()) {
    val isTablet = rememberIsTablet()
    val widthDp = LocalConfiguration.current.screenWidthDp
    val gridCols = if (widthDp >= 900) 4 else if (widthDp >= 600) 3 else 2
    val context = LocalContext.current
    val bg = Color(0xFF121212)

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) {
            vm.importAudioUris(uris)
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when (vm.selectedTab) {
                    SPTab.HOME -> SPHomeContent(vm, isTablet)
                    SPTab.SEARCH -> SPSearchContent(vm, gridCols)
                    SPTab.LIBRARY -> SPLibraryContent(vm)
                    SPTab.SETTINGS -> SPSettingsContent(vm, context)
                }
            }

            // Mini Player
            if (vm.currentTrack != null) {
                val cur = vm.currentTrack!!
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Row(
                        modifier = Modifier
                            .widthIn(max = if (isTablet) 720.dp else 1000.dp)
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFF282828))
                            .clickable { vm.isNowPlayingOpen = true }
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        AsyncImage(model = cur.coverUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(42.dp).clip(RoundedCornerShape(4.dp)).background(Color(0xFF181818)))
                        Spacer(Modifier.width(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(cur.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(cur.artistName, color = Color(0xFFB3B3B3), fontSize = 12.sp, maxLines = 1)
                        }
                        IconButton(onClick = { vm.toggleSkyrock() }) {
                            Icon(Icons.Default.Radio, contentDescription = "Skyrock", tint = if (vm.isSkyrockMode) Color(0xFF009EF5) else Color(0xFFB3B3B3))
                        }
                        IconButton(onClick = { vm.togglePlayPause() }) {
                            Icon(if (vm.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null, tint = Color.White)
                        }
                    }
                }
            }

            // Bottom Tab Bar (Always at bottom on Phone & Tablet)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black)
                    .navigationBarsPadding(),
                contentAlignment = Alignment.Center
            ) {
                Row(
                    modifier = Modifier
                        .widthIn(max = if (isTablet) 640.dp else 1000.dp)
                        .fillMaxWidth()
                        .height(54.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SPTab.entries.forEach { tab ->
                        val sel = vm.selectedTab == tab
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .adaptiveHomeTabGesture(isHome = tab == SPTab.HOME) { vm.selectedTab = tab },
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                imageVector = when (tab) {
                                    SPTab.HOME -> Icons.Default.Home
                                    SPTab.SEARCH -> Icons.Default.Search
                                    SPTab.LIBRARY -> Icons.Default.LibraryMusic
                                    SPTab.SETTINGS -> Icons.Default.Settings
                                },
                                contentDescription = tab.label,
                                tint = if (sel) Color.White else Color(0xFFB3B3B3),
                                modifier = Modifier.size(22.dp)
                            )
                            Text(tab.label, fontSize = 10.sp, color = if (sel) Color.White else Color(0xFFB3B3B3))
                        }
                    }
                }
            }
        }

        // Collection / Downloads Detail Overlay
        if (vm.activeCollection != null) {
            val col = vm.activeCollection!!
            var tracks by remember(col.id, vm.downloadedTracks.size) { mutableStateOf(if (col.id == "offline_downloads") vm.downloadedTracks else col.tracks) }
            LaunchedEffect(col.id) {
                if (!col.isUserCreated) tracks = SpotifyEngine.fetchCollectionTracks(col)
            }
            Column(modifier = Modifier.fillMaxSize().background(bg).statusBarsPadding()) {
                Row(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { vm.activeCollection = null }) { Icon(Icons.Default.ArrowBack, contentDescription = null, tint = Color.White) }
                    Text(col.title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    if (col.id == "offline_downloads") {
                        Button(
                            onClick = { filePicker.launch(arrayOf("audio/*")) },
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1ED760))
                        ) {
                            Icon(Icons.Default.CreateNewFolder, contentDescription = null, tint = Color.Black)
                            Spacer(Modifier.width(6.dp))
                            Text("Importer", color = Color.Black, fontWeight = FontWeight.Bold)
                        }
                    }
                }
                LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(tracks) { t ->
                        SPTrackRow(t, tracks, vm)
                    }
                }
            }
        }

        // Artist Page Overlay
        if (vm.activeArtistId != null) {
            val (aid, aname) = vm.activeArtistId!!
            var details by remember(aid) { mutableStateOf<SPArtistDetails?>(null) }
            LaunchedEffect(aid) { details = SpotifyEngine.fetchArtistDetails(aid) }
            Box(modifier = Modifier.fillMaxSize().background(bg).statusBarsPadding()) {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().height(260.dp)) {
                            AsyncImage(model = details?.pictureUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            Box(modifier = Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, bg))))
                            IconButton(onClick = { vm.activeArtistId = null }, modifier = Modifier.align(Alignment.TopStart).padding(10.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape)) {
                                Icon(Icons.Default.ArrowBack, contentDescription = null, tint = Color.White)
                            }
                            Text(details?.name ?: aname, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Black, modifier = Modifier.align(Alignment.BottomStart).padding(16.dp))
                        }
                    }
                    itemsIndexed(details?.topTracks ?: emptyList()) { idx, t ->
                        Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("${idx + 1}", color = Color(0xFFB3B3B3), modifier = Modifier.width(26.dp))
                            SPTrackRow(t, details?.topTracks ?: emptyList(), vm)
                        }
                    }
                }
            }
        }

        // Album Page Overlay
        if (vm.activeAlbumId != null) {
            val (alId, alTitle) = vm.activeAlbumId!!
            var details by remember(alId) { mutableStateOf<SPAlbumDetails?>(null) }
            LaunchedEffect(alId) { details = SpotifyEngine.fetchAlbumDetails(alId) }
            Column(modifier = Modifier.fillMaxSize().background(bg).statusBarsPadding()) {
                Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { vm.activeAlbumId = null }) { Icon(Icons.Default.ArrowBack, contentDescription = null, tint = Color.White) }
                    Text(details?.title ?: alTitle, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
                LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(details?.tracks ?: emptyList()) { t -> SPTrackRow(t, details?.tracks ?: emptyList(), vm) }
                }
            }
        }

        // Fullscreen Now Playing Overlay (2-pane on Tablet Landscape, Portrait on Phone)
        if (vm.isNowPlayingOpen && vm.currentTrack != null) {
            val cur = vm.currentTrack!!
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Brush.verticalGradient(listOf(if (vm.isSkyrockMode) Color(0xFF0A385C) else Color(0xFF28323B), bg)))
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { vm.isNowPlayingOpen = false }) { Icon(Icons.Default.KeyboardArrowDown, contentDescription = null, tint = Color.White) }
                    Spacer(Modifier.weight(1f))
                    Text("LECTURE EN COURS", color = Color(0xFFB3B3B3), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { vm.trackOptionsTarget = cur }) { Icon(Icons.Default.MoreHoriz, contentDescription = null, tint = Color.White) }
                }

                if (isTablet && widthDp >= 720) {
                    Spacer(Modifier.weight(1f))
                    Row(
                        modifier = Modifier.widthIn(max = 920.dp).fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(42.dp)
                    ) {
                        AsyncImage(
                            model = cur.coverUrl,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(320.dp).clip(RoundedCornerShape(10.dp)).background(Color(0xFF181818))
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(cur.title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Spacer(Modifier.height(4.dp))
                            Text(
                                cur.artistName,
                                color = Color(0xFFB3B3B3),
                                fontSize = 16.sp,
                                modifier = Modifier.clickable {
                                    cur.artistId?.let { aid -> vm.isNowPlayingOpen = false; vm.activeArtistId = Pair(aid, cur.artistName) }
                                }
                            )
                            if (vm.streamLabel.isNotEmpty()) {
                                Spacer(Modifier.height(4.dp))
                                Text(vm.streamLabel, color = Color.Gray, fontSize = 12.sp)
                            }
                            Spacer(Modifier.height(24.dp))
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                                IconButton(onClick = { }) { Icon(Icons.Default.SkipPrevious, contentDescription = null, tint = Color.White, modifier = Modifier.size(36.dp)) }
                                Box(
                                    modifier = Modifier.size(68.dp).clip(CircleShape).background(Color.White).clickable { vm.togglePlayPause() },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(if (vm.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null, tint = Color.Black, modifier = Modifier.size(34.dp))
                                }
                                IconButton(onClick = { }) { Icon(Icons.Default.SkipNext, contentDescription = null, tint = Color.White, modifier = Modifier.size(36.dp)) }
                            }
                            Spacer(Modifier.height(22.dp))
                            Button(
                                onClick = { vm.toggleSkyrock() },
                                colors = ButtonDefaults.buttonColors(containerColor = if (vm.isSkyrockMode) Color(0xFF009EF5) else Color(0xFF282828)),
                                shape = CircleShape
                            ) {
                                Icon(Icons.Default.Radio, contentDescription = null, tint = Color.White)
                                Spacer(Modifier.width(8.dp))
                                Text(if (vm.isSkyrockMode) "Version Skyrock (1.025x) ON" else "Version Skyrock", color = Color.White, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                } else {
                    Spacer(Modifier.weight(1f))
                    AsyncImage(
                        model = cur.coverUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(300.dp).clip(RoundedCornerShape(8.dp)).background(Color(0xFF181818))
                    )
                    Spacer(Modifier.weight(1f))
                    Column(modifier = Modifier.fillMaxWidth().widthIn(max = 520.dp)) {
                        Text(cur.title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            cur.artistName,
                            color = Color(0xFFB3B3B3),
                            fontSize = 15.sp,
                            modifier = Modifier.clickable {
                                cur.artistId?.let { aid -> vm.isNowPlayingOpen = false; vm.activeArtistId = Pair(aid, cur.artistName) }
                            }
                        )
                        if (vm.streamLabel.isNotEmpty()) {
                            Text(vm.streamLabel, color = Color.Gray, fontSize = 11.sp)
                        }
                        Spacer(Modifier.height(18.dp))
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { }) { Icon(Icons.Default.SkipPrevious, contentDescription = null, tint = Color.White, modifier = Modifier.size(34.dp)) }
                            Box(
                                modifier = Modifier.size(64.dp).clip(CircleShape).background(Color.White).clickable { vm.togglePlayPause() },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(if (vm.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null, tint = Color.Black, modifier = Modifier.size(32.dp))
                            }
                            IconButton(onClick = { }) { Icon(Icons.Default.SkipNext, contentDescription = null, tint = Color.White, modifier = Modifier.size(34.dp)) }
                        }
                        Spacer(Modifier.height(16.dp))
                        Button(
                            onClick = { vm.toggleSkyrock() },
                            colors = ButtonDefaults.buttonColors(containerColor = if (vm.isSkyrockMode) Color(0xFF009EF5) else Color(0xFF282828)),
                            shape = CircleShape
                        ) {
                            Icon(Icons.Default.Radio, contentDescription = null, tint = Color.White)
                            Spacer(Modifier.width(8.dp))
                            Text(if (vm.isSkyrockMode) "Version Skyrock (1.025x) ON" else "Version Skyrock", color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }

        // Track Options Modal
        if (vm.trackOptionsTarget != null) {
            val t = vm.trackOptionsTarget!!
            AlertDialog(
                onDismissRequest = { vm.trackOptionsTarget = null },
                containerColor = Color(0xFF181818),
                title = { Text(t.title, color = Color.White) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Liker", color = Color.White, modifier = Modifier.fillMaxWidth().clickable {
                            vm.likedTracks = if (vm.likedTracks.any { it.id == t.id }) vm.likedTracks.filterNot { it.id == t.id } else listOf(t) + vm.likedTracks
                            vm.trackOptionsTarget = null
                        }.padding(vertical = 6.dp))
                        t.artistId?.let { aid ->
                            Text("Voir l'artiste (${t.artistName})", color = Color.White, modifier = Modifier.fillMaxWidth().clickable {
                                vm.trackOptionsTarget = null; vm.isNowPlayingOpen = false; vm.activeArtistId = Pair(aid, t.artistName)
                            }.padding(vertical = 6.dp))
                        }
                        t.albumId?.let { alId ->
                            Text("Voir l'album (${t.albumTitle})", color = Color.White, modifier = Modifier.fillMaxWidth().clickable {
                                vm.trackOptionsTarget = null; vm.isNowPlayingOpen = false; vm.activeAlbumId = Pair(alId, t.albumTitle)
                            }.padding(vertical = 6.dp))
                        }
                    }
                },
                confirmButton = { TextButton(onClick = { vm.trackOptionsTarget = null }) { Text("Fermer", color = Color(0xFF1ED760)) } }
            )
        }
    }
}

@Composable
private fun SPTrackRow(t: SPTrack, queue: List<SPTrack>, vm: SpotifyViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable { vm.playTrack(t, queue) },
        verticalAlignment = Alignment.CenterVertically
    ) {
        AsyncImage(model = t.coverUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(48.dp).clip(RoundedCornerShape(4.dp)).background(Color(0xFF282828)))
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(t.title, color = if (vm.currentTrack?.id == t.id) Color(0xFF1ED760) else Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(t.artistName, color = Color(0xFFB3B3B3), fontSize = 13.sp, maxLines = 1)
        }
        IconButton(onClick = { vm.trackOptionsTarget = t }) {
            Icon(Icons.Default.MoreVert, contentDescription = null, tint = Color(0xFFB3B3B3))
        }
    }
}

@Composable
private fun SPHomeContent(vm: SpotifyViewModel, isTablet: Boolean) {
    val data = vm.homeData
    LazyColumn(modifier = Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Text("Écoutés récemment", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(16.dp))
        }
        if (data != null) {
            item {
                Text("Titres du moment", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(data.topTracks) { t ->
                        Column(modifier = Modifier.width(if (isTablet) 168.dp else 140.dp).clickable { vm.playTrack(t, data.topTracks) }) {
                            AsyncImage(model = t.coverUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(if (isTablet) 168.dp else 140.dp).clip(RoundedCornerShape(4.dp)))
                            Spacer(Modifier.height(6.dp))
                            Text(t.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(t.artistName, color = Color(0xFFB3B3B3), fontSize = 12.sp, maxLines = 1)
                        }
                    }
                }
            }
            item { SPCollectionRow("Playlists", data.playlists, isTablet) { vm.activeCollection = it } }
            item { SPCollectionRow("Albums populaires", data.albums, isTablet) { vm.activeAlbumId = Pair(it.id, it.title) } }
            item { SPCollectionRow("Podcasts populaires", data.podcasts, isTablet) { vm.activeCollection = it } }
        }
    }
}

@Composable
private fun SPCollectionRow(title: String, items: List<SPCollection>, isTablet: Boolean, onClick: (SPCollection) -> Unit) {
    Column(modifier = Modifier.padding(top = 18.dp)) {
        Text(title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(items) { c ->
                Column(modifier = Modifier.width(if (isTablet) 168.dp else 140.dp).clickable { onClick(c) }) {
                    AsyncImage(model = c.coverUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(if (isTablet) 168.dp else 140.dp).clip(RoundedCornerShape(4.dp)))
                    Spacer(Modifier.height(6.dp))
                    Text(c.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(c.subtitle, color = Color(0xFFB3B3B3), fontSize = 12.sp, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun SPSearchContent(vm: SpotifyViewModel, cols: Int) {
    Column(modifier = Modifier.fillMaxSize().statusBarsPadding().padding(16.dp)) {
        Text("Rechercher", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = vm.searchQuery,
            onValueChange = { vm.performSearch(it) },
            placeholder = { Text("Artistes, titres, albums, podcasts...", color = Color.Gray) },
            singleLine = true,
            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White),
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(14.dp))
        val sd = vm.searchData
        if (sd != null) {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(sd.tracks) { t -> SPTrackRow(t, sd.tracks, vm) }
            }
        }
    }
}

@Composable
private fun SPLibraryContent(vm: SpotifyViewModel) {
    Column(modifier = Modifier.fillMaxSize().statusBarsPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Bibliothèque", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Row(
            modifier = Modifier.fillMaxWidth().clickable {
                vm.activeCollection = SPCollection("liked", SPCollectionKind.PLAYLIST, "Titres likés", tracks = vm.likedTracks, isUserCreated = true)
            },
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(modifier = Modifier.size(60.dp).clip(RoundedCornerShape(4.dp)).background(Color(0xFF472AE8)), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Favorite, contentDescription = null, tint = Color.White)
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text("Titres likés", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text("${vm.likedTracks.size} titres", color = Color(0xFFB3B3B3), fontSize = 13.sp)
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().clickable {
                vm.activeCollection = SPCollection("offline_downloads", SPCollectionKind.PLAYLIST, "Titres téléchargés", tracks = vm.downloadedTracks, isUserCreated = true)
            },
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(modifier = Modifier.size(60.dp).clip(RoundedCornerShape(4.dp)).background(Color(0xFF146B3D)), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.DownloadForOffline, contentDescription = null, tint = Color(0xFF1ED760))
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text("Titres téléchargés & importés", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text("${vm.downloadedTracks.size} fichiers", color = Color(0xFFB3B3B3), fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun SPSettingsContent(vm: SpotifyViewModel, context: android.content.Context) {
    val scope = rememberCoroutineScope()
    Column(modifier = Modifier.fillMaxSize().statusBarsPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Réglages & OpenDeezer ARL", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        OutlinedTextField(
            value = vm.arlDraft,
            onValueChange = { vm.arlDraft = it },
            label = { Text("Cookie ARL Deezer", color = Color.Gray) },
            singleLine = true,
            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White),
            modifier = Modifier.fillMaxWidth()
        )
        Button(
            onClick = {
                SpotifyEngine.setARL(context, vm.arlDraft)
                scope.launch {
                    val (ok, name) = SpotifyEngine.validateARL()
                    vm.arlStatus = if (ok) "Connecté ($name)" else "ARL invalide ou expiré"
                }
            },
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1ED760))
        ) { Text("Enregistrer & Tester l'ARL", color = Color.Black, fontWeight = FontWeight.Bold) }
        if (vm.arlStatus.isNotEmpty()) {
            Text(vm.arlStatus, color = if (vm.arlStatus.contains("Connecté")) Color(0xFF1ED760) else Color(0xFFFF9800))
        }
    }
}
