package com.mediahub.spotify

import com.mediahub.core.AppHttp
import okhttp3.Request
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

object DeezerStreamProxy {
    private var serverSocket: ServerSocket? = null
    private var port: Int = 0
    private val pool = Executors.newCachedThreadPool()
    private val trackUrls = ConcurrentHashMap<String, String>()
    private val trackSizes = ConcurrentHashMap<String, Long>()

    @Synchronized
    fun ensureStarted(): Int {
        if (port > 0 && serverSocket != null) return port
        val ss = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        serverSocket = ss
        port = ss.localPort
        pool.submit {
            while (!ss.isClosed) {
                try {
                    val client = ss.accept()
                    pool.submit { handleClient(client) }
                } catch (_: Exception) {}
            }
        }
        return port
    }

    fun register(trackId: String, cdnUrl: String): String {
        val p = ensureStarted()
        trackUrls[trackId] = cdnUrl
        return "http://127.0.0.1:$p/track/$trackId.mp3"
    }

    private fun handleClient(socket: Socket) {
        socket.use { s ->
            val input = s.getInputStream().bufferedReader()
            val firstLine = input.readLine() ?: return
            val parts = firstLine.split(" ")
            if (parts.size < 2) return
            val method = parts[0]
            val trackId = parts[1].removePrefix("/track/").removeSuffix(".mp3")
            val cdnUrl = trackUrls[trackId] ?: run {
                s.getOutputStream().write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".toByteArray())
                return
            }

            var rangeStart = 0L
            var rangeEnd: Long? = null
            var hasRange = false
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
                if (line.lowercase().startsWith("range: bytes=")) {
                    hasRange = true
                    val r = line.substringAfter("=").trim().split("-")
                    rangeStart = r[0].toLongOrNull() ?: 0L
                    if (r.size > 1 && r[1].isNotEmpty()) rangeEnd = r[1].toLongOrNull()
                }
            }

            val totalSize = trackSizes[trackId] ?: run {
                val headReq = Request.Builder().url(cdnUrl).head().build()
                val sz = AppHttp.client.newCall(headReq).execute().use { r ->
                    r.header("Content-Length")?.toLongOrNull() ?: 0L
                }
                if (sz > 0) trackSizes[trackId] = sz
                sz
            }

            val out = s.getOutputStream()
            if (method == "HEAD") {
                val hdr = "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\nContent-Length: $totalSize\r\nConnection: close\r\n\r\n"
                out.write(hdr.toByteArray())
                return
            }

            val alignedStart = (rangeStart / 2048L) * 2048L
            val effEnd = rangeEnd ?: if (totalSize > 0) totalSize - 1 else alignedStart + 524_287L
            val alignedEnd = if (totalSize > 0) minOf(totalSize - 1, ((effEnd / 2048L) + 1) * 2048L - 1) else effEnd

            var encBytes: ByteArray? = null
            for (attempt in 0 until 3) {
                try {
                    val fetchReq = Request.Builder().url(cdnUrl).header("Range", "bytes=$alignedStart-$alignedEnd").build()
                    AppHttp.client.newCall(fetchReq).execute().use { resp ->
                        if (resp.isSuccessful) {
                            val b = resp.body?.bytes()
                            if (b != null && b.isNotEmpty()) {
                                encBytes = b
                            }
                        }
                    }
                    if (encBytes != null) break
                } catch (_: Exception) {}
                if (attempt < 2) Thread.sleep(250L * (attempt + 1))
            }

            val validEnc = encBytes ?: run {
                out.write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
                return
            }
            val decrypted = decryptStripes(validEnc, trackId, (alignedStart / 2048L).toInt())

            val skip = (rangeStart - alignedStart).toInt().coerceAtLeast(0)
            val want = (effEnd - rangeStart + 1).toInt().coerceAtLeast(0)
            val sliceEnd = minOf(decrypted.size, skip + want)
            val body = if (skip < sliceEnd) decrypted.copyOfRange(skip, sliceEnd) else ByteArray(0)

            val hdr = StringBuilder()
            if (hasRange && totalSize > 0) {
                hdr.append("HTTP/1.1 206 Partial Content\r\n")
                hdr.append("Content-Range: bytes $rangeStart-${rangeStart + body.size - 1}/$totalSize\r\n")
            } else {
                hdr.append("HTTP/1.1 200 OK\r\n")
            }
            hdr.append("Content-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n")
            out.write(hdr.toString().toByteArray())
            out.write(body)
            out.flush()
        }
    }

    fun decryptStripes(data: ByteArray, trackId: String, startChunkIndex: Int = 0): ByteArray {
        val key = deriveKey(trackId)
        val iv = byteArrayOf(0, 1, 2, 3, 4, 5, 6, 7)
        val cipher = Cipher.getInstance("Blowfish/CBC/NoPadding")
        val keySpec = SecretKeySpec(key, "Blowfish")
        val ivSpec = IvParameterSpec(iv)

        val out = ByteArrayOutputStream(data.size)
        var offset = 0
        var chunk = startChunkIndex
        while (offset < data.size) {
            val end = minOf(offset + 2048, data.size)
            val len = end - offset
            if (chunk % 3 == 0 && len == 2048) {
                cipher.init(Cipher.DECRYPT_MODE, keySpec, ivSpec)
                out.write(cipher.doFinal(data, offset, len))
            } else {
                out.write(data, offset, len)
            }
            offset = end
            chunk++
        }
        return out.toByteArray()
    }

    private fun deriveKey(trackId: String): ByteArray {
        val md5 = MessageDigest.getInstance("MD5").digest(trackId.toByteArray())
        val hex = md5.joinToString("") { "%02x".format(it) }.toByteArray()
        val secret = "g4el58wc0zvf9na1".toByteArray()
        return ByteArray(16) { i -> (hex[i].toInt() xor hex[i + 16].toInt() xor secret[i].toInt()).toByte() }
    }
}
