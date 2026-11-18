package com.mediahub.netflix

import android.content.Context
import com.mediahub.core.AppHttp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

data class NFMedia(
    val id: Int,
    val mediaType: String, // "movie" or "tv"
    val title: String,
    val overview: String,
    val posterPath: String?,
    val backdropPath: String?,
    val releaseYear: String,
    val top10Rank: Int? = null
) {
    val posterUrl: String? get() = posterPath?.let { "https://image.tmdb.org/t/p/w500$it" }
    val backdropUrl: String? get() = backdropPath?.let { "https://image.tmdb.org/t/p/w1280$it" } ?: posterUrl
}

data class NFEpisode(
    val id: Int,
    val season: Int,
    val episode: Int,
    val name: String,
    val overview: String,
    val stillPath: String?
) {
    val stillUrl: String? get() = stillPath?.let { "https://image.tmdb.org/t/p/w500$it" }
}

data class NFStreamSource(
    val url: String,
    val name: String,
    val provider: String,
    val format: String,
    val language: String,
    val isEmbed: Boolean,
    val referer: String? = null
)

object NetflixEngine {
    private const val TMDB_KEY = "YOUR_TMDB_API_KEY"
    private const val TMDB_BASE = "https://api.themoviedb.org/3"
    const val DEFAULT_MOVIX = "https://api.movix.miami"

    private var movixBase = DEFAULT_MOVIX

    fun init(ctx: Context) {
        val prefs = ctx.getSharedPreferences("nf_prefs", Context.MODE_PRIVATE)
        movixBase = prefs.getString("movix_url", DEFAULT_MOVIX) ?: DEFAULT_MOVIX
    }

    fun getMovixBase(): String = movixBase

    fun setMovixBase(ctx: Context, raw: String): String {
        var c = raw.trim().trimEnd('/')
        if (c.isNotEmpty() && !c.startsWith("http")) c = "https://$c"
        if (c.isEmpty()) c = DEFAULT_MOVIX
        movixBase = c
        ctx.getSharedPreferences("nf_prefs", Context.MODE_PRIVATE).edit().putString("movix_url", c).apply()
        return c
    }

    suspend fun fetchHomeFeed(filter: String = "All"): Pair<NFMedia?, List<Pair<String, List<NFMedia>>>> = coroutineScope {
        val trendTask = async { fetchTMDBList("trending/all/day") }
        val moviesTask = async { fetchTMDBList("movie/popular", forceType = "movie") }
        val tvTask = async { fetchTMDBList("tv/popular", forceType = "tv") }
        val actionTask = async { fetchTMDBList("discover/movie", mapOf("with_genres" to "28"), "movie") }

        val trend = trendTask.await()
        val movies = moviesTask.await()
        val tv = tvTask.await()
        val action = actionTask.await()

        val filtered = when (filter) {
            "Series" -> listOf(
                "Top 10 Séries" to tv.take(10).mapIndexed { i, m -> m.copy(top10Rank = i + 1) },
                "Séries populaires" to tv
            )
            "Films" -> listOf(
                "Top 10 Films" to movies.take(10).mapIndexed { i, m -> m.copy(top10Rank = i + 1) },
                "Films populaires" to movies,
                "Action & Adrénaline" to action
            )
            else -> listOf(
                "Top 10 en France aujourd'hui" to trend.take(10).mapIndexed { i, m -> m.copy(top10Rank = i + 1) },
                "Tendances Films" to movies,
                "Séries du moment" to tv,
                "Action & Adrénaline" to action
            )
        }
        val hero = when (filter) {
            "Series" -> tv.firstOrNull()
            "Films" -> movies.firstOrNull()
            else -> trend.firstOrNull()
        }
        Pair(hero, filtered.filter { it.second.isNotEmpty() })
    }

    suspend fun search(query: String): List<NFMedia> {
        val q = URLEncoder.encode(query.trim(), "UTF-8")
        return fetchTMDBList("search/multi", mapOf("query" to q))
    }

    suspend fun fetchEpisodes(tvId: Int, season: Int): List<NFEpisode> = withContext(Dispatchers.IO) {
        val url = "$TMDB_BASE/tv/$tvId/season/$season?api_key=$TMDB_KEY&language=fr-FR"
        val raw = getText(url) ?: return@withContext emptyList()
        val eps = JSONObject(raw).optJSONArray("episodes") ?: return@withContext emptyList()
        val out = mutableListOf<NFEpisode>()
        for (i in 0 until eps.length()) {
            val e = eps.getJSONObject(i)
            out.add(
                NFEpisode(
                    id = e.optInt("id"),
                    season = season,
                    episode = e.optInt("episode_number", i + 1),
                    name = e.optString("name", "Épisode ${i + 1}"),
                    overview = e.optString("overview"),
                    stillPath = e.optString("still_path").takeIf { it.isNotEmpty() && it != "null" }
                )
            )
        }
        out
    }

    suspend fun resolveMovixStreams(media: NFMedia, season: Int = 1, episode: Int = 1): List<NFStreamSource> = coroutineScope {
        val pur = async { fetchPurStream(media, season, episode) }
        val lnk = async { fetchLinks(media, season, episode) }
        val fs = async { fetchFStream(media, season, episode) }
        val wf = async { fetchWiflix(media) }

        val all = pur.await() + lnk.await() + fs.await() + wf.await()
        val seen = mutableSetOf<String>()
        val direct = all.filter { !it.isEmbed && seen.add(it.url) }
        val embeds = all.filter { it.isEmbed && seen.add(it.url) }
        direct + embeds
    }

    suspend fun extractDirectStream(src: NFStreamSource): NFStreamSource? = withContext(Dispatchers.IO) {
        if (!src.isEmbed) return@withContext src
        val html = getText(src.url, referer = "https://french-stream.net/") ?: return@withContext null
        val regex = Regex("""https?://[^\s"'<>\\]+\.(?:m3u8|mp4)(?:\?[^\s"'<>\\]*)?""")
        val found = regex.findAll(html).map { it.value.replace("\\/", "/") }
            .firstOrNull { !it.contains("/troll/") && !it.contains("preview") }
        if (found != null) {
            val fmt = if (found.contains(".m3u8")) "m3u8" else "mp4"
            return@withContext src.copy(url = found, format = fmt, isEmbed = false)
        }
        null
    }

    private suspend fun fetchPurStream(m: NFMedia, s: Int, e: Int): List<NFStreamSource> = withContext(Dispatchers.IO) {
        val url = if (m.mediaType == "movie") "$movixBase/api/purstream/movie/${m.id}/stream"
        else "$movixBase/api/purstream/tv/${m.id}/stream?season=$s&episode=$e"
        val raw = getMovixText(url) ?: return@withContext emptyList()
        val arr = JSONObject(raw).optJSONArray("sources") ?: return@withContext emptyList()
        (0 until arr.length()).mapNotNull { i ->
            val obj = arr.getJSONObject(i)
            val u = obj.optString("url")
            if (u.isEmpty()) null else NFStreamSource(u, obj.optString("name", "PurStream 1080p"), "PurStream", obj.optString("format", "m3u8"), "MULTI", false, null)
        }
    }

    private suspend fun fetchFStream(m: NFMedia, s: Int, e: Int): List<NFStreamSource> = withContext(Dispatchers.IO) {
        val url = if (m.mediaType == "movie") "$movixBase/api/fstream/movie/${m.id}"
        else "$movixBase/api/fstream/tv/${m.id}/season/$s"
        val raw = getMovixText(url) ?: return@withContext emptyList()
        val json = JSONObject(raw)
        val langObj = if (m.mediaType == "movie") json.optJSONObject("players")
        else json.optJSONObject("episodes")?.optJSONObject("$e")?.optJSONObject("languages")
        langObj ?: return@withContext emptyList()
        val out = mutableListOf<NFStreamSource>()
        val keys = langObj.keys()
        while (keys.hasNext()) {
            val lang = keys.next()
            val arr = langObj.optJSONArray(lang) ?: continue
            for (i in 0 until arr.length()) {
                val entry = arr.getJSONObject(i)
                val u = entry.optString("url")
                if (u.isNotEmpty()) {
                    val p = entry.optString("player", "Serveur")
                    val direct = u.contains(".m3u8") || u.contains(".mp4")
                    out.add(NFStreamSource(u, "$p ($lang)", "FStream", if (direct) "mp4" else "embed", lang, !direct))
                }
            }
        }
        out
    }

    private suspend fun fetchLinks(m: NFMedia, s: Int, e: Int): List<NFStreamSource> = withContext(Dispatchers.IO) {
        val url = if (m.mediaType == "movie") "$movixBase/api/links/movie/${m.id}"
        else "$movixBase/api/links/tv/${m.id}"
        val raw = getMovixText(url) ?: return@withContext emptyList()
        val json = JSONObject(raw)
        val arr: JSONArray? = if (m.mediaType == "movie") {
            json.optJSONObject("data")?.optJSONArray("links")
        } else {
            val dataArr = json.optJSONArray("data")
            var match: JSONArray? = null
            if (dataArr != null) {
                for (i in 0 until dataArr.length()) {
                    val o = dataArr.getJSONObject(i)
                    if (o.optInt("season_number") == s && o.optInt("episode_number") == e) {
                        match = o.optJSONArray("links")
                        break
                    }
                }
            }
            match
        }
        arr ?: return@withContext emptyList()
        val out = mutableListOf<NFStreamSource>()
        for (i in 0 until arr.length()) {
            val item = arr.get(i)
            val u = when (item) {
                is String -> item
                is JSONObject -> item.optString("url")
                else -> ""
            }
            if (u.isNotEmpty()) {
                val direct = u.contains(".m3u8") || u.contains(".mp4")
                out.add(NFStreamSource(u, if (direct) "Direct MP4" else u.substringAfter("://").substringBefore("/"), "Links", if (direct) "mp4" else "embed", "MULTI", !direct))
            }
        }
        out
    }

    private suspend fun fetchWiflix(m: NFMedia): List<NFStreamSource> = withContext(Dispatchers.IO) {
        if (m.mediaType != "movie") return@withContext emptyList()
        val raw = getMovixText("$movixBase/api/wiflix/movie/${m.id}") ?: return@withContext emptyList()
        val players = JSONObject(raw).optJSONObject("players") ?: return@withContext emptyList()
        val out = mutableListOf<NFStreamSource>()
        val keys = players.keys()
        while (keys.hasNext()) {
            val lang = keys.next()
            val arr = players.optJSONArray(lang) ?: continue
            for (i in 0 until arr.length()) {
                val entry = arr.getJSONObject(i)
                val u = entry.optString("url")
                if (u.isNotEmpty()) {
                    val host = entry.optString("name", "Wiflix")
                    out.add(NFStreamSource(u, "$host (${lang.uppercase()})", "Wiflix", "embed", lang.uppercase(), true))
                }
            }
        }
        out
    }

    private suspend fun fetchTMDBList(endpoint: String, extra: Map<String, String> = emptyMap(), forceType: String? = null): List<NFMedia> = withContext(Dispatchers.IO) {
        val sb = StringBuilder("$TMDB_BASE/$endpoint?api_key=$TMDB_KEY&language=fr-FR")
        for ((k, v) in extra) sb.append("&$k=$v")
        val raw = getText(sb.toString()) ?: return@withContext emptyList()
        val results = JSONObject(raw).optJSONArray("results") ?: return@withContext emptyList()
        val out = mutableListOf<NFMedia>()
        for (i in 0 until results.length()) {
            val o = results.getJSONObject(i)
            val mType = o.optString("media_type").ifEmpty { forceType ?: if (o.has("first_air_date")) "tv" else "movie" }
            if (mType != "movie" && mType != "tv") continue
            val poster = o.optString("poster_path").takeIf { it.isNotEmpty() && it != "null" }
            val back = o.optString("backdrop_path").takeIf { it.isNotEmpty() && it != "null" }
            if (poster == null && back == null) continue
            val title = o.optString("title").ifEmpty { o.optString("name", "Titre") }
            val date = o.optString("release_date").ifEmpty { o.optString("first_air_date") }.take(4)
            out.add(NFMedia(o.optInt("id"), mType, title, o.optString("overview"), poster, back, date))
        }
        out
    }

    private fun getMovixText(url: String): String? {
        val origin = movixBase.replace("://api.", "://")
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
            .header("Origin", origin)
            .header("Referer", "$origin/")
            .build()
        return try {
            AppHttp.client.newCall(req).execute().use { r -> if (r.isSuccessful) r.body?.string() else null }
        } catch (_: Exception) { null }
    }

    private fun getText(url: String, referer: String? = null): String? {
        val b = Request.Builder().url(url).header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
        if (referer != null) b.header("Referer", referer)
        return try {
            AppHttp.client.newCall(b.build()).execute().use { r -> if (r.isSuccessful) r.body?.string() else null }
        } catch (_: Exception) { null }
    }
}
