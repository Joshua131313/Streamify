package com.streamify.app.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.streamify.app.data.Media
import com.streamify.app.data.httpsUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.coroutineContext

val StreamRed = Color(0xFFFF454F)
val Canvas: Color @Composable get() = MaterialTheme.colorScheme.background
val Panel: Color @Composable get() = MaterialTheme.colorScheme.surfaceVariant
val Muted: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant

@Composable
fun StreamifyTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val activity = remember(context) {
        generateSequence(context) { (it as? android.content.ContextWrapper)?.baseContext }
            .filterIsInstance<android.app.Activity>().firstOrNull()
    }
    val prefs = remember { context.getSharedPreferences("streamify", android.content.Context.MODE_PRIVATE) }
    var setting by remember { mutableStateOf(prefs.getString("theme", "Dark")) }
    DisposableEffect(prefs) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { values, key -> if (key == "theme") setting = values.getString("theme", "Dark") }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    val dark = setting == "Dark" || setting == "System" && isSystemInDarkTheme()
    SideEffect {
        activity?.let { activity ->
            androidx.core.view.WindowCompat.getInsetsController(activity.window, activity.window.decorView).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    MaterialTheme(typography = Typography(labelLarge = MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp)), colorScheme = if (dark) darkColorScheme(primary = StreamRed, onPrimary = Color.White,
        secondary = Color(0xFFAFBFDA), background = Color(0xFF0B0D10), surface = Color(0xFF0B0D10), surfaceVariant = Color(0xFF161A20), onSurfaceVariant = Color(0xFF9BA4B5),
        onBackground = Color(0xFFF5F5F5), onSurface = Color(0xFFF5F5F5)) else lightColorScheme(primary = Color(0xFFBE2635), background = Color(0xFFF6F7FA), surface = Color(0xFFF6F7FA), surfaceVariant = Color.White, onSurfaceVariant = Color(0xFF576172)), content = content)
}

private val images = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap) = value.byteCount
}

@Composable
fun RemoteImage(url: String?, description: String?, modifier: Modifier = Modifier, scale: ContentScale = ContentScale.Crop) {
    val bitmap by produceState<Bitmap?>(null, url) {
        value = null
        if (url == null || !httpsUrl(url)) return@produceState
        value = images.get(url) ?: withContext(Dispatchers.IO) {
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                try {
                    connection.connectTimeout = 10_000; connection.readTimeout = 10_000
                    connection.inputStream.use { BitmapFactory.decodeStream(it) }?.also { images.put(url, it) }
                } finally { connection.disconnect() }
            } catch (_: Exception) { coroutineContext.ensureActive(); null }
        }
    }
    Box(modifier.background(Panel), contentAlignment = Alignment.Center) {
        bitmap?.let { Image(it.asImageBitmap(), description, Modifier.fillMaxSize(), contentScale = scale) }
            ?: Icon(Icons.Rounded.Theaters, description, Modifier.size(30.dp), tint = Muted.copy(alpha = .4f))
    }
}

@Composable
fun MediaPoster(media: Media, onClick: () -> Unit, modifier: Modifier = Modifier, roomy: Boolean = false) {
    Column(modifier.clickable(onClick = onClick)) {
        Box {
            RemoteImage(media.image(), media.title, Modifier.fillMaxWidth().aspectRatio(2f / 3).clip(RoundedCornerShape(if (roomy) 12.dp else 8.dp)))
            if (media.rating > 0) Surface(Modifier.align(Alignment.TopEnd).padding(6.dp), color = Canvas.copy(alpha = .9f), shape = RoundedCornerShape(5.dp)) {
                Text("★ %.1f".format(media.rating), Modifier.padding(horizontal = 6.dp, vertical = 3.dp), style = MaterialTheme.typography.labelSmall)
            }
        }
        Text(media.title, Modifier.padding(top = if (roomy) 10.dp else 6.dp), maxLines = if (roomy) 2 else 1, overflow = TextOverflow.Ellipsis, fontSize = if (roomy) 13.sp else 12.sp, lineHeight = if (roomy) 18.sp else 16.sp, fontWeight = FontWeight.Medium)
        Text(listOf(media.year, media.type.label).filter { it.isNotBlank() }.joinToString(" · "), Modifier.padding(top = if (roomy) 4.dp else 0.dp), color = Muted, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
fun MediaShelf(title: String, media: List<Media>, onSelect: (Media) -> Unit) {
    if (media.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (title.isNotBlank()) Text(title, Modifier.padding(horizontal = 16.dp), fontSize = 18.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold)
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(media, key = { it.key }) { item -> MediaPoster(item, { onSelect(item) }, Modifier.width(112.dp)) }
        }
    }
}

@Composable
fun Loading(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(36.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.dp) }
}

@Composable
fun Message(title: String, body: String, action: String? = null, onAction: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(Icons.Rounded.LiveTv, null, Modifier.size(36.dp), tint = Muted)
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Text(body, color = Muted, style = MaterialTheme.typography.bodyMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (action != null) SecondaryButton(onClick = onAction, modifier = Modifier.heightIn(min = 48.dp)) { Text(action) }
    }
}

@Composable
fun ErrorBanner(text: String, retry: () -> Unit) {
    Surface(color = Panel, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = Muted)
            SecondaryButton(onClick = retry) { Text("Retry") }
        }
    }
}
