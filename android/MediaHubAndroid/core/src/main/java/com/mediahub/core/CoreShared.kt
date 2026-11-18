package com.mediahub.core

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.flow.MutableSharedFlow
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

object CrossoverBus {
    val openSwitcherEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 4)
    fun requestSwitcher() {
        openSwitcherEvents.tryEmit(Unit)
    }
}

@Composable
fun rememberIsTablet(): Boolean {
    val cfg = LocalConfiguration.current
    return cfg.screenWidthDp >= 600
}

@Composable
fun rememberAdaptiveColumns(phoneCols: Int = 1, tabletCols: Int = 3): Int {
    val cfg = LocalConfiguration.current
    return if (cfg.screenWidthDp >= 900) tabletCols + 1 else if (cfg.screenWidthDp >= 600) tabletCols else phoneCols
}

fun Context.findActivity(): Activity? {
    var ctx = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

fun Context.setLandscapeMode(landscape: Boolean) {
    findActivity()?.requestedOrientation = if (landscape) {
        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    } else {
        ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }
}

@Composable
fun Modifier.adaptiveHomeTabGesture(
    isHome: Boolean,
    onTap: () -> Unit
): Modifier {
    val haptic = LocalHapticFeedback.current
    return this.pointerInput(isHome) {
        detectTapGestures(
            onTap = { onTap() },
            onLongPress = {
                if (isHome) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    CrossoverBus.requestSwitcher()
                }
            }
        )
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun ExoVideoSurface(
    player: Player,
    zoomToFill: Boolean = false,
    modifier: Modifier = Modifier.fillMaxSize()
) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = false
                this.player = player
                resizeMode = if (zoomToFill) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
            }
        },
        update = { pv ->
            if (pv.player !== player) pv.player = player
            pv.resizeMode = if (zoomToFill) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
        },
        modifier = modifier
    )
}

object AppHttp {
    private val cookieStore = ConcurrentHashMap<String, MutableList<Cookie>>()

    val cookieJar = object : CookieJar {
        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            val host = url.host
            val list = cookieStore.getOrPut(host) { mutableListOf() }
            synchronized(list) {
                for (c in cookies) {
                    list.removeAll { it.name == c.name }
                    list.add(c)
                }
            }
        }

        override fun loadForRequest(url: HttpUrl): List<Cookie> {
            val out = mutableListOf<Cookie>()
            for ((domain, list) in cookieStore) {
                if (url.host == domain || url.host.endsWith(".$domain") || domain.endsWith(".${url.host}")) {
                    synchronized(list) { out.addAll(list) }
                }
            }
            return out
        }
    }

    fun setCookie(domain: String, name: String, value: String) {
        val list = cookieStore.getOrPut(domain) { mutableListOf() }
        synchronized(list) {
            list.removeAll { it.name == name }
            if (value.isNotEmpty()) {
                list.add(
                    Cookie.Builder()
                        .domain(domain)
                        .path("/")
                        .name(name)
                        .value(value)
                        .secure()
                        .build()
                )
            }
        }
    }

    val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
}
