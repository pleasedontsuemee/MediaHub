package com.mediahub.spotify

import android.content.Context
import com.mediahub.core.AppHttp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

enum class SPCollectionKind { PLAYLIST, ALBUM, ARTIST, PODCAST }

data class SPTrack(
    val id: String,
    val title: String,
    val artistName: String,
    val artistId: String? = null,
    val albumTitle: String = "",
    val albumId: String? = null,
    val coverUrl: String? = null,
    val durationSec: Int = 180,
    val previewUrl: String? = null,
    val directAudioUrl: String? = null,
    val localFilePath: String? = null
)

data class SPCollection(
    val id: String,
    val kind: SPCollectionKind,
    val title: String,
    val subtitle: String = "",
    val coverUrl: String? = null,
    val tracks: List<SPTrack> = emptyList(),
    val isUserCreated: Boolean = false
)

data class SPHomeData(
    val topTracks: List<SPTrack>,
    val playlists: List<SPCollection>,
    val albums: List<SPCollection>,
    val artists: List<SPCollection>,
    val podcasts: List<SPCollection>
)

data class SPSearchData(
    val tracks: List<SPTrack>,
    val albums: List<SPCollection>,
    val artists: List<SPCollection>,
    val playlists: List<SPCollection>,
    val podcasts: List<SPCollection>
)

data class SPArtistDetails(
    val name: String,
    val pictureUrl: String?,
    val nbFan: Int,
    val topTracks: List<SPTrack>,
    val albums: List<SPCollection>,
    val related: List<SPCollection>
)

data class SPAlbumDetails(
    val title: String,
    val artistName: String,
    val artistId: String?,
    val artistPicUrl: String?,
    val coverUrl: String?,
    val releaseYear: String,
    val tracks: List<SPTrack>
)

object SpotifyEngine {
    private const val DEEZER = "https://api.deezer.com"
    private val jsonMedia = "application/json".toMediaType()
    private var arlCookie: String = ""

    fun init(ctx: Context) {
        arlCookie = ctx.getSharedPreferences("sp_prefs", Context.MODE_PRIVATE).getString("arl", "") ?: ""
        if (arlCookie.isNotEmpty()) AppHttp.setCookie("deezer.com", "arl", arlCookie)
    }

    fun getARL(): String = arlCookie

    fun setARL(ctx: Context, raw: String) {
        arlCookie = raw.trim()
        ctx.getSharedPreferences("sp_prefs", Context.MODE_PRIVATE).edit().putString("arl", arlCookie).apply()
        AppHttp.setCookie("deezer.com", "arl", arlCookie)
    }

    suspend fun validateARL(): Pair<Boolean, String?> = withContext(Dispatchers.IO) {
        if (arlCookie.isEmpty()) return@withContext Pair(false, null)
        val sess = fetchSession(arlCookie) ?: return@withContext Pair(false, null)
        Pair(true, sess.third)
    }

    suspend fun fetchHome(): SPHomeData = coroutineScope {
        val t = async { fetchChartTracks() }
        val p = async { fetchChartCollections("playlists", SPCollectionKind.PLAYLIST, "Playlist") }
        val a = async { fetchChartCollections("albums", SPCollectionKind.ALBUM, "Album") }
        val ar = async { fetchChartCollections("artists", SPCollectionKind.ARTIST, "Artiste") }
        val pod = async { fetchChartCollections("podcasts", SPCollectionKind.PODCAST, "Podcast") }
        SPHomeData(t.await(), p.await(), a.await(), ar.await(), pod.await())
    }

    suspend fun search(query: String): SPSearchData = coroutineScope {
        val q = URLEncoder.encode(query.trim(), "UTF-8")
        val t = async { fetchTracksFromUrl("$DEEZER/search/track?q=$q&limit=25") }
        val a = async { fetchCollectionsFromUrl("$DEEZER/search/album?q=$q&limit=12", SPCollectionKind.ALBUM, "Album") }
        val ar = async { fetchCollectionsFromUrl("$DEEZER/search/artist?q=$q&limit=10", SPCollectionKind.ARTIST, "Artiste") }
        val p = async { fetchCollectionsFromUrl("$DEEZER/search/playlist?q=$q&limit=10", SPCollectionKind.PLAYLIST, "Playlist") }
        val pod = async { fetchCollectionsFromUrl("$DEEZER/search/podcast?q=$q&limit=10", SPCollectionKind.PODCAST, "Podcast") }
        SPSearchData(t.await(), a.await(), ar.await(), p.await(), pod.await())
    }

    suspend fun fetchCollectionTracks(col: SPCollection): List<SPTrack> {
        if (col.isUserCreated) return col.tracks
        return when (col.kind) {
            SPCollectionKind.PLAYLIST -> fetchTracksFromUrl("$DEEZER/playlist/${col.id}/tracks?limit=50")
            SPCollectionKind.ALBUM -> fetchTracksFromUrl("$DEEZER/album/${col.id}/tracks?limit=50", col.title, col.coverUrl)
            SPCollectionKind.ARTIST -> fetchTracksFromUrl("$DEEZER/artist/${col.id}/top?limit=30")
            SPCollectionKind.PODCAST -> fetchPodcastEpisodes(col)
        }
    }

    suspend fun fetchArtistDetails(artistId: String): SPArtistDetails = coroutineScope {
        val info = async { getJson("$DEEZER/artist/$artistId") }
        val top = async { fetchTracksFromUrl("$DEEZER/artist/$artistId/top?limit=25") }
        val al = async { fetchCollectionsFromUrl("$DEEZER/artist/$artistId/albums?limit=20", SPCollectionKind.ALBUM, "Album") }
        val rel = async { fetchCollectionsFromUrl("$DEEZER/artist/$artistId/related?limit=12", SPCollectionKind.ARTIST, "Artiste") }

        val j = info.await()
        val name = j?.optString("name", "Artiste") ?: "Artiste"
        val pic = j?.optString("picture_xl")?.ifEmpty { j.optString("picture_big") }
        val fans = j?.optInt("nb_fan") ?: 0
        SPArtistDetails(name, pic, fans, top.await(), al.await(), rel.await())
    }

    suspend fun fetchAlbumDetails(albumId: String): SPAlbumDetails = withContext(Dispatchers.IO) {
        val j = getJson("$DEEZER/album/$albumId") ?: return@withContext SPAlbumDetails("Album", "Artiste", null, null, null, "", emptyList())
        val title = j.optString("title", "Album")
        val cover = j.optString("cover_xl").ifEmpty { j.optString("cover_big") }
        val year = j.optString("release_date").take(4)
        val art = j.optJSONObject("artist")
        val artName = art?.optString("name", "Artiste") ?: "Artiste"
        val artId = art?.optInt("id")?.takeIf { it > 0 }?.toString()
        val artPic = art?.optString("picture_medium")
        val arr = j.optJSONObject("tracks")?.optJSONArray("data") ?: JSONArray()
        val tracks = (0 until arr.length()).mapNotNull { parseTrack(arr.getJSONObject(it), title, cover) }
        SPAlbumDetails(title, artName, artId, artPic, cover, year, tracks)
    }

    suspend fun resolvePlayableStream(track: SPTrack): Pair<String, String>? = withContext(Dispatchers.IO) {
        if (!track.localFilePath.isNullOrEmpty()) return@withContext Pair(track.localFilePath, "Fichier local")
        if (!track.directAudioUrl.isNullOrEmpty()) return@withContext Pair(track.directAudioUrl, "Podcast MP3")

        if (arlCookie.isNotEmpty()) {
            val sess = fetchSession(arlCookie)
            if (sess != null) {
                val (apiToken, licenseToken, _) = sess
                val songReq = Request.Builder()
                    .url("https://www.deezer.com/ajax/gw-light.php?method=song.getData&input=3&api_version=1.0&api_token=$apiToken")
                    .post(JSONObject().put("sng_id", track.id).toString().toRequestBody(jsonMedia))
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
                    .build()
                val trackToken = AppHttp.client.newCall(songReq).execute().use { r ->
                    val raw = r.body?.string() ?: ""
                    JSONObject(raw).optJSONObject("results")?.optString("TRACK_TOKEN") ?: ""
                }
                if (trackToken.isNotEmpty()) {
                    val mediaBody = JSONObject().apply {
                        put("license_token", licenseToken)
                        put("media", JSONArray().put(JSONObject().apply {
                            put("type", "FULL")
                            put("formats", JSONArray()
                                .put(JSONObject().put("cipher", "BF_CBC_STRIPE").put("format", "MP3_320"))
                                .put(JSONObject().put("cipher", "BF_CBC_STRIPE").put("format", "MP3_128")))
                        }))
                        put("track_tokens", JSONArray().put(trackToken))
                    }
                    val mReq = Request.Builder()
                        .url("https://media.deezer.com/v1/get_url")
                        .post(mediaBody.toString().toRequestBody(jsonMedia))
                        .build()
                    val cdnUrl = AppHttp.client.newCall(mReq).execute().use { r ->
                        val raw = r.body?.string() ?: ""
                        JSONObject(raw).optJSONArray("data")?.optJSONObject(0)
                            ?.optJSONArray("media")?.optJSONObject(0)
                            ?.optJSONArray("sources")?.optJSONObject(0)?.optString("url") ?: ""
                    }
                    if (cdnUrl.isNotEmpty()) {
                        val proxyUrl = DeezerStreamProxy.register(track.id, cdnUrl)
                        return@withContext Pair(proxyUrl, "OpenDeezer ARL (Complet)")
                    }
                }
            }
        }

        if (!track.previewUrl.isNullOrEmpty()) {
            return@withContext Pair(track.previewUrl, "Deezer Teaser 30s")
        }
        null
    }

    private fun fetchSession(arl: String): Triple<String, String, String>? {
        AppHttp.setCookie("deezer.com", "arl", arl)
        val req = Request.Builder()
            .url("https://www.deezer.com/ajax/gw-light.php?method=deezer.getUserData&input=3&api_version=1.0&api_token=null")
            .post("".toRequestBody(null))
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
            .build()
        return try {
            AppHttp.client.newCall(req).execute().use { r ->
                val res = JSONObject(r.body?.string() ?: "").optJSONObject("results") ?: return null
                val token = res.optString("checkForm")
                val user = res.optJSONObject("USER") ?: return null
                val uid = user.optInt("USER_ID", 0)
                if (uid <= 0 || token.isEmpty()) return null
                val lic = user.optJSONObject("OPTIONS")?.optString("license_token") ?: return null
                val name = user.optString("BLOG_NAME", "Deezer")
                Triple(token, lic, name)
            }
        } catch (_: Exception) { null }
    }

    private suspend fun fetchChartTracks() = fetchTracksFromUrl("$DEEZER/chart/0/tracks?limit=25")
    private suspend fun fetchChartCollections(path: String, kind: SPCollectionKind, label: String) =
        fetchCollectionsFromUrl("$DEEZER/chart/0/$path?limit=15", kind, label)

    private suspend fun fetchTracksFromUrl(url: String, fallbackAlbum: String? = null, fallbackCover: String? = null): List<SPTrack> = withContext(Dispatchers.IO) {
        val arr = getJson(url)?.optJSONArray("data") ?: return@withContext emptyList()
        (0 until arr.length()).mapNotNull { parseTrack(arr.getJSONObject(it), fallbackAlbum, fallbackCover) }
    }

    private suspend fun fetchPodcastEpisodes(col: SPCollection): List<SPTrack> = withContext(Dispatchers.IO) {
        val arr = getJson("$DEEZER/podcast/${col.id}/episodes?limit=50")?.optJSONArray("data") ?: return@withContext emptyList()
        (0 until arr.length()).mapNotNull { i ->
            val o = arr.getJSONObject(i)
            val id = o.optInt("id")
            val title = o.optString("title")
            val mp3 = o.optString("mp3")
            val pic = o.optString("picture_xl").ifEmpty { col.coverUrl ?: "" }
            if (title.isEmpty()) null else SPTrack("ep_$id", title, col.title, null, "Podcast", null, pic, o.optInt("duration", 1800), mp3, mp3)
        }
    }

    private suspend fun fetchCollectionsFromUrl(url: String, kind: SPCollectionKind, label: String): List<SPCollection> = withContext(Dispatchers.IO) {
        val arr = getJson(url)?.optJSONArray("data") ?: return@withContext emptyList()
        (0 until arr.length()).mapNotNull { i ->
            val o = arr.getJSONObject(i)
            val id = o.optInt("id")
            val title = o.optString("title").ifEmpty { o.optString("name") }
            if (id <= 0 || title.isEmpty()) null else {
                val cover = o.optString("cover_xl").ifEmpty { o.optString("picture_xl") }.ifEmpty { o.optString("cover_big") }.ifEmpty { o.optString("picture_big") }
                val sub = when (kind) {
                    SPCollectionKind.ALBUM -> "Album • ${o.optJSONObject("artist")?.optString("name") ?: label}"
                    SPCollectionKind.PLAYLIST -> "Playlist • ${o.optJSONObject("user")?.optString("name") ?: label}"
                    else -> label
                }
                SPCollection(id.toString(), kind, title, sub, cover)
            }
        }
    }

    private fun parseTrack(o: JSONObject, fallbackAlbum: String? = null, fallbackCover: String? = null): SPTrack? {
        val id = o.optInt("id")
        val title = o.optString("title_short").ifEmpty { o.optString("title") }
        if (id <= 0 || title.isEmpty()) return null
        val art = o.optJSONObject("artist")
        val alb = o.optJSONObject("album")
        val cover = alb?.optString("cover_xl")?.ifEmpty { alb.optString("cover_big") }
            ?: art?.optString("picture_xl")
            ?: fallbackCover
        return SPTrack(
            id = id.toString(),
            title = title,
            artistName = art?.optString("name", "Artiste") ?: "Artiste",
            artistId = art?.optInt("id")?.takeIf { it > 0 }?.toString(),
            albumTitle = alb?.optString("title") ?: fallbackAlbum ?: "",
            albumId = alb?.optInt("id")?.takeIf { it > 0 }?.toString(),
            coverUrl = cover,
            durationSec = o.optInt("duration", 180),
            previewUrl = o.optString("preview").takeIf { it.isNotEmpty() }
        )
    }

    private fun getJson(url: String): JSONObject? = try {
        AppHttp.client.newCall(Request.Builder().url(url).build()).execute().use { r ->
            if (r.isSuccessful) JSONObject(r.body?.string() ?: "") else null
        }
    } catch (_: Exception) { null }
}
