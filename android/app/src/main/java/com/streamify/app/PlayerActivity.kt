package com.streamify.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.zIndex
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.streamify.app.data.*
import com.streamify.app.ui.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import org.json.JSONObject
import kotlin.coroutines.coroutineContext

class PlayerActivity : ComponentActivity() {
    private var pip by mutableStateOf(false)
    private var playbackActive = false
    private var suppressAutoPip = false
    private var playbackCommand: ((Boolean) -> Unit)? = null
    private val pipReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                "$packageName.PIP_PLAY" -> playbackCommand?.invoke(true)
                "$packageName.PIP_PAUSE" -> playbackCommand?.invoke(false)
            }
        }
    }
    private fun pipParams(): android.app.PictureInPictureParams {
        val playing = playbackActive
        val builder = android.app.PictureInPictureParams.Builder().setAspectRatio(android.util.Rational(16, 9))
        val command = Intent(if (playing) "$packageName.PIP_PAUSE" else "$packageName.PIP_PLAY").setPackage(packageName)
        val pending = android.app.PendingIntent.getBroadcast(this, 0, command, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        val label = if (playing) "Pause" else "Play"
        val action = android.app.RemoteAction(android.graphics.drawable.Icon.createWithResource(this, if (playing) R.drawable.pip_pause else R.drawable.pip_play), label, label, pending)
        action.isEnabled = playbackCommand != null
        builder.setActions(listOf(action))
        if (android.os.Build.VERSION.SDK_INT >= 31) builder.setAutoEnterEnabled(playing && !suppressAutoPip).setSeamlessResizeEnabled(true)
        return builder.build()
    }
    override fun onDestroy() {
        unregisterReceiver(pipReceiver)
        playbackCommand = null
        super.onDestroy()
    }
    private fun configurePip(playing: Boolean) {
        playbackActive = playing
        if (!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        runCatching { setPictureInPictureParams(pipParams()) }
    }
    private fun enterPip() {
        if (!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val entered = runCatching { enterPictureInPictureMode(pipParams()) }.getOrDefault(false)
        if (!entered) android.widget.Toast.makeText(this, "Allow picture-in-picture for Streamify in Android settings.", android.widget.Toast.LENGTH_LONG).show()
    }
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (android.os.Build.VERSION.SDK_INT < 31 && playbackActive && !suppressAutoPip) enterPip()
    }
    override fun onPictureInPictureModeChanged(inPip: Boolean, configuration: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(inPip, configuration)
        pip = inPip
    }

    private var playerTouch: (() -> Unit)? = null
    private var playerZoom: ((Float) -> Unit)? = null
    private var pinching = false
    private val scaleDetector by lazy { android.view.ScaleGestureDetector(this, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: android.view.ScaleGestureDetector): Boolean {
            playerZoom?.invoke(detector.scaleFactor); return true
        }
    }).apply { isQuickScaleEnabled = false; isStylusScaleEnabled = false } }
    override fun dispatchTouchEvent(event: android.view.MotionEvent): Boolean {
        if (event.actionMasked == android.view.MotionEvent.ACTION_DOWN) playerTouch?.invoke()
        if (playerZoom != null) {
            if (event.actionMasked == android.view.MotionEvent.ACTION_POINTER_DOWN && event.pointerCount == 2) {
                pinching = true
                android.view.MotionEvent.obtain(event).also { it.action = android.view.MotionEvent.ACTION_CANCEL; super.dispatchTouchEvent(it); it.recycle() }
            }
            scaleDetector.onTouchEvent(event)
            if (pinching) {
                if (event.actionMasked == android.view.MotionEvent.ACTION_UP || event.actionMasked == android.view.MotionEvent.ACTION_CANCEL) pinching = false
                return true
            }
        }
        return super.dispatchTouchEvent(event)
    }

    companion object {
        fun mediaIntent(context: Context, media: Media, season: Int, episode: Int, provider: String) = Intent(context, PlayerActivity::class.java)
            .putExtra("media", media.json().toString()).putExtra("season", season).putExtra("episode", episode).putExtra("provider", provider)
        fun gameIntent(context: Context, game: Game) = Intent(context, PlayerActivity::class.java).putExtra("game", game)
        fun streamIntent(context: Context, title: String, url: String, chatRoom: String? = null) = Intent(context, PlayerActivity::class.java).putExtra("title", title).putExtra("url", url).putExtra("chatRoom", chatRoom)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.content.ContextCompat.registerReceiver(this, pipReceiver, android.content.IntentFilter().apply {
            addAction("$packageName.PIP_PLAY"); addAction("$packageName.PIP_PAUSE")
        }, androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED)
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)
        val store = LocalStore(this)
        val media = intent.getStringExtra("media")?.let { runCatching { Media.parse(JSONObject(it)) }.getOrNull() }
        @Suppress("DEPRECATION")
        val game = intent.getSerializableExtra("game") as? Game
        setContent { StreamifyTheme { if (game != null) GamePlayer(store, game) else Player(store, media) } }
    }

    @Composable
    private fun GamePlayer(store: LocalStore, game: Game) {
        val repository = remember { StreamifyRepository(store) }
        var retry by remember { mutableIntStateOf(0) }
        val state by produceState(LoadState<List<Stream>>(loading = true), game.key, retry) {
            value = LoadState(loading = true)
            try {
                val sources = kotlinx.coroutines.withTimeoutOrNull(30_000) { repository.streams(game) }
                value = if (sources == null) LoadState(error = "Finding streams timed out. Please retry.") else LoadState(sources)
            } catch (failure: Exception) { coroutineContext.ensureActive(); value = LoadState(error = failure.localizedMessage ?: "Streams unavailable.") }
        }
        val streams = state.data.orEmpty()
        if (streams.isNotEmpty()) Player(store, null, game, streams)
        else Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding()) {
                ScreenHeading("${game.away.abbreviation} vs ${game.home.abbreviation}", ::finish)
                if (state.loading) { Loading(); Text("Finding streams…", Modifier.padding(20.dp)) }
                else Message("No stream available", state.error ?: "Sources usually appear near game time.", "Try again", { retry++ })
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun Player(store: LocalStore, media: Media?, game: Game? = null, streams: List<Stream> = emptyList()) {
        var sourceIndex by rememberSaveable { mutableIntStateOf(0) }
        var sourcePicker by remember { mutableStateOf(false) }
        var options by remember { mutableStateOf(false) }
        var providerId by rememberSaveable { mutableStateOf(intent.getStringExtra("provider") ?: store.serverId) }
        val provider = store.servers.firstOrNull { it.id == providerId } ?: store.servers.first()
        var season by rememberSaveable { mutableIntStateOf(intent.getIntExtra("season", 1)) }
        var episode by rememberSaveable { mutableIntStateOf(intent.getIntExtra("episode", 1)) }
        var generation by remember { mutableIntStateOf(0) }
        var preferEmbed by rememberSaveable { mutableStateOf(true) }
        // Stream providers reject being nested. Restored movie/embed state must never wrap sports.
        val embedded = media != null && preferEmbed
        val url = media?.let { provider.url(it, season, episode) } ?: streams.getOrNull(sourceIndex)?.url ?: streams.firstOrNull()?.url ?: intent.getStringExtra("url").orEmpty()
        val title = media?.title ?: game?.let { "${it.away.abbreviation} vs ${it.home.abbreviation}" } ?: intent.getStringExtra("title").orEmpty()
        var error by remember(url, generation, embedded) { mutableStateOf<String?>(null) }
        var loading by remember(url, generation, embedded) { mutableStateOf(true) }
        var slow by remember(url, generation, embedded) { mutableStateOf(false) }
        var fullscreen by remember { mutableStateOf<View?>(null) }
        var expanded by remember { mutableStateOf(false) }
        val immersive = expanded || fullscreen != null
        var zoom by remember(url) { mutableFloatStateOf(1f) }
        var fill by remember(url) { mutableStateOf<VideoFill?>(null) }
        var videoSize by remember { mutableStateOf(IntSize.Zero) }
        var controlsVisible by remember { mutableStateOf(true) }
        var interaction by remember { mutableIntStateOf(0) }
        LaunchedEffect(immersive, interaction) {
            controlsVisible = true
            if (immersive) { delay(3_000); controlsVisible = false }
        }
        DisposableEffect(immersive) {
            playerTouch = { interaction++ }
            playerZoom = if (immersive) ({ factor: Float -> fill = null; zoom = (zoom * factor).coerceIn(1f, 4f); interaction++ }) else null
            onDispose { playerTouch = null; playerZoom = null; pinching = false }
        }
        val originalOrientation = remember { requestedOrientation }
        var callback by remember { mutableStateOf<WebChromeClient.CustomViewCallback?>(null) }
        var dead by remember(url, generation, embedded) { mutableStateOf(false) }
        var picker by remember { mutableStateOf(false) }
        var chatOpen by remember { mutableStateOf(false) }
        val chatRoom = game?.let(::chatRoomId) ?: intent.getStringExtra("chatRoom")
        var pickerSeason by remember { mutableIntStateOf(season) }
        val repo = remember { StreamifyRepository(store) }
        val details by produceState<Details?>(null, media?.key) {
            if (media?.type == MediaType.TV) try { value = repo.details(media) } catch (_: Exception) { coroutineContext.ensureActive() }
        }
        val episodes by produceState<List<Episode>>(emptyList(), media?.key, season, pickerSeason, picker) {
            value = emptyList()
            if (media?.type == MediaType.TV) try { value = repo.episodes(media.id, if (picker) pickerSeason else season) } catch (_: Exception) { coroutineContext.ensureActive() }
        }
        fun leaveFullscreen() {
            expanded = false
            zoom = 1f
            fill = null
            val oldCallback = callback
            callback = null
            (fullscreen?.parent as? ViewGroup)?.removeView(fullscreen)
            fullscreen = null
            oldCallback?.onCustomViewHidden()
        }
        fun close() { configurePip(false); leaveFullscreen(); finish() }
        fun retry() { leaveFullscreen(); generation++ }
        LaunchedEffect(url, generation, embedded) { delay(20_000); slow = true }
        LaunchedEffect(media?.key, season, episode) {
            media?.let { item -> AccountRepository.get(this@PlayerActivity).record(item, season, episode) }
        }
        DisposableEffect(immersive, pip) {
            val bars = WindowCompat.getInsetsController(window, window.decorView)
            // WebView can register its own Back callback. Native fullscreen must exit first.
            val fullscreenBack = if (immersive && android.os.Build.VERSION.SDK_INT >= 33) {
                android.window.OnBackInvokedCallback { leaveFullscreen() }.also {
                    onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY, it)
                }
            } else null
            if (immersive || pip) {
                bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                bars.hide(WindowInsetsCompat.Type.systemBars())
                if (!pip) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            } else {
                bars.show(WindowInsetsCompat.Type.systemBars())
                requestedOrientation = originalOrientation
            }
            onDispose {
                if (android.os.Build.VERSION.SDK_INT >= 33 && fullscreenBack != null) onBackInvokedDispatcher.unregisterOnBackInvokedCallback(fullscreenBack)
                bars.show(WindowInsetsCompat.Type.systemBars())
                requestedOrientation = originalOrientation
            }
        }
        val accounts = remember { AccountRepository.get(this@PlayerActivity) }
        val progressOwner = remember(media?.key, season, episode) { accounts.auth.currentUser?.takeUnless { it.isAnonymous }?.uid }
        val progress = remember(media?.key, season, episode) {
            media?.let { item -> PlaybackCheckpoint(History(item, season, episode), save = { entry, cloud -> accounts.savePlayback(entry, progressOwner, cloud) }) }
        }
        // Native fullscreen also works when a provider's own button is unavailable.
        val web = remember(url, generation, embedded) {
            WebView(this).apply {
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                setBackgroundColor(android.graphics.Color.BLACK)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                settings.mediaPlaybackRequiresUserGesture = false
                settings.setSupportMultipleWindows(true)
                settings.javaScriptCanOpenWindowsAutomatically = false
                settings.userAgentString = settings.userAgentString.replace("; wv", "").replace("Version/4.0 ", "")
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    WebViewCompat.addDocumentStartJavaScript(this, sportsPdfCompatibilityScript, setOf("https://embed.st"))
                    val host = Uri.parse(url).host?.removePrefix("www.")
                    if (host != null) WebViewCompat.addDocumentStartJavaScript(this, orientationCompatibilityScript, setOf("https://$host", "https://www.$host"))
                }
                if (media != null && progress != null && WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    val origin = Uri.parse(url).let { "${it.scheme}://${it.authority}" }
                    val allowed = setOf(origin)
                    val previous = accounts.store.history.firstOrNull { it.media.key == media.key && it.season == season && it.episode == episode }
                    WebViewCompat.addWebMessageListener(this, "StreamifyProgress", allowed) { _, message, sourceOrigin, _, _ ->
                        if (sourceOrigin.toString().trimEnd('/') == origin && !dead) {
                            val raw = runCatching { message.data }.getOrNull()
                            if (raw != null && raw.length <= 1024) runCatching {
                                val sample = JSONObject(raw)
                                progress.sample(sample.getDouble("position"), sample.getDouble("duration"), sample.optBoolean("force"))
                            }
                        }
                    }
                    WebViewCompat.addDocumentStartJavaScript(this, playbackProgressScript(previous?.takeIf { it.resumable }?.positionSeconds ?: 0.0), allowed)
                }
                if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    val origin = Uri.parse(url).let { "${it.scheme}://${it.authority}" }
                    WebViewCompat.addWebMessageListener(this, "StreamifyPlaybackState", setOf(origin)) { _, message, sourceOrigin, _, reply ->
                        if (!dead && sourceOrigin.toString().trimEnd('/') == origin) {
                            playbackCommand = { play -> runCatching { reply.postMessage(if (play) "play" else "pause") } }
                            when (message.data) { "playing" -> configurePip(true); "paused" -> configurePip(false) }
                        }
                    }
                    WebViewCompat.addDocumentStartJavaScript(this, """
                        (() => {
                          let last = '';
                          window.StreamifyPlaybackState.onmessage = event => {
                            if (event.data !== 'play' && event.data !== 'pause') return;
                            const videos = Array.from(document.querySelectorAll('video'));
                            const video = videos.find(v => !v.paused && !v.ended) || videos.find(v => v.readyState >= 2);
                            if (!video) return;
                            if (event.data === 'pause') video.pause();
                            else { const result = video.play(); if (result) result.catch(() => {}); }
                          };
                          setInterval(() => {
                            const videos = Array.from(document.querySelectorAll('video'));
                            if (!videos.length) return;
                            const state = videos.some(v => !v.paused && !v.ended && v.readyState >= 2) ? 'playing' : 'paused';
                            if (state !== last) { last = state; window.StreamifyPlaybackState.postMessage(state); }
                          }, 500);
                        })();
                    """.trimIndent(), setOf(origin))
                }
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        val target = request.url.toString()
                        if (target == "about:blank") return false
                        if (!httpsUrl(target)) return true
                        // Provider frames may follow HTTPS CDN redirects. Advertising must
                        // never replace the host page or take over the native player.
                        val expectedHost = if (embedded) "appassets.androidplatform.net" else Uri.parse(url).host
                        return request.isForMainFrame && request.url.host?.removePrefix("www.") != expectedHost?.removePrefix("www.")
                    }
                    override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) { loading = true }
                    override fun onPageFinished(view: WebView, url: String?) { loading = false }
                    override fun onReceivedError(view: WebView, request: WebResourceRequest, issue: WebResourceError) {
                        if (request.isForMainFrame || request.url.toString() == url) { loading = false; error = "This source could not load. Retry, switch source, or open in browser." }
                    }
                    override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                        if (request.isForMainFrame || request.url.toString() == url) { loading = false; error = "Source returned HTTP ${response.statusCode}. Try another source." }
                    }
                    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                        leaveFullscreen(); dead = true; loading = false
                        error = "The video renderer stopped. Reload or choose another source."
                        (view.parent as? ViewGroup)?.removeView(view)
                        return true
                    }
                }
                webChromeClient = object : WebChromeClient() {
                    override fun onCreateWindow(view: WebView?, dialog: Boolean, gesture: Boolean, result: Message?) = false
                    override fun onShowCustomView(view: View, customCallback: CustomViewCallback) {
                        if (fullscreen != null) { customCallback.onCustomViewHidden(); return }
                        fullscreen = view; callback = customCallback
                    }
                    override fun onHideCustomView() { leaveFullscreen() }
                    override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                        if (BuildConfig.DEBUG) android.util.Log.d("StreamifyPlayer", "${message.messageLevel()}: ${message.message()}")
                        return true
                    }
                }
                var loaded = false
                addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
                    if (!loaded && right > left && bottom > top) {
                        loaded = true
                        if (!httpsUrl(url)) { loading = false; error = "Invalid player address." }
                        else if (embedded) loadDataWithBaseURL("https://appassets.androidplatform.net/player/", playerDocument(url), "text/html", "UTF-8", null)
                        else loadUrl(url)
                    }
                }
            }
        }
        fun snapToFill() {
            interaction++
            if (fill != null || zoom > 1.01f) { fill = null; zoom = 1f; return }
            if (dead) return
            val nativeFullscreen = fullscreen != null
            web.evaluateJavascript(videoGeometryScript) { result ->
                if (isFinishing || isDestroyed) return@evaluateJavascript
                val transform = runCatching {
                    val geometry = JSONObject(result)
                    val vw = videoSize.width.toFloat(); val vh = videoSize.height.toFloat()
                    if (nativeFullscreen) {
                        val aspect = geometry.getDouble("aspect").toFloat()
                        val w = minOf(vw, vh * aspect); val h = w / aspect
                        videoFill(vw, vh, (vw-w)/2, (vh-h)/2, w, h)
                    } else {
                        val sx = vw / geometry.getDouble("viewportWidth").toFloat()
                        val sy = vh / geometry.getDouble("viewportHeight").toFloat()
                        videoFill(vw, vh, geometry.getDouble("left").toFloat()*sx, geometry.getDouble("top").toFloat()*sy,
                            geometry.getDouble("width").toFloat()*sx, geometry.getDouble("height").toFloat()*sy)
                    }
                }.getOrNull()
                if (transform != null) { fill = transform; zoom = transform.scale; interaction++ }
                else android.widget.Toast.makeText(this@PlayerActivity, "This source doesn’t expose its video size. Pinch to zoom instead.", android.widget.Toast.LENGTH_LONG).show()
            }
        }
        DisposableEffect(web) {
            val observer = LifecycleEventObserver { _, event ->
                if (!dead) {
                    if (event == Lifecycle.Event.ON_PAUSE) progress?.flush()
                    if (event == Lifecycle.Event.ON_STOP && !isInPictureInPictureMode) web.onPause()
                    if (event == Lifecycle.Event.ON_RESUME) { web.onResume(); suppressAutoPip = false; configurePip(playbackActive) }
                }
            }
            lifecycle.addObserver(observer)
            onDispose {
                playbackCommand = null; configurePip(false); lifecycle.removeObserver(observer); progress?.flush(); leaveFullscreen()
                (web.parent as? ViewGroup)?.removeView(web)
                if (!dead) web.stopLoading()
                web.destroy()
            }
        }
        BackHandler { if (immersive) leaveFullscreen() else close() }
        Surface(color = Canvas) {
            Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().then(if (immersive || pip) Modifier else Modifier.systemBarsPadding())) {
                if (!immersive && !pip) {
                Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = ::close) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Close player") }
                    Column(Modifier.weight(1f).padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(title, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                        if (media?.type == MediaType.TV) Text("Season $season · Episode $episode", color = Muted, style = MaterialTheme.typography.labelSmall)
                    }
                    IconButton(onClick = { expanded = true }) { Icon(Icons.Rounded.Fullscreen, "Enter fullscreen") }
                    if (chatRoom != null) IconButton(onClick = { chatOpen = true }) { Icon(Icons.Rounded.ChatBubbleOutline, "Game chat") }
                    Box {
                        IconButton(onClick = { options = true }) { Icon(Icons.Rounded.MoreVert, "Player options") }
                        DropdownMenu(expanded = options, onDismissRequest = { options = false }) {
                            DropdownMenuItem(text = { Text("Picture-in-picture") }, leadingIcon = { Icon(Icons.Rounded.PictureInPictureAlt, null) }, onClick = { options = false; enterPip() })
                            DropdownMenuItem(text = { Text("Reload stream") }, leadingIcon = { Icon(Icons.Rounded.Refresh, null) }, onClick = { options = false; retry() })
                            if (media != null) DropdownMenuItem(text = { Text(if (embedded) "Use direct playback" else "Use embedded playback") }, leadingIcon = { Icon(Icons.Rounded.Tune, null) }, onClick = { options = false; leaveFullscreen(); preferEmbed = !preferEmbed })
                            DropdownMenuItem(text = { Text("Open in browser") }, leadingIcon = { Icon(Icons.Rounded.OpenInBrowser, null) }, onClick = {
                                options = false; suppressAutoPip = true; configurePip(playbackActive)
                                if (httpsUrl(url)) runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                            })
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (media != null || streams.isNotEmpty()) SecondaryButton(onClick = { sourcePicker = true }, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) {
                        Icon(Icons.Rounded.VideoSettings, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp))
                        Text(if (media != null) provider.label else "Stream ${sourceIndex + 1}")
                        Spacer(Modifier.width(6.dp)); Icon(Icons.Rounded.KeyboardArrowDown, "Choose source", Modifier.size(20.dp))
                    }
                    if (media?.type == MediaType.TV) IconButton(onClick = { pickerSeason = season; picker = true }) { Icon(Icons.Rounded.VideoLibrary, "Episodes") }
                    Spacer(Modifier.weight(1f))
                    if (loading) CircularProgressIndicator(Modifier.size(18.dp), color = Muted, strokeWidth = 2.dp)
                    IconButton(onClick = ::enterPip) { Icon(Icons.Rounded.PictureInPictureAlt, "Picture-in-picture", tint = Muted) }
                }
                error?.let { ErrorBanner(it, ::retry) }
                }
                Box(Modifier.fillMaxWidth().weight(1f).clipToBounds().onSizeChanged { videoSize = it }) {
                  Box(Modifier.fillMaxSize().graphicsLayer { scaleX = zoom; scaleY = zoom; translationX = fill?.offsetX ?: 0f; translationY = fill?.offsetY ?: 0f }) {
                    if (!dead) key(web) { AndroidView(factory = { web }, modifier = Modifier.fillMaxSize()) }
                    fullscreen?.let { video -> key(video) {
                        AndroidView(factory = { FrameLayout(it).apply { (video.parent as? ViewGroup)?.removeView(video); addView(video, FrameLayout.LayoutParams(-1, -1)) } }, modifier = Modifier.fillMaxSize())
                    } }
                }
                }
                if (!immersive && !pip && slow && loading) Text(if (slow) "Still blank? Choose another source or open in browser. The back arrow above always closes the player."
                    else "Tap the video to play. Availability depends on the selected source.", Modifier.padding(horizontal = 20.dp, vertical = 16.dp), style = MaterialTheme.typography.labelSmall, color = Muted)
            }
            AnimatedVisibility(visible = immersive && !pip && controlsVisible, modifier = Modifier.align(Alignment.TopEnd).zIndex(10f).displayCutoutPadding().padding(8.dp), enter = fadeIn(), exit = fadeOut()) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    FilledTonalButton(onClick = ::snapToFill,
                        colors = ButtonDefaults.filledTonalButtonColors(containerColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = .65f), contentColor = androidx.compose.ui.graphics.Color.White)) {
                        Icon(Icons.Rounded.ZoomIn, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                        Text(if (fill != null || zoom > 1.01f) "Fit screen" else "Fill screen")
                    }
                    IconButton(onClick = ::enterPip, colors = IconButtonDefaults.iconButtonColors(containerColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = .65f), contentColor = androidx.compose.ui.graphics.Color.White)) { Icon(Icons.Rounded.PictureInPictureAlt, "Picture-in-picture") }
                    IconButton(onClick = ::leaveFullscreen,
                        colors = IconButtonDefaults.iconButtonColors(containerColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = .65f), contentColor = androidx.compose.ui.graphics.Color.White)) {
                        Icon(Icons.Rounded.FullscreenExit, "Exit fullscreen")
                    }
                }
            }
            }
        }
        if (!pip && chatOpen && chatRoom != null) ModalBottomSheet(onDismissRequest = { chatOpen = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            Box(Modifier.fillMaxHeight(.85f).verticalScroll(rememberScrollState()).imePadding().padding(bottom = 24.dp)) {
                LiveChatRoom(chatRoom, AccountRepository.get(this@PlayerActivity)) {
                    startActivity(Intent(this@PlayerActivity, MainActivity::class.java).putExtra("openAccount", true))
                }
            }
        }
        if (!pip && sourcePicker) ModalBottomSheet(onDismissRequest = { sourcePicker = false }) {
            Text(if (media != null) "Playback source" else "Choose a stream", Modifier.padding(20.dp), style = MaterialTheme.typography.titleLarge)
            androidx.compose.foundation.lazy.LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (media != null) items(store.servers, key = { it.id }) { item ->
                    Surface(onClick = { leaveFullscreen(); providerId = item.id; store.serverId = item.id; sourcePicker = false }, modifier = Modifier.fillMaxWidth(), shape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp), color = Panel) {
                        Row(Modifier.padding(18.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.PlayCircleOutline, null, tint = Muted)
                            Text(item.label, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                            if (item.id == provider.id) Icon(Icons.Rounded.CheckCircle, "Selected source")
                        }
                    }
                }
                items(streams.size) { index ->
                    Surface(onClick = { leaveFullscreen(); sourceIndex = index; sourcePicker = false }, modifier = Modifier.fillMaxWidth(),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
                        color = if (sourceIndex == index) MaterialTheme.colorScheme.onSurface.copy(alpha = .10f) else Panel) {
                        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(Icons.Rounded.PlayCircleOutline, null, tint = Muted)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("Stream ${index + 1}", style = MaterialTheme.typography.titleSmall)
                                Text(streams[index].label, color = Muted, style = MaterialTheme.typography.bodySmall)
                            }
                            if (sourceIndex == index) Icon(Icons.Rounded.Check, "Selected stream")
                        }
                    }
                }
            }
        }
        if (!pip && picker) AlertDialog(onDismissRequest = { picker = false }, title = { Text("Choose an episode") }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) { items(details?.seasons.orEmpty()) { item -> FilterPill(item.name, item.number == pickerSeason, { pickerSeason = item.number }) } }
                androidx.compose.foundation.lazy.LazyColumn(Modifier.heightIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { items(episodes) { item ->
                    SecondaryButton(onClick = { season = pickerSeason; episode = item.number; picker = false; leaveFullscreen() }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("${item.number}. ${item.title}", Modifier.weight(1f)) }
                } }
            }
        }, confirmButton = { SecondaryButton(onClick = { picker = false }) { Text("Done") } })
    }
}
