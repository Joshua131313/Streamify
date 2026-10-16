package com.streamify.app.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Message
import android.view.ViewGroup
import android.webkit.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import kotlinx.coroutines.*
import java.time.LocalDate
import java.time.Instant
import kotlin.coroutines.coroutineContext
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.streamify.app.LoadState
import com.streamify.app.StreamifyViewModel
import com.streamify.app.data.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MultiWatchScreen(vm: StreamifyViewModel) {
    var picker by remember { mutableStateOf(false) }
    var audible by remember { mutableStateOf(vm.multiWatch.firstOrNull()?.url) }
    val streams = vm.multiWatch.toList()
    LaunchedEffect(streams.map { it.url }) {
        if (audible != null && streams.none { it.url == audible }) audible = streams.firstOrNull()?.url
        if (streams.size == 1) audible = streams.first().url
    }
    Column(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
        Row(Modifier.fillMaxWidth().height(48.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = vm::back) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
            Text("Multi-watch", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            if (streams.size < 4) SecondaryButton(onClick = { picker = true }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
                Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Text("Game")
            }
        }
        // A single Layout keeps existing WebViews alive when the number of slots changes.
        Layout(modifier = Modifier.fillMaxWidth().weight(1f), content = {
            streams.forEach { stream -> key(stream.url) {
                MultiWatchPane(stream, { vm.multiWatch.remove(stream) }, Modifier.fillMaxSize(), stream.url == audible,
                    { audible = if (audible == stream.url) null else stream.url })
            } }
            if (streams.isEmpty() || streams.size == 3) Box(Modifier.fillMaxSize().padding(4.dp).clip(RoundedCornerShape(12.dp)).background(Panel), contentAlignment = Alignment.Center) {
                SecondaryButton(onClick = { picker = true }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Live games"); Icon(Icons.Rounded.KeyboardArrowDown, null)
                }
            }
        }) { measurables, constraints ->
            val columns = if (streams.size >= 3) 2 else 1
            val rows = if (streams.size >= 2) 2 else 1
            val width = constraints.maxWidth / columns
            val height = constraints.maxHeight / rows
            val children = measurables.map { it.measure(Constraints.fixed(width, height)) }
            layout(constraints.maxWidth, constraints.maxHeight) { children.forEachIndexed { index, child -> child.place((index % columns) * width, (index / columns) * height) } }
        }
    }
    if (picker) LiveGamePicker(vm, { picker = false }) { stream ->
        if (vm.multiWatch.isEmpty()) audible = stream.url
        vm.queueStream(stream); picker = false
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LiveGamePicker(vm: StreamifyViewModel, dismiss: () -> Unit, choose: (Stream) -> Unit) {
    var retry by remember { mutableIntStateOf(0) }
    var loadingGame by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val games by produceState(LoadState<List<Game>>(loading = true), retry) {
        value = LoadState(loading = true)
        try {
            val results = coroutineScope {
                // Include yesterday's late games and tomorrow's games near midnight.
                League.entries.flatMap { league -> (-1L..1L).map { offset -> async {
                    try { vm.repository.schedule(league, LocalDate.now().plusDays(offset)).games }
                    catch (_: Exception) { coroutineContext.ensureActive(); emptyList() }
                } } }.awaitAll().flatten()
            }
            val now = Instant.now()
            value = LoadState(results.distinctBy { it.key }.filter {
                it.live || (it.state == "pre" && parseTimestamp(it.date)?.let { start -> !start.isBefore(now.minusSeconds(900)) && !start.isAfter(now.plusSeconds(7200)) } == true)
            }.sortedWith(compareByDescending<Game> { it.live }.thenBy { it.date }))
        } catch (failure: Exception) { coroutineContext.ensureActive(); value = LoadState(error = failure.localizedMessage) }
    }
    ModalBottomSheet(onDismissRequest = dismiss) {
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Add a game", style = MaterialTheme.typography.titleLarge)
            Text("Live now or starting within two hours", color = Muted, style = MaterialTheme.typography.bodySmall)
            error?.let { Text(it, color = Muted) }
        }
        if (games.loading) Loading()
        else if (games.data.isNullOrEmpty()) Message("No live games found", games.error ?: "Check again closer to game time.", "Refresh", { retry++ })
        LazyColumn(Modifier.heightIn(max = 440.dp), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(games.data.orEmpty(), key = { it.key }) { game ->
                Surface(onClick = { if (loadingGame == null) { loadingGame = game.key; error = null; scope.launch {
                    try {
                        val stream = withTimeoutOrNull(30_000) { vm.repository.streams(game).firstOrNull() }
                        if (stream == null) error = "No stream available for this game yet. Try another game."
                        else if (vm.multiWatch.any { it.url == stream.url }) error = "This game is already playing."
                        else choose(stream.copy(label = "${game.away.abbreviation} vs ${game.home.abbreviation}"))
                    } catch (failure: Exception) { coroutineContext.ensureActive(); error = failure.localizedMessage }
                    finally { loadingGame = null }
                } } }, enabled = loadingGame == null, shape = RoundedCornerShape(14.dp), color = Panel) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        LeagueLogo(game.league, Modifier.size(32.dp))
                        Column(Modifier.weight(1f)) {
                            Text("${game.away.abbreviation} vs ${game.home.abbreviation}", style = MaterialTheme.typography.titleSmall)
                            Text(if (game.live) "Live · ${game.status}" else gameTime(game), color = Muted, style = MaterialTheme.typography.bodySmall)
                        }
                        if (loadingGame == game.key) CircularProgressIndicator(Modifier.size(20.dp), color = Muted, strokeWidth = 2.dp)
                        else Icon(Icons.Rounded.PlayArrow, null)
                    }
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun MultiWatchPane(stream: Stream, remove: () -> Unit, modifier: Modifier, audible: Boolean, toggleAudio: () -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var retry by remember { mutableIntStateOf(0) }
    var error by remember(retry) { mutableStateOf(false) }
    var dead by remember(retry) { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val currentAudible by rememberUpdatedState(audible)
    val web = remember(stream.url, retry) { WebView(context).apply {
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        settings.javaScriptEnabled = true; settings.domStorageEnabled = true
        settings.useWideViewPort = true; settings.loadWithOverviewMode = true
        setBackgroundColor(android.graphics.Color.BLACK)
        settings.allowFileAccess = false; settings.allowContentAccess = false
        settings.mediaPlaybackRequiresUserGesture = false
        settings.setSupportMultipleWindows(true)
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.userAgentString = settings.userAgentString.replace("; wv", "").replace("Version/4.0 ", "")
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    WebViewCompat.addDocumentStartJavaScript(this, sportsPdfCompatibilityScript, setOf("https://embed.st"))
            val host = Uri.parse(stream.url).host?.removePrefix("www.")
            if (host != null) WebViewCompat.addDocumentStartJavaScript(this, orientationCompatibilityScript, setOf("https://$host", "https://www.$host"))
        }
        webChromeClient = object : WebChromeClient() { override fun onCreateWindow(view: WebView?, dialog: Boolean, gesture: Boolean, result: Message?) = false }
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String?) { view.evaluateJavascript(multiWatchAudioUpdate(currentAudible && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)), null) }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.url.toString() != "about:blank" && (!httpsUrl(request.url.toString()) || request.isForMainFrame && request.url.host != Uri.parse(stream.url).host)
            override fun onReceivedError(view: WebView, request: WebResourceRequest, issue: WebResourceError) { if (request.isForMainFrame || request.url.toString() == stream.url) error = true }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean { dead = true; error = true; (view.parent as? ViewGroup)?.removeView(view); return true }
        }
        var loaded = false
        addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            if (!loaded && right > left && bottom > top) { loaded = true; loadUrl(stream.url) }
        }
    } }
    DisposableEffect(web, audible) {
        val script = if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
            WebViewCompat.addDocumentStartJavaScript(web, multiWatchAudioScript(audible), setOf("*")) else null
        if (!dead) web.evaluateJavascript(multiWatchAudioUpdate(audible), null)
        onDispose { script?.remove() }
    }
    DisposableEffect(web) {
        val observer = LifecycleEventObserver { _, event -> if (!dead) { if (event == Lifecycle.Event.ON_PAUSE) { web.evaluateJavascript(multiWatchAudioUpdate(false), null); web.onPause() }
            if (event == Lifecycle.Event.ON_RESUME) { web.onResume(); web.evaluateJavascript(multiWatchAudioUpdate(currentAudible), null) } } }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); (web.parent as? ViewGroup)?.removeView(web); if (!dead) web.stopLoading(); web.destroy() }
    }
    Column(modifier.padding(3.dp).clip(RoundedCornerShape(10.dp)).background(androidx.compose.ui.graphics.Color.Black)) {
        Row(Modifier.fillMaxWidth().height(44.dp).background(Panel).padding(start = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stream.label.substringBefore(" · "), Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
            IconButton(onClick = toggleAudio, modifier = Modifier.size(44.dp)) {
                Icon(if (audible) Icons.Rounded.VolumeUp else Icons.Rounded.VolumeOff, if (audible) "Mute stream" else "Listen to stream", Modifier.size(18.dp))
            }
            Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.size(44.dp)) { Icon(Icons.Rounded.MoreVert, "Stream options", Modifier.size(18.dp)) }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Fullscreen") }, onClick = { menu = false; context.startActivity(com.streamify.app.PlayerActivity.streamIntent(context, stream.label, stream.url)) })
                    DropdownMenuItem(text = { Text("Reload") }, onClick = { menu = false; retry++ })
                    DropdownMenuItem(text = { Text("Open in browser") }, onClick = { menu = false; runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(stream.url))) } })
                    DropdownMenuItem(text = { Text("Remove") }, onClick = { menu = false; remove() })
                }
            }
        }
        if (error) Text("Source unavailable. Use options to retry.", color = Muted, style = MaterialTheme.typography.labelSmall)
        if (!dead) key(web) { AndroidView(factory = { web }, modifier = Modifier.fillMaxWidth().weight(1f)) }
    }
}
