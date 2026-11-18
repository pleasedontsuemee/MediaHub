package com.mediahub.youtube

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import coil.compose.AsyncImage
import com.mediahub.core.*
import kotlinx.coroutines.launch

enum class YTTab(val label: String) {
    HOME("Accueil"),
    SHORTS("Shorts"),
    SUBS("Abonnements"),
    LIBRARY("Vous")
}

class YouTubeViewModel(app: Application) : AndroidViewModel(app) {
    val player: ExoPlayer = ExoPlayer.Builder(app).build()

    var selectedTab by mutableStateOf(YTTab.HOME)
    var selectedChip by mutableStateOf("Tout")
    var searchQuery by mutableStateOf("")
    var isSearchOpen by mutableStateOf(false)
    var videos by mutableStateOf<List<YTVideo>>(emptyList())
    var shorts by mutableStateOf<List<YTVideo>>(emptyList())
    var isLoading by mutableStateOf(true)
    var currentVideo by mutableStateOf<YTVideo?>(null)
    var isPlayerFullscreen by mutableStateOf(false)
    var isPlaying by mutableStateOf(false)
    var likedIds by mutableStateOf<Set<String>>(emptySet())
    var subscribedChannels by mutableStateOf<Set<String>>(emptySet())
    var availableQualities by mutableStateOf<List<Int>>(emptyList())
    var selectedQualityHeight by mutableStateOf<Int?>(null)
    var activeQualityHeight by mutableStateOf<Int?>(null)

    private var currentStreamInfo: YTStreamInfo? = null
    private var isUsingHls: Boolean = false

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlayingNow: Boolean) {
            isPlaying = isPlayingNow
        }

        override fun onTracksChanged(tracks: Tracks) {
            if (!isUsingHls) return
            val heights = mutableSetOf<Int>()
            var activeH: Int? = null
            for (group in tracks.groups) {
                if (group.type != C.TRACK_TYPE_VIDEO) continue
                for (i in 0 until group.length) {
                    val h = group.getTrackFormat(i).height
                    if (h > 0 && group.isTrackSupported(i)) {
                        heights.add(h)
                    }
                    if (group.isTrackSelected(i) && h > 0) {
                        activeH = h
                    }
                }
            }
            if (heights.isEmpty()) {
                for (group in tracks.groups) {
                    if (group.type != C.TRACK_TYPE_VIDEO) continue
                    for (i in 0 until group.length) {
                        val h = group.getTrackFormat(i).height
                        if (h > 0) heights.add(h)
                    }
                }
            }
            if (heights.isNotEmpty()) {
                availableQualities = heights.sortedDescending()
            }
            activeQualityHeight = activeH
            val target = selectedQualityHeight
            if (target != null && needsQualityOverrideReapply(tracks, target)) {
                applyHlsQuality(target)
            }
        }
    }

    init {
        player.addListener(playerListener)
        loadFeed("trending france")
        loadShorts()
    }

    fun loadFeed(query: String) {
        viewModelScope.launch {
            isLoading = true
            videos = YouTubeEngine.fetchFeed(query)
            isLoading = false
        }
    }

    private fun loadShorts() {
        viewModelScope.launch {
            shorts = YouTubeEngine.fetchFeed("shorts france viral")
        }
    }

    fun playVideo(video: YTVideo) {
        currentVideo = video
        isPlayerFullscreen = true
        availableQualities = emptyList()
        activeQualityHeight = null
        currentStreamInfo = null
        isUsingHls = false
        viewModelScope.launch {
            val info = YouTubeEngine.resolveStreamInfo(video.id) ?: return@launch
            currentStreamInfo = info
            if (info.hlsUrl != null) {
                isUsingHls = true
                applyHlsQuality(selectedQualityHeight)
                player.setMediaItem(MediaItem.fromUri(info.hlsUrl))
                player.prepare()
                player.play()
                isPlaying = true
            } else if (info.progressiveFormats.isNotEmpty()) {
                isUsingHls = false
                availableQualities = info.progressiveFormats.map { it.height }.distinct().sortedDescending()
                val chosen = pickProgressiveFormat(info.progressiveFormats, selectedQualityHeight)
                if (chosen != null) {
                    activeQualityHeight = chosen.height
                    player.setMediaItem(MediaItem.fromUri(chosen.url))
                    player.prepare()
                    player.play()
                    isPlaying = true
                }
            }
        }
    }

    fun selectQuality(height: Int?) {
        selectedQualityHeight = height
        if (isUsingHls) {
            applyHlsQuality(height)
            return
        }
        val formats = currentStreamInfo?.progressiveFormats ?: return
        val chosen = pickProgressiveFormat(formats, height) ?: return
        val currentUri = player.currentMediaItem?.localConfiguration?.uri?.toString()
        if (currentUri != chosen.url) {
            val pos = player.currentPosition.coerceAtLeast(0L)
            val shouldPlay = player.playWhenReady
            player.setMediaItem(MediaItem.fromUri(chosen.url))
            player.prepare()
            if (pos > 0L) player.seekTo(pos)
            player.playWhenReady = shouldPlay
        }
        activeQualityHeight = chosen.height
    }

    private fun pickProgressiveFormat(formats: List<YTFormat>, targetHeight: Int?): YTFormat? {
        if (formats.isEmpty()) return null
        if (targetHeight == null) return formats.first()
        return formats.firstOrNull { it.height == targetHeight }
            ?: formats.minByOrNull { kotlin.math.abs(it.height - targetHeight) }
    }

    private fun needsQualityOverrideReapply(tracks: Tracks, targetHeight: Int): Boolean {
        val currentOverrides = player.trackSelectionParameters.overrides
        var hasVideoGroup = false
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            hasVideoGroup = true
            val existing = currentOverrides[group.mediaTrackGroup] ?: return true
            val valid = existing.trackIndices.isNotEmpty() && existing.trackIndices.all { idx ->
                idx < group.length && group.getTrackFormat(idx).height == targetHeight
            }
            if (!valid) return true
        }
        return !hasVideoGroup
    }

    private fun applyHlsQuality(targetHeight: Int?) {
        val builder = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
            .clearVideoSizeConstraints()
            .setMaxVideoBitrate(Int.MAX_VALUE)

        if (targetHeight != null) {
            var appliedOverride = false
            for (group in player.currentTracks.groups) {
                if (group.type != C.TRACK_TYPE_VIDEO) continue
                val supportedIndices = (0 until group.length).filter { idx ->
                    group.getTrackFormat(idx).height == targetHeight && group.isTrackSupported(idx)
                }
                val indices = supportedIndices.ifEmpty {
                    (0 until group.length).filter { idx ->
                        group.getTrackFormat(idx).height == targetHeight
                    }
                }
                if (indices.isNotEmpty()) {
                    builder.addOverride(TrackSelectionOverride(group.mediaTrackGroup, indices))
                    appliedOverride = true
                }
            }
            if (!appliedOverride) {
                builder.setMaxVideoSize(Int.MAX_VALUE, targetHeight)
                builder.setMinVideoSize(0, targetHeight)
            }
        }
        player.trackSelectionParameters = builder.build()
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

    override fun onCleared() {
        player.removeListener(playerListener)
        player.release()
    }
}

@Composable
fun YouTubeAppScreen(vm: YouTubeViewModel = viewModel()) {
    val isTablet = rememberIsTablet()
    val widthDp = LocalConfiguration.current.screenWidthDp
    val cols = if (widthDp >= 900) 3 else if (widthDp >= 600) 2 else 1
    val bg = Color(0xFF0F0F0F)
    val chips = listOf("Tout", "Musique", "Gaming", "Rap FR", "En direct", "Podcasts")

    Box(modifier = Modifier.fillMaxSize().background(bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top Bar
            Row(
                modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (vm.isSearchOpen) {
                    OutlinedTextField(
                        value = vm.searchQuery,
                        onValueChange = { vm.searchQuery = it },
                        placeholder = { Text("Rechercher sur YouTube", color = Color.Gray) },
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = Color.Red,
                            unfocusedBorderColor = Color(0xFF333333)
                        ),
                        modifier = Modifier.weight(1f).widthIn(max = 560.dp)
                    )
                    IconButton(onClick = { vm.loadFeed(vm.searchQuery.ifBlank { "trending france" }) }) {
                        Icon(Icons.Default.Search, contentDescription = "Go", tint = Color.White)
                    }
                    IconButton(onClick = { vm.isSearchOpen = false }) {
                        Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
                    }
                } else {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFFFF0000))
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                    }
                    Spacer(Modifier.width(8.dp))
                    Text("YouTube", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { vm.isSearchOpen = true }) {
                        Icon(Icons.Default.Search, contentDescription = "Search", tint = Color.White)
                    }
                }
            }

            // Filter Chips
            if (vm.selectedTab == YTTab.HOME) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(chips) { chip ->
                        val sel = vm.selectedChip == chip
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) Color.White else Color(0xFF272727))
                                .clickable {
                                    vm.selectedChip = chip
                                    vm.loadFeed(if (chip == "Tout") "trending france" else "$chip france")
                                }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(chip, color = if (sel) Color.Black else Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }

            // Scalable Grid (1 col on Phone, 2-3 cols on Tablet)
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                val displayList = if (vm.selectedTab == YTTab.SHORTS) vm.shorts else vm.videos
                if (vm.isLoading && displayList.isEmpty()) {
                    CircularProgressIndicator(color = Color.Red, modifier = Modifier.align(Alignment.Center))
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(cols),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(displayList, key = { it.id }) { v ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { vm.playVideo(v) }
                            ) {
                                Box(modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(Color(0xFF222222))) {
                                    AsyncImage(
                                        model = v.thumbnailUrl,
                                        contentDescription = v.title,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier.fillMaxSize()
                                    )
                                    if (v.durationText.isNotEmpty()) {
                                        Text(
                                            v.durationText,
                                            color = Color.White,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            modifier = Modifier
                                                .align(Alignment.BottomEnd)
                                                .padding(6.dp)
                                                .background(Color.Black.copy(alpha = 0.8f), RoundedCornerShape(4.dp))
                                                .padding(horizontal = 5.dp, vertical = 2.dp)
                                        )
                                    }
                                }
                                Spacer(Modifier.height(10.dp))
                                Row(verticalAlignment = Alignment.Top) {
                                    Box(
                                        modifier = Modifier.size(36.dp).clip(CircleShape).background(Color(0xFF333333)),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(v.channelTitle.take(1).uppercase(), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                    }
                                    Spacer(Modifier.width(10.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(v.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                        Spacer(Modifier.height(2.dp))
                                        Text("${v.channelTitle} ${if (v.viewCountText.isNotEmpty()) "• ${v.viewCountText}" else ""}", color = Color(0xFFAAAAAA), fontSize = 12.sp, maxLines = 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Mini Player Bar
            if (vm.currentVideo != null && !vm.isPlayerFullscreen) {
                val cur = vm.currentVideo!!
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(58.dp)
                        .background(Color(0xFF212121))
                        .clickable { vm.isPlayerFullscreen = true }
                        .padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    AsyncImage(model = cur.thumbnailUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(64.dp, 40.dp).clip(RoundedCornerShape(4.dp)))
                    Spacer(Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(cur.title, color = Color.White, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(cur.channelTitle, color = Color(0xFFAAAAAA), fontSize = 11.sp, maxLines = 1)
                    }
                    IconButton(onClick = { vm.togglePlayPause() }) {
                        Icon(if (vm.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null, tint = Color.White)
                    }
                    IconButton(onClick = { vm.player.stop(); vm.currentVideo = null }) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                    }
                }
            }

            // Bottom Tab Bar (Always at bottom on Phone & Tablet)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF0F0F0F))
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
                    YTTab.entries.forEach { tab ->
                        val selected = vm.selectedTab == tab
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .adaptiveHomeTabGesture(isHome = tab == YTTab.HOME) {
                                    vm.selectedTab = tab
                                },
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                imageVector = when (tab) {
                                    YTTab.HOME -> Icons.Default.Home
                                    YTTab.SHORTS -> Icons.Default.Bolt
                                    YTTab.SUBS -> Icons.Default.Subscriptions
                                    YTTab.LIBRARY -> Icons.Default.VideoLibrary
                                },
                                contentDescription = tab.label,
                                tint = if (selected) Color.White else Color(0xFFAAAAAA),
                                modifier = Modifier.size(22.dp)
                            )
                            Text(tab.label, fontSize = 10.sp, color = if (selected) Color.White else Color(0xFFAAAAAA))
                        }
                    }
                }
            }
        }

        // Fullscreen / 2-Pane Watch Player Overlay
        if (vm.isPlayerFullscreen && vm.currentVideo != null) {
            val cur = vm.currentVideo!!
            if (isTablet && widthDp >= 800) {
                // Tablet Widescreen 2-Pane Watch Layout
                Row(modifier = Modifier.fillMaxSize().background(Color.Black).statusBarsPadding().navigationBarsPadding().padding(16.dp)) {
                    Column(modifier = Modifier.weight(0.65f).fillMaxHeight()) {
                        YouTubePlayerBox(
                            vm = vm,
                            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(Color.Black)
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(cur.title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("${cur.channelTitle} • ${cur.viewCountText}", color = Color(0xFFAAAAAA), fontSize = 14.sp, modifier = Modifier.weight(1f))
                            val liked = vm.likedIds.contains(cur.id)
                            Button(onClick = { vm.likedIds = if (liked) vm.likedIds - cur.id else vm.likedIds + cur.id }, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF272727))) {
                                Icon(if (liked) Icons.Default.ThumbUp else Icons.Default.ThumbUpOffAlt, contentDescription = null, tint = Color.White)
                                Spacer(Modifier.width(6.dp))
                                Text(if (liked) "Aimé" else "J'aime", color = Color.White)
                            }
                            val subbed = vm.subscribedChannels.contains(cur.channelTitle)
                            Button(onClick = { vm.subscribedChannels = if (subbed) vm.subscribedChannels - cur.channelTitle else vm.subscribedChannels + cur.channelTitle }, colors = ButtonDefaults.buttonColors(containerColor = if (subbed) Color(0xFF272727) else Color.White)) {
                                Text(if (subbed) "Abonné" else "S'abonner", color = if (subbed) Color.White else Color.Black, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    LazyColumn(modifier = Modifier.weight(0.35f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        item { Text("À suivre", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                        items(vm.videos.filter { it.id != cur.id }) { nextV ->
                            Row(modifier = Modifier.fillMaxWidth().clickable { vm.playVideo(nextV) }) {
                                AsyncImage(model = nextV.thumbnailUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(130.dp, 74.dp).clip(RoundedCornerShape(6.dp)))
                                Spacer(Modifier.width(10.dp))
                                Column {
                                    Text(nextV.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    Text(nextV.channelTitle, color = Color(0xFFAAAAAA), fontSize = 11.sp, maxLines = 1)
                                }
                            }
                        }
                    }
                }
            } else {
                // Phone Portrait Watch Layout
                Column(modifier = Modifier.fillMaxSize().background(Color.Black).statusBarsPadding()) {
                    YouTubePlayerBox(
                        vm = vm,
                        modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Color.Black)
                    )
                    Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                        Text(cur.title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(6.dp))
                        Text("${cur.channelTitle} • ${cur.viewCountText}", color = Color(0xFFAAAAAA), fontSize = 13.sp)
                        Spacer(Modifier.height(14.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            val liked = vm.likedIds.contains(cur.id)
                            Button(onClick = { vm.likedIds = if (liked) vm.likedIds - cur.id else vm.likedIds + cur.id }, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF272727))) {
                                Icon(if (liked) Icons.Default.ThumbUp else Icons.Default.ThumbUpOffAlt, contentDescription = null, tint = Color.White)
                                Spacer(Modifier.width(6.dp))
                                Text(if (liked) "Aimé" else "J'aime", color = Color.White)
                            }
                            val subbed = vm.subscribedChannels.contains(cur.channelTitle)
                            Button(onClick = { vm.subscribedChannels = if (subbed) vm.subscribedChannels - cur.channelTitle else vm.subscribedChannels + cur.channelTitle }, colors = ButtonDefaults.buttonColors(containerColor = if (subbed) Color(0xFF272727) else Color.White)) {
                                Text(if (subbed) "Abonné" else "S'abonner", color = if (subbed) Color.White else Color.Black, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun YouTubePlayerBox(
    vm: YouTubeViewModel,
    modifier: Modifier = Modifier
) {
    var qualityMenuExpanded by remember { mutableStateOf(false) }
    val qualityLabel = vm.selectedQualityHeight?.let { "${it}p" }
        ?: vm.activeQualityHeight?.let { "Auto (${it}p)" }
        ?: "Auto"

    Box(modifier = modifier) {
        ExoVideoSurface(player = vm.player)
        IconButton(
            onClick = { vm.isPlayerFullscreen = false },
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(8.dp)
                .background(Color.Black.copy(alpha = 0.6f), CircleShape)
        ) {
            Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Minimize", tint = Color.White)
        }
        Row(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = { vm.togglePlayPause() },
                modifier = Modifier.background(Color.Black.copy(alpha = 0.6f), CircleShape)
            ) {
                Icon(
                    if (vm.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (vm.isPlaying) "Pause" else "Play",
                    tint = Color.White
                )
            }
            Box {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color.Black.copy(alpha = 0.65f))
                        .clickable { qualityMenuExpanded = true }
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp)
                ) {
                    Icon(
                        Icons.Default.Settings,
                        contentDescription = "Qualité",
                        tint = Color.White,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        qualityLabel,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                DropdownMenu(
                    expanded = qualityMenuExpanded,
                    onDismissRequest = { qualityMenuExpanded = false },
                    modifier = Modifier.background(Color(0xFF212121))
                ) {
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = vm.activeQualityHeight?.takeIf { vm.selectedQualityHeight == null }
                                    ?.let { "Auto (${it}p)" } ?: "Auto",
                                color = Color.White,
                                fontWeight = if (vm.selectedQualityHeight == null) FontWeight.Bold else FontWeight.Normal
                            )
                        },
                        trailingIcon = {
                            if (vm.selectedQualityHeight == null) {
                                Icon(Icons.Default.Check, contentDescription = null, tint = Color.Red)
                            }
                        },
                        onClick = {
                            vm.selectQuality(null)
                            qualityMenuExpanded = false
                        }
                    )
                    vm.availableQualities.forEach { height ->
                        val isSelected = vm.selectedQualityHeight == height
                        DropdownMenuItem(
                            text = {
                                Text(
                                    text = "${height}p",
                                    color = Color.White,
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                                )
                            },
                            trailingIcon = {
                                if (isSelected) {
                                    Icon(Icons.Default.Check, contentDescription = null, tint = Color.Red)
                                }
                            },
                            onClick = {
                                vm.selectQuality(height)
                                qualityMenuExpanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}
