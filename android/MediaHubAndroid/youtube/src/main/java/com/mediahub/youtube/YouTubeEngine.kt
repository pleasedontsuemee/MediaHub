package com.mediahub.youtube

import com.mediahub.core.AppHttp
import kotlinx.coroutines.Dispatchers
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
    val progressiveFormats: List<YTFormat>
)

object YouTubeEngine {
    private val jsonMedia = "application/json".toMediaType()

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

    suspend fun resolveStreamInfo(videoId: String): YTStreamInfo? = withContext(Dispatchers.IO) {
        val body = JSONObject().apply {
            put("context", JSONObject().apply {
                put("client", JSONObject().apply {
                    put("clientName", "IOS")
                    put("clientVersion", "20.10.4")
                    put("deviceMake", "Apple")
                    put("deviceModel", "iPhone16,2")
                    put("osName", "iPhone")
                    put("osVersion", "18.3.1.22D72")
                    put("hl", "fr")
                    put("gl", "FR")
                })
            })
            put("videoId", videoId)
        }
        val req = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
            .post(body.toString().toRequestBody(jsonMedia))
            .header("User-Agent", "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_1 like Mac OS X;)")
            .build()

        try {
            AppHttp.client.newCall(req).execute().use { resp ->
                val raw = resp.body?.string() ?: return@withContext null
                val sd = JSONObject(raw).optJSONObject("streamingData") ?: return@withContext null
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
                    return@withContext YTStreamInfo(hls, sortedProgressive)
                }
            }
        } catch (_: Exception) {}
        null
    }
}
