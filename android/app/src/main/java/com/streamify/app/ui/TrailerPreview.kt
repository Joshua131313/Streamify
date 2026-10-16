package com.streamify.app.ui

import android.annotation.SuppressLint
import android.net.Uri
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TrailerPreview(url: String?, poster: String?, active: Boolean) {
    val context=LocalContext.current
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    var foreground by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(lifecycle) {
        val observer=LifecycleEventObserver { _,_ -> foreground=lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    val id=remember(url) { url?.let { Uri.parse(it).getQueryParameter("v") }?.takeIf { Regex("[A-Za-z0-9_-]{6,30}").matches(it) } }
    var playing by remember(id) { mutableStateOf(false) }
    var ended by remember(id) { mutableStateOf(false) }
    var failed by remember(id) { mutableStateOf(false) }
    var muted by remember(id) { mutableStateOf(true) }
    val shouldPlay=active && foreground
    val latestActive by rememberUpdatedState(shouldPlay)
    val web=remember(id) { if(id==null) null else WebView(context).apply {
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        settings.javaScriptEnabled=true;settings.domStorageEnabled=true;settings.mediaPlaybackRequiresUserGesture=false
        settings.allowFileAccess=false;settings.allowContentAccess=false
        webViewClient=object:WebViewClient() {
            override fun shouldOverrideUrlLoading(view:WebView,request:android.webkit.WebResourceRequest)=request.isForMainFrame
            override fun onPageFinished(view:WebView,url:String?) { view.evaluateJavascript("window.wanted=${latestActive}; window.control&&control();",null) }
        }
        loadDataWithBaseURL("https://com.streamify.app/", """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body,#p{margin:0;width:100%;height:100%;background:#000;overflow:hidden}</style></head><body><div id="p"></div><script>
        var p,wanted=false,previewState=-2;function control(){if(!p||!p.playVideo)return;if(wanted)p.playVideo();else p.pauseVideo();}
        function onYouTubeIframeAPIReady(){p=new YT.Player('p',{videoId:'$id',playerVars:{playsinline:1,controls:0,rel:0,origin:'https://com.streamify.app'},events:{onReady:function(){p.mute();control();},onStateChange:function(e){previewState=e.data;},onError:function(){previewState=-9;},onAutoplayBlocked:function(){previewState=-9;}}});}
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>""", "text/html","UTF-8",null)
    } }
    DisposableEffect(web) { onDispose { web?.loadUrl("about:blank");web?.destroy() } }
    LaunchedEffect(web,shouldPlay) { web?.evaluateJavascript("window.wanted=$shouldPlay;window.control&&control();",null) }
    LaunchedEffect(web) { if(web!=null) while(true) {
        web.evaluateJavascript("window.previewState") { raw -> when(raw) { "1" -> {playing=true;ended=false}; "0" -> {playing=false;ended=true}; "-9" -> {failed=true;playing=false} } }
        delay(500)
    } }
    Box(Modifier.fillMaxWidth().height(240.dp)) {
        RemoteImage(poster,null,Modifier.fillMaxSize())
        if(web!=null && !failed) AndroidView(factory={web},modifier=Modifier.fillMaxSize().graphicsLayer { alpha=if(playing) 1f else 0f })
        Box(Modifier.matchParentSize().pointerInput(Unit) { awaitPointerEventScope { while(true) awaitPointerEvent() } })
        if(ended) SecondaryButton(onClick={ ended=false;web?.evaluateJavascript("p.seekTo(0,true);p.playVideo();",null) },modifier=Modifier.align(Alignment.Center)) { Icon(Icons.Rounded.Replay,null);Text("Replay") }
        if(playing) FilledIconButton(onClick={muted=!muted;web?.evaluateJavascript(if(muted) "p.mute();" else "p.unMute();",null)},modifier=Modifier.align(Alignment.BottomEnd).padding(12.dp),colors=IconButtonDefaults.filledIconButtonColors(containerColor=Color(0xCC292B30),contentColor=Color.White)) { Icon(if(muted) Icons.Rounded.VolumeOff else Icons.Rounded.VolumeUp,if(muted) "Unmute trailer" else "Mute trailer") }
    }
}
