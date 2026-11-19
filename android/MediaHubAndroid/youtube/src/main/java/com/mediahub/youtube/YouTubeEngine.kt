package com.mediahub.youtube

import com.mediahub.core.AppHttp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

data class YTVideo(
    val id: String,
    val title: String,
    val channelTitle: String,
    val thumbnailUrl: String,
    val durationText: String = "",
    val viewCountText: String = ""
)

data class YTFormat(
    val height: Int,
    val label: String,
    val url: String
)

data class YTStreamInfo(
    val hlsUrl: String?,
    val progressiveFormats: List<YTFormat>,
    val userAgent: String = YouTubeEngine.VISIONOS_UA
)

object YouTubeEngine {
    private val jsonMedia = "application/json".toMediaType()
    const val VISIONOS_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private const val ANDROID_UA = "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip"
    private const val IOS_UA = "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"

    @Volatile
    private var cachedVisitorData: String? = null

    private fun ensureVisitorData(forceRefresh: Boolean = false): String {
        if (!forceRefresh) {
            cachedVisitorData?.takeIf { it.isNotEmpty() }?.let { return it }
        } else {
            cachedVisitorData = null
        }
        val body = JSONObject().apply {
            put("context", JSONObject().apply {
                put("client", JSONObject().apply {
                    put("clientName", "WEB")
                    put("clientVersion", "2.20260708.00.00")
                    put("hl", "fr")
                    put("gl", "FR")
                })
            })
        }
        val req = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false")
            .post(body.toString().toRequestBody(jsonMedia))
            .header("Origin", "https://www.youtube.com")
            .header("User-Agent", VISIONOS_UA)
            .build()
        try {
            AppHttp.client.newCall(req).execute().use { resp ->
                val raw = resp.body?.string() ?: return ""
                val vd = JSONObject(raw).optJSONObject("responseContext")?.optString("visitorData") ?: ""
                if (vd.isNotEmpty()) {
                    cachedVisitorData = vd
                    return vd
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    suspend fun fetchFeed(query: String = "trending france musique"): List<YTVideo> = withContext(Dispatchers.IO) {
        val body = JSONObject().apply {
            put("context", JSONObject().apply {
                put("client", JSONObject().apply {
                    put("clientName", "WEB")
                    put("clientVersion", "2.20241106.01.00")
                    put("hl", "fr")
                    put("gl", "FR")
                })
            })
            put("query", query)
        }
        val req = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/search?prettyPrint=false")
            .post(body.toString().toRequestBody(jsonMedia))
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36")
            .build()

        val out = mutableListOf<YTVideo>()
        try {
            AppHttp.client.newCall(req).execute().use { resp ->
                val raw = resp.body?.string() ?: return@withContext emptyList()
                val root = JSONObject(raw)
                collectVideos(root, out, mutableSetOf())
            }
        } catch (_: Exception) {}
        out
    }

    suspend fun fetchPersonalizedHomeFeed(
        chip: String,
        watchKeywords: List<String>,
        subscribedChannels: Set<String>,
        watchedIds: Set<String>
    ): List<YTVideo> = coroutineScope {
        val queries = mutableListOf<String>()
        when {
            chip == "Nouveautés" || chip == "New to you" -> {
                val pool = listOf(
                    "Découverte documentaire tech science France",
                    "Nouveautés musique indépendante clip",
                    "Reportage insolite histoire culture",
                    "Créateurs émergents gaming humour France"
                ).shuffled()
                queries.addAll(pool.take(2))
            }
            chip != "Tout" && chip != "All" && chip.isNotBlank() -> {
                val chipMap = mapOf(
                    "Musique" to listOf("Nouveautés musique clip officiel France", "Top hits musique 2025"),
                    "Gaming" to listOf("Gaming let's play France", "Jeux vidéo gameplay nouveautés"),
                    "Direct" to listOf("Live stream direct France", "Musique lofi radio live"),
                    "Podcasts" to listOf("Podcast interview discussion France", "Débat société culture podcast"),
                    "Actualités" to listOf("Actualités France journal info", "Tech économie actualité"),
                    "Tech" to listOf("High-tech test smartphone", "Programmation IA nouveautés tech")
                )
                queries.addAll(chipMap[chip] ?: listOf("$chip France", chip))
                watchKeywords.firstOrNull()?.takeIf { it.isNotBlank() }?.let {
                    queries.add("$chip $it")
                }
            }
            else -> {
                watchKeywords.firstOrNull()?.takeIf { it.isNotBlank() }?.let { queries.add(it) }
                if (watchKeywords.size > 1) {
                    watchKeywords.drop(1).take(4).randomOrNull()?.takeIf { it.isNotBlank() }?.let { queries.add(it) }
                }
                subscribedChannels.randomOrNull()?.takeIf { it.isNotBlank() }?.let { queries.add(it) }
                val fallbacks = listOf(
                    "Tendances France vidéos populaires",
                    "Musique clip officiel France 2025",
                    "Divertissement gaming tech France"
                )
                for (fb in fallbacks) {
                    if (queries.size >= 3) break
                    queries.add(fb)
                }
            }
        }

        val uniqueQueries = queries.distinct().take(3)
        val buckets = uniqueQueries.map { q -> async { fetchFeed(q) } }.awaitAll()

        val merged = mutableListOf<YTVideo>()
        val seenIds = mutableSetOf<String>()
        val channelCounts = mutableMapOf<String, Int>()
        val subLower = subscribedChannels.map { it.lowercase() }.toSet()
        val maxLen = buckets.maxOfOrNull { it.size } ?: 0

        for (i in 0 until maxLen) {
            for (b in buckets) {
                if (i >= b.size) continue
                val vid = b[i]
                if (!seenIds.add(vid.id)) continue
                if ((chip == "Nouveautés" || chip == "New to you") && subLower.contains(vid.channelTitle.lowercase())) continue
                if (watchedIds.contains(vid.id)) continue
                val chKey = vid.channelTitle.lowercase()
                val cnt = channelCounts[chKey] ?: 0
                if (cnt >= 2 && merged.size < 18) continue
                channelCounts[chKey] = cnt + 1
                merged.add(vid)
            }
        }

        if (merged.size < 8) {
            for (b in buckets) {
                for (vid in b) {
                    if (seenIds.add(vid.id)) merged.add(vid)
                }
            }
        }
        merged.take(30)
    }

    private fun collectVideos(node: Any?, out: MutableList<YTVideo>, seen: MutableSet<String>) {
        if (out.size >= 30) return
        when (node) {
            is JSONObject -> {
                if (node.has("videoRenderer")) {
                    val vr = node.getJSONObject("videoRenderer")
                    val vid = vr.optString("videoId")
                    if (vid.isNotEmpty() && seen.add(vid)) {
                        val title = vr.optJSONObject("title")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")
                            ?: "Vidéo YouTube"
                        val chan = vr.optJSONObject("ownerText")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text")
                            ?: "Chaîne"
                        val dur = vr.optJSONObject("lengthText")?.optString("simpleText") ?: ""
                        val views = vr.optJSONObject("shortViewCountText")?.optString("simpleText") ?: ""
                        val thumb = "https://i.ytimg.com/vi/$vid/hqdefault.jpg"
                        out.add(YTVideo(vid, title, chan, thumb, dur, views))
                    }
                }
                val keys = node.keys()
                while (keys.hasNext()) {
                    collectVideos(node.opt(keys.next()), out, seen)
                }
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    collectVideos(node.opt(i), out, seen)
                }
            }
        }
    }

    suspend fun resolvePlayableUrl(videoId: String): String? {
        val info = resolveStreamInfo(videoId) ?: return null
        return info.hlsUrl ?: info.progressiveFormats.firstOrNull()?.url
    }

    suspend fun resolveStreamInfo(videoId: String, forceRefresh: Boolean = false): YTStreamInfo? = withContext(Dispatchers.IO) {
        val vd = ensureVisitorData(forceRefresh = forceRefresh)

        // 1. Primary: VISIONOS 1.02 (ID 101) with visitorData -> 144p..4K60 SDR & HDR HLS + adaptive MP4, NO 51s 403!
        queryPlayerClient(
            videoId = videoId,
            visitorData = vd,
            clientId = 101,
            clientName = "VISIONOS",
            clientVersion = "1.02",
            userAgent = VISIONOS_UA,
            extraClientFields = mapOf(
                "deviceMake" to "Apple",
                "deviceModel" to "RealityDevice17,1",
                "osName" to "visionOS",
                "osVersion" to "26.5.23O471"
            )
        )?.let { return@withContext it }

        // 2. Fallback: ANDROID 21.26.364 (ID 3) with visitorData
        queryPlayerClient(
            videoId = videoId,
            visitorData = vd,
            clientId = 3,
            clientName = "ANDROID",
            clientVersion = "21.26.364",
            userAgent = ANDROID_UA,
            extraClientFields = mapOf(
                "osName" to "Android",
                "osVersion" to "11",
                "androidSdkVersion" to 30
            )
        )?.let { return@withContext it }

        // 3. Last resort: IOS 21.26.4 (ID 5) with visitorData
        queryPlayerClient(
            videoId = videoId,
            visitorData = vd,
            clientId = 5,
            clientName = "IOS",
            clientVersion = "21.26.4",
            userAgent = IOS_UA,
            extraClientFields = mapOf(
                "deviceMake" to "Apple",
                "deviceModel" to "iPhone16,2",
                "osName" to "iPhone",
                "osVersion" to "18.3.2.22D82"
            )
        )
    }

    private fun queryPlayerClient(
        videoId: String,
        visitorData: String,
        clientId: Int,
        clientName: String,
        clientVersion: String,
        userAgent: String,
        extraClientFields: Map<String, Any>
    ): YTStreamInfo? {
        val clientObj = JSONObject().apply {
            put("clientName", clientName)
            put("clientVersion", clientVersion)
            put("hl", "fr")
            put("gl", "FR")
            if (visitorData.isNotEmpty()) put("visitorData", visitorData)
            for ((k, v) in extraClientFields) put(k, v)
        }
        val body = JSONObject().apply {
            put("context", JSONObject().apply { put("client", clientObj) })
            put("videoId", videoId)
            put("contentCheckOk", true)
            put("racyCheckOk", true)
        }
        val reqBuilder = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
            .post(body.toString().toRequestBody(jsonMedia))
            .header("User-Agent", userAgent)
            .header("X-YouTube-Client-Name", clientId.toString())
            .header("X-YouTube-Client-Version", clientVersion)
            .header("Origin", "https://www.youtube.com")
        if (visitorData.isNotEmpty()) {
            reqBuilder.header("X-Goog-Visitor-Id", visitorData)
        }

        try {
            AppHttp.client.newCall(reqBuilder.build()).execute().use { resp ->
                if (!resp.isSuccessful) return null
                val raw = resp.body?.string() ?: return null
                val root = JSONObject(raw)
                val status = root.optJSONObject("playabilityStatus")?.optString("status") ?: ""
                if (status != "OK" && status.isNotEmpty()) return null
                val sd = root.optJSONObject("streamingData") ?: return null
                val hls = sd.optString("hlsManifestUrl").takeIf { it.isNotEmpty() }
                val formatsArr = sd.optJSONArray("formats")
                val progressive = mutableListOf<YTFormat>()
                if (formatsArr != null) {
                    for (i in 0 until formatsArr.length()) {
                        val f = formatsArr.optJSONObject(i) ?: continue
                        val u = f.optString("url")
                        val h = f.optInt("height", 0)
                        if (u.isNotEmpty() && h > 0) {
                            val label = f.optString("qualityLabel").ifEmpty { "${h}p" }
                            progressive.add(YTFormat(h, label, u))
                        }
                    }
                }
                val sortedProgressive = progressive
                    .sortedByDescending { it.height }
                    .distinctBy { it.height }
                if (hls != null || sortedProgressive.isNotEmpty()) {
                    return YTStreamInfo(hls, sortedProgressive, userAgent)
                }
            }
        } catch (_: Exception) {}
        return null
    }
}
