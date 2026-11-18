package com.mediahub.netflix

import android.app.Application
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Image
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import coil.compose.AsyncImage
import com.mediahub.core.*
import kotlinx.coroutines.launch

enum class NFTab(val label: String) {
    HOME("Accueil"),
    SEARCH("Rechercher"),
    MY_LIST("Ma liste")
}

class NetflixViewModel(app: Application) : AndroidViewModel(app) {
    val player: ExoPlayer = ExoPlayer.Builder(app).build()

    var selectedTab by mutableStateOf(NFTab.HOME)
    var homeFilter by mutableStateOf("All")
    var hero by mutableStateOf<NFMedia?>(null)
    var rows by mutableStateOf<List<Pair<String, List<NFMedia>>>>(emptyList())
    var searchQuery by mutableStateOf("")
    var searchResults by mutableStateOf<List<NFMedia>>(emptyList())
    var myList by mutableStateOf<List<NFMedia>>(emptyList())
    var selectedDetail by mutableStateOf<NFMedia?>(null)
    var episodes by mutableStateOf<List<NFEpisode>>(emptyList())

    var isPlayerPresented by mutableStateOf(false)
    var playingMedia by mutableStateOf<NFMedia?>(null)
    var sources by mutableStateOf<List<NFStreamSource>>(emptyList())
    var activeSource by mutableStateOf<NFStreamSource?>(null)
    var isBuffering by mutableStateOf(false)
    var showSettings by mutableStateOf(false)
    var movixUrlDraft by mutableStateOf("")

    init {
        NetflixEngine.init(app)
        movixUrlDraft = NetflixEngine.getMovixBase()
        loadHome("All")
    }

    fun loadHome(filter: String) {
        homeFilter = filter
        viewModelScope.launch {
            val (h, r) = NetflixEngine.fetchHomeFeed(filter)
            hero = h
            rows = r
        }
    }

    fun search(q: String) {
        searchQuery = q
        if (q.isBlank()) { searchResults = emptyList(); return }
        viewModelScope.launch {
            searchResults = NetflixEngine.search(q)
        }
    }

    fun openDetail(m: NFMedia) {
        selectedDetail = m
        episodes = emptyList()
        if (m.mediaType == "tv") {
            viewModelScope.launch {
                episodes = NetflixEngine.fetchEpisodes(m.id, 1)
            }
        }
    }

    fun playMedia(m: NFMedia, season: Int = 1, episode: Int = 1) {
        selectedDetail = null
        playingMedia = m
        isPlayerPresented = true
        isBuffering = true
        sources = emptyList()
        activeSource = null

        viewModelScope.launch {
            val list = NetflixEngine.resolveMovixStreams(m, season, episode)
            sources = list
            val first = list.firstOrNull()
            if (first == null) {
                isBuffering = false
                return@launch
            }
            activateSource(first)
        }
    }

    fun switchSource(src: NFStreamSource) {
        isBuffering = true
        viewModelScope.launch { activateSource(src) }
    }

    private suspend fun activateSource(src: NFStreamSource) {
        val resolved = if (src.isEmbed) NetflixEngine.extractDirectStream(src) ?: src else src
        activeSource = resolved
        if (resolved.isEmbed) {
            player.stop()
            isBuffering = false
        } else {
            player.setMediaItem(MediaItem.fromUri(resolved.url))
            player.prepare()
            player.play()
            isBuffering = false
        }
    }

    fun closePlayer() {
        player.stop()
        isPlayerPresented = false
    }

    override fun onCleared() {
        player.release()
    }
}

@Composable
fun NetflixAppScreen(vm: NetflixViewModel = viewModel()) {
    val isTablet = rememberIsTablet()
    val widthDp = LocalConfiguration.current.screenWidthDp
    val gridCols = if (widthDp >= 900) 6 else if (widthDp >= 600) 4 else 3
    val context = LocalContext.current

    LaunchedEffect(vm.isPlayerPresented) {
        if (!isTablet) {
            context.setLandscapeMode(vm.isPlayerPresented)
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when (vm.selectedTab) {
                    NFTab.HOME -> NFHomeContent(vm, isTablet, widthDp)
                    NFTab.SEARCH -> NFSearchContent(vm, gridCols)
                    NFTab.MY_LIST -> NFMyListContent(vm, gridCols)
                }
            }

            // Bottom Tab Bar (Always at bottom on Phone & Tablet)
            if (!vm.isPlayerPresented) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF121212))
                        .navigationBarsPadding(),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        modifier = Modifier
                            .widthIn(max = if (isTablet) 600.dp else 1000.dp)
                            .fillMaxWidth()
                            .height(52.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        NFTab.entries.forEach { tab ->
                            val sel = vm.selectedTab == tab
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .adaptiveHomeTabGesture(isHome = tab == NFTab.HOME) { vm.selectedTab = tab },
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Icon(
                                    imageVector = when (tab) {
                                        NFTab.HOME -> Icons.Default.Home
                                        NFTab.SEARCH -> Icons.Default.Search
                                        NFTab.MY_LIST -> Icons.Default.Bookmark
                                    },
                                    contentDescription = tab.label,
                                    tint = if (sel) Color.White else Color(0xFF8C8C8C),
                                    modifier = Modifier.size(22.dp)
                                )
                                Text(tab.label, fontSize = 10.sp, color = if (sel) Color.White else Color(0xFF8C8C8C))
                            }
                        }
                    }
                }
            }
        }

        // Detail Modal (Centered card on Tablet, full on Phone)
        if (vm.selectedDetail != null) {
            val m = vm.selectedDetail!!
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.85f)).statusBarsPadding().navigationBarsPadding(),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .widthIn(max = if (isTablet) 780.dp else 1000.dp)
                        .fillMaxHeight(if (isTablet) 0.92f else 1f)
                        .clip(RoundedCornerShape(if (isTablet) 14.dp else 0.dp))
                        .background(Color(0xFF141414))
                ) {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        item {
                            Box(modifier = Modifier.fillMaxWidth().height(if (isTablet) 340.dp else 230.dp)) {
                                AsyncImage(model = m.backdropUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                Box(
                                    modifier = Modifier.fillMaxWidth().height(120.dp).align(Alignment.BottomCenter)
                                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xFF141414))))
                                )
                                IconButton(
                                    onClick = { vm.selectedDetail = null },
                                    modifier = Modifier.align(Alignment.TopEnd).padding(12.dp).background(Color.Black.copy(alpha = 0.7f), CircleShape)
                                ) { Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White) }
                            }
                            Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                                Text(m.title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
                                Spacer(Modifier.height(6.dp))
                                Text(m.releaseYear, color = Color(0xFFB3B3B3), fontSize = 13.sp)
                                Spacer(Modifier.height(14.dp))
                                Button(
                                    onClick = { vm.playMedia(m) },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                                    shape = RoundedCornerShape(4.dp),
                                    modifier = Modifier.fillMaxWidth().height(42.dp)
                                ) {
                                    Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color.Black)
                                    Spacer(Modifier.width(6.dp))
                                    Text("Lecture", color = Color.Black, fontWeight = FontWeight.Bold)
                                }
                                Spacer(Modifier.height(12.dp))
                                Text(m.overview, color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp, lineHeight = 20.sp)
                                Spacer(Modifier.height(14.dp))
                                val inList = vm.myList.any { it.id == m.id }
                                OutlinedButton(onClick = {
                                    vm.myList = if (inList) vm.myList.filterNot { it.id == m.id } else listOf(m) + vm.myList
                                }) {
                                    Icon(if (inList) Icons.Default.Check else Icons.Default.Add, contentDescription = null, tint = Color.White)
                                    Spacer(Modifier.width(6.dp))
                                    Text(if (inList) "Dans Ma liste" else "Ma liste", color = Color.White)
                                }
                            }
                        }
                        items(vm.episodes) { ep ->
                            Row(
                                modifier = Modifier.fillMaxWidth().clickable { vm.playMedia(m, ep.season, ep.episode) }.padding(horizontal = 20.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                AsyncImage(model = ep.stillUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(132.dp, 74.dp).clip(RoundedCornerShape(4.dp)).background(Color(0xFF222222)))
                                Spacer(Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("${ep.episode}. ${ep.name}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                    Text(ep.overview, color = Color(0xFFB3B3B3), fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fullscreen Player Overlay
        if (vm.isPlayerPresented) {
            var showSources by remember { mutableStateOf(false) }
            Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
                val src = vm.activeSource
                if (src != null && src.isEmbed) {
                    AndroidView(
                        factory = { ctx ->
                            WebView(ctx).apply {
                                settings.javaScriptEnabled = true
                                settings.mediaPlaybackRequiresUserGesture = false
                                webChromeClient = WebChromeClient()
                                webViewClient = WebViewClient()
                                loadUrl(src.url, mapOf("Referer" to "https://movix.miami/"))
                            }
                        },
                        update = { wv ->
                            if (wv.url != src.url) wv.loadUrl(src.url, mapOf("Referer" to "https://movix.miami/"))
                        },
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    ExoVideoSurface(player = vm.player)
                }

                if (vm.isBuffering) {
                    CircularProgressIndicator(color = Color(0xFFE50914), modifier = Modifier.align(Alignment.Center))
                }

                Row(
                    modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 24.dp, vertical = 14.dp).align(Alignment.TopCenter),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = { vm.closePlayer() },
                        modifier = Modifier.background(Color.Black.copy(alpha = 0.65f), CircleShape)
                    ) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White) }
                    Spacer(Modifier.width(12.dp))
                    Text(vm.playingMedia?.title ?: "", color = Color.White, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1)
                    Button(
                        onClick = { showSources = true },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE50914))
                    ) {
                        Text("Serveurs (${vm.sources.size})", color = Color.White, fontSize = 12.sp)
                    }
                }

                if (showSources) {
                    AlertDialog(
                        onDismissRequest = { showSources = false },
                        containerColor = Color(0xFF181818),
                        title = { Text("Serveurs Movix (${vm.sources.size})", color = Color.White) },
                        text = {
                            LazyColumn(modifier = Modifier.heightIn(max = 320.dp)) {
                                items(vm.sources) { s ->
                                    Row(
                                        modifier = Modifier.fillMaxWidth().clickable { vm.switchSource(s); showSources = false }.padding(vertical = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text("${s.provider} • ${s.name}", color = Color.White, fontWeight = FontWeight.SemiBold)
                                            Text(if (s.isEmbed) "LECTEUR WEB • ${s.language}" else "DIRECT ${s.format.uppercase()}", color = if (s.isEmbed) Color.Gray else Color(0xFF1ED760), fontSize = 11.sp)
                                        }
                                        if (vm.activeSource?.url == s.url) Icon(Icons.Default.Check, contentDescription = null, tint = Color(0xFFE50914))
                                    }
                                }
                            }
                        },
                        confirmButton = {
                            TextButton(onClick = { showSources = false }) { Text("Fermer", color = Color(0xFFE50914)) }
                        }
                    )
                }
            }
        }

        // Movix URL Settings Dialog
        if (vm.showSettings) {
            AlertDialog(
                onDismissRequest = { vm.showSettings = false },
                containerColor = Color(0xFF181818),
                title = { Text("URL Movix & Réglages", color = Color.White) },
                text = {
                    OutlinedTextField(
                        value = vm.movixUrlDraft,
                        onValueChange = { vm.movixUrlDraft = it },
                        label = { Text("URL Movix", color = Color.Gray) },
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White)
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        vm.movixUrlDraft = NetflixEngine.setMovixBase(context, vm.movixUrlDraft)
                        vm.loadHome(vm.homeFilter)
                        vm.showSettings = false
                    }) { Text("Appliquer", color = Color(0xFFE50914)) }
                },
                dismissButton = {
                    TextButton(onClick = { vm.showSettings = false }) { Text("Fermer", color = Color.White) }
                }
            )
        }
    }
}

@Composable
private fun NFHomeContent(vm: NetflixViewModel, isTablet: Boolean, widthDp: Int) {
    val isLandscapeTablet = isTablet && widthDp >= 800
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        item {
            val hero = vm.hero
            Box(modifier = Modifier.fillMaxWidth().height(if (isLandscapeTablet) 460.dp else if (isTablet) 520.dp else 490.dp)) {
                if (hero != null) {
                    AsyncImage(
                        model = if (isLandscapeTablet) hero.backdropUrl else (hero.posterUrl ?: hero.backdropUrl),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                if (isLandscapeTablet) {
                    Box(
                        modifier = Modifier.fillMaxSize().background(
                            Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.85f), Color.Black.copy(alpha = 0.3f), Color.Transparent))
                        )
                    )
                }
                Box(
                    modifier = Modifier.fillMaxWidth().height(220.dp).align(Alignment.BottomCenter)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f), Color.Black)))
                )

                // Floating Top Bar (Real N Ribbon + Avatar)
                Column(modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(painter = painterResource(R.drawable.netflix_n_ribbon), contentDescription = "Netflix", modifier = Modifier.height(30.dp).clickable { vm.loadHome("All") })
                        if (isLandscapeTablet) {
                            Spacer(Modifier.width(32.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                                listOf("Séries" to "Series", "Films" to "Films", "Tout" to "All").forEach { (label, key) ->
                                    Text(
                                        label,
                                        color = Color.White,
                                        fontSize = 15.sp,
                                        fontWeight = if (vm.homeFilter == key) FontWeight.Bold else FontWeight.Medium,
                                        modifier = Modifier.clickable { vm.loadHome(key) }.padding(6.dp)
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        Image(
                            painter = painterResource(R.drawable.avatar_squid),
                            contentDescription = "Profil",
                            modifier = Modifier.size(28.dp).clip(RoundedCornerShape(4.dp)).clickable { vm.showSettings = true }
                        )
                    }
                    if (!isLandscapeTablet) {
                        Spacer(Modifier.height(10.dp))
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                            listOf("Séries" to "Series", "Films" to "Films", "Tout" to "All").forEach { (label, key) ->
                                Text(
                                    label,
                                    color = Color.White,
                                    fontSize = 15.sp,
                                    fontWeight = if (vm.homeFilter == key) FontWeight.Bold else FontWeight.Medium,
                                    modifier = Modifier.clickable { vm.loadHome(key) }.padding(6.dp)
                                )
                            }
                        }
                    }
                }

                // Hero Controls
                if (hero != null) {
                    if (isLandscapeTablet) {
                        Column(
                            modifier = Modifier.align(Alignment.BottomStart).padding(start = 28.dp, bottom = 28.dp).widthIn(max = 520.dp)
                        ) {
                            Text(hero.title.uppercase(), color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Black, maxLines = 2)
                            Spacer(Modifier.height(8.dp))
                            Text(hero.overview, color = Color.White.copy(alpha = 0.88f), fontSize = 13.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                            Spacer(Modifier.height(14.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Button(
                                    onClick = { vm.playMedia(hero) },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                                    shape = RoundedCornerShape(4.dp)
                                ) {
                                    Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color.Black)
                                    Spacer(Modifier.width(4.dp))
                                    Text("Lecture", color = Color.Black, fontWeight = FontWeight.Bold)
                                }
                                Button(
                                    onClick = { vm.openDetail(hero) },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333333).copy(alpha = 0.85f)),
                                    shape = RoundedCornerShape(4.dp)
                                ) {
                                    Icon(Icons.Default.Info, contentDescription = null, tint = Color.White)
                                    Spacer(Modifier.width(6.dp))
                                    Text("Plus d'infos", color = Color.White, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    } else {
                        Column(
                            modifier = Modifier.fillMaxWidth().align(Alignment.BottomCenter).padding(bottom = 18.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(hero.title.uppercase(), color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.padding(horizontal = 24.dp))
                            Spacer(Modifier.height(14.dp))
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable {
                                    val inList = vm.myList.any { it.id == hero.id }
                                    vm.myList = if (inList) vm.myList.filterNot { it.id == hero.id } else listOf(hero) + vm.myList
                                }) {
                                    Icon(if (vm.myList.any { it.id == hero.id }) Icons.Default.Check else Icons.Default.Add, contentDescription = null, tint = Color.White)
                                    Text("Ma liste", color = Color.White, fontSize = 11.sp)
                                }
                                Button(
                                    onClick = { vm.playMedia(hero) },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                                    shape = RoundedCornerShape(4.dp)
                                ) {
                                    Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color.Black)
                                    Spacer(Modifier.width(4.dp))
                                    Text("Lecture", color = Color.Black, fontWeight = FontWeight.Bold)
                                }
                                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { vm.openDetail(hero) }) {
                                    Icon(Icons.Default.Info, contentDescription = null, tint = Color.White)
                                    Text("Infos", color = Color.White, fontSize = 11.sp)
                                }
                            }
                        }
                    }
                }
            }
        }

        items(vm.rows) { (title, items) ->
            Column(modifier = Modifier.padding(vertical = 10.dp)) {
                Text(title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(items) { item ->
                        Box(
                            modifier = Modifier
                                .size(if (isTablet) 136.dp else 112.dp, if (isTablet) 198.dp else 164.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .background(Color(0xFF1A1A1A))
                                .clickable { vm.openDetail(item) }
                        ) {
                            AsyncImage(model = item.posterUrl, contentDescription = item.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            if (item.top10Rank != null) {
                                Text(
                                    "TOP ${item.top10Rank}",
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Black,
                                    modifier = Modifier.align(Alignment.TopEnd).background(Color(0xFFE50914)).padding(horizontal = 5.dp, vertical = 2.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NFSearchContent(vm: NetflixViewModel, cols: Int) {
    Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
        OutlinedTextField(
            value = vm.searchQuery,
            onValueChange = { vm.search(it) },
            placeholder = { Text("Rechercher un film, une série...", color = Color.Gray) },
            singleLine = true,
            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White),
            modifier = Modifier.fillMaxWidth().padding(16.dp)
        )
        LazyVerticalGrid(
            columns = GridCells.Fixed(cols),
            contentPadding = PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(vm.searchResults) { item ->
                AsyncImage(
                    model = item.posterUrl,
                    contentDescription = item.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.aspectRatio(2f / 3f).clip(RoundedCornerShape(4.dp)).clickable { vm.openDetail(item) }
                )
            }
        }
    }
}

@Composable
private fun NFMyListContent(vm: NetflixViewModel, cols: Int) {
    Column(modifier = Modifier.fillMaxSize().statusBarsPadding().padding(16.dp)) {
        Text("Ma liste", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))
        LazyVerticalGrid(
            columns = GridCells.Fixed(cols),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(vm.myList) { item ->
                AsyncImage(
                    model = item.posterUrl,
                    contentDescription = item.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.aspectRatio(2f / 3f).clip(RoundedCornerShape(4.dp)).clickable { vm.openDetail(item) }
                )
            }
        }
    }
}
