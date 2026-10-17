package com.streamify.app.downloads

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.streamify.app.data.Media
import com.streamify.app.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.snap
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.semantics.*
import kotlin.math.roundToInt

fun openDownloads(context: Context) { context.startActivity(Intent(context,DownloadsActivity::class.java)) }

@Composable
fun DownloadButton(media: Media, season: Int = 0, episode: Int = 0, compact: Boolean = false, episodeTitle: String = "", thumbnail: String? = null) {
    val context=LocalContext.current
    val store=remember { DownloadStore.get(context) }
    val downloads by store.items.collectAsState()
    val key="${media.type.path}_${media.id}_${season}_$episode"
    val existing=downloads.firstOrNull { it.key==key }
    val action = { if(existing==null) { store.enqueue(media,season,episode,episodeTitle,thumbnail); android.widget.Toast.makeText(context,"Added to downloads",android.widget.Toast.LENGTH_SHORT).show() } else openDownloads(context) }
    val label=when(existing?.state) {
        "queued" -> "Queued"
        "resolving" -> "Preparing download"
        "downloading" -> if(existing.total>0) "Downloading · ${(existing.bytes.toDouble()/existing.total*100).toInt().coerceIn(0,100)}%" else "Downloading"
        "paused" -> "Download paused"
        "error","failed" -> "Download failed"
        "complete" -> "Downloaded"
        else -> if(season>0) "Download S$season E$episode" else "Download"
    }
    if(compact) IconButton(onClick=action,modifier=Modifier.semantics {contentDescription="$label · Episode $episode"}) { DownloadStatusIcon(existing) }
    else SecondaryButton(onClick=action,modifier=Modifier.fillMaxWidth().heightIn(min=50.dp)) { DownloadStatusIcon(existing);Spacer(Modifier.width(10.dp));Text(label) }
}

@Composable
fun DownloadStatusIcon(item: DownloadItem?, modifier: Modifier=Modifier) {
    val progress by animateFloatAsState(if(item!=null && item.total>0) (item.bytes.toDouble()/item.total).toFloat().coerceIn(0f,1f) else 0f,label="Download progress")
    Box(modifier.size(26.dp),contentAlignment=Alignment.Center) {
        when(item?.state) {
            "queued","resolving" -> CircularProgressIndicator(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.onSurface,strokeWidth=2.dp)
            "downloading","paused" -> {
                if(item.total>0 || item.state=="paused") CircularProgressIndicator(progress={progress},modifier=Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.onSurface,trackColor=Muted.copy(alpha=.3f),strokeWidth=2.dp,gapSize=0.dp)
                else CircularProgressIndicator(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.onSurface,strokeWidth=2.dp)
                Icon(if(item.state=="paused") Icons.Rounded.Pause else Icons.Rounded.Stop,null,Modifier.size(12.dp))
            }
            "complete" -> Icon(Icons.Rounded.DownloadDone,null)
            "error","failed" -> Icon(Icons.Rounded.Refresh,null)
            else -> Icon(Icons.Rounded.Download,null)
        }
    }
}

@Composable
fun DownloadsToolbarButton() {
    val context=LocalContext.current
    val downloads by remember {DownloadStore.get(context)}.items.collectAsState()
    val active=downloads.filter {it.state in listOf("queued","resolving","downloading")}
    IconButton(onClick={openDownloads(context)}) {
        Box(Modifier.size(30.dp)) {
            Icon(Icons.Rounded.Download,"Downloads",Modifier.align(Alignment.Center).size(24.dp))
            if(active.isNotEmpty()) Box(Modifier.align(Alignment.TopEnd).size(12.dp).background(MaterialTheme.colorScheme.background,CircleShape)) {
                val known=active.all {it.total>0}
                if(known) CircularProgressIndicator(progress={(active.sumOf {it.bytes}.toDouble()/active.sumOf {it.total}).toFloat().coerceIn(0f,1f)},modifier=Modifier.fillMaxSize(),color=StreamRed,strokeWidth=2.dp,gapSize=0.dp)
                else CircularProgressIndicator(Modifier.fillMaxSize(),color=StreamRed,strokeWidth=2.dp)
            }
        }
    }
}

class DownloadsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if(android.os.Build.VERSION.SDK_INT>=33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 700)
        setContent { StreamifyTheme { Surface(Modifier.fillMaxSize()) { DownloadsPage { finish() } } } }
    }
}

@Composable
fun DownloadsPage(back: (() -> Unit)? = null) {
    val context=LocalContext.current
    val online by remember { com.streamify.app.data.NetworkStatus.get(context).online }.collectAsState()
    val store=remember { DownloadStore.get(context) }
    val downloads by store.items.collectAsState()
    var selectedShow by rememberSaveable { mutableStateOf<Int?>(null) }
    var editing by rememberSaveable { mutableStateOf(false) }
    var browseEpisodes by rememberSaveable { mutableStateOf(false) }
    BackHandler(selectedShow!=null) { if(browseEpisodes) browseEpisodes=false else {selectedShow=null;editing=false} }
    val showTitle=downloads.firstOrNull { it.id==selectedShow && it.season>0 }?.title
    LaunchedEffect(showTitle) { if(showTitle==null) selectedShow=null }
    var legacyMessage by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        legacyMessage=withContext(Dispatchers.IO) {
            val prefs=context.getSharedPreferences("movie-download-test",Context.MODE_PRIVATE)
            val id=prefs.getLong("id",-1)
            if(id == -1L || prefs.getBoolean("migrated",false)) return@withContext ""
            runCatching {
                val manager=context.getSystemService(DownloadManager::class.java)
                manager.query(DownloadManager.Query().setFilterById(id)).use { c ->
                    if(!c.moveToFirst()) return@use ""
                    if(c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) != DownloadManager.STATUS_SUCCESSFUL) return@use "Your earlier Titanic test is still managed by Android. Reopen Downloads after it finishes to import it."
                    val item=DownloadItem("movie_597_0_0",597,"Titanic",state="complete")
                    val old=File(context.getExternalFilesDir(null),"titanic-download-test.mp4")
                    if(old.exists() && store.get(item.key)==null) {
                        val target=store.file(item.key)
                        check(store.directory.usableSpace>old.length()) { "Not enough room to import Titanic." }
                        old.copyTo(target,overwrite=true)
                        store.update(item.copy(bytes=target.length(),total=target.length()))
                        manager.remove(id)
                    }
                    prefs.edit().putBoolean("migrated",true).apply()
                    ""
                }
            }.getOrElse { "Could not import the earlier test download: ${it.localizedMessage}" }
        }
    }
    if(browseEpisodes && selectedShow!=null && online) {
        val vm:com.streamify.app.StreamifyViewModel=androidx.lifecycle.viewmodel.compose.viewModel()
        Box(Modifier.fillMaxSize().safeDrawingPadding()) {
            DetailScreen(Media(selectedShow!!,com.streamify.app.data.MediaType.TV,showTitle.orEmpty()),vm) {browseEpisodes=false}
        }
        return
    }
    LazyColumn(Modifier.fillMaxSize().safeDrawingPadding(),contentPadding=PaddingValues(bottom=24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { Row(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=12.dp),verticalAlignment=Alignment.CenterVertically) {
            if(back!=null || selectedShow!=null) IconButton(onClick={if(selectedShow!=null) {selectedShow=null;editing=false} else back?.invoke()}, colors=IconButtonDefaults.iconButtonColors(containerColor=Color.White.copy(alpha=.08f),contentColor=Color.White)) { Icon(Icons.Rounded.ArrowBack,"Back") }
            Text(showTitle ?: "Downloads",Modifier.weight(1f).padding(horizontal=12.dp),style=MaterialTheme.typography.titleLarge,maxLines=1,overflow=TextOverflow.Ellipsis)
            IconButton(onClick={editing=!editing}) { Icon(if(editing) Icons.Rounded.Check else Icons.Rounded.Edit,if(editing) "Done editing" else "Edit downloads") }
        } }
        if(!online) item { PagePanel(Modifier.padding(horizontal=20.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Rounded.CloudOff,null)
                Text("You’re offline",style=MaterialTheme.typography.titleMedium)
            }
            Text("Your downloaded movies and episodes are ready to watch. Browsing returns automatically when you reconnect.",color=Muted)
        } }
        item { Text("On this device · ${downloads.count { it.state=="complete" }} ready to watch",Modifier.padding(horizontal=20.dp),color=Muted) }
        if(legacyMessage.isNotBlank()) item { Column(Modifier.padding(horizontal=20.dp)) { Text(legacyMessage,color=Muted); SecondaryButton(onClick={context.startActivity(Intent(context,com.streamify.app.DownloadTestActivity::class.java))}) { Text("View earlier test download") } } }
        if(downloads.isEmpty()) item { Message("Your offline library", if(online) "Download a movie or an episode from its details page. Your saved videos will appear here, even without internet." else "No downloads saved yet. Connect to the internet to download movies and episodes for your next offline session.") }
        val groups=if(selectedShow==null) downloads.groupBy { if(it.season>0) "tv_${it.id}" else it.key }.values.sortedBy { it.first().title }
            else downloads.filter { it.id==selectedShow && it.season>0 }.sortedWith(compareBy({it.season},{it.episode})).map { listOf(it) }
        groups.forEach { group ->
            val entry=group.first()
            val series=selectedShow==null && entry.season>0
            if(selectedShow!=null && groups.firstOrNull { it.first().season==entry.season }?.first()?.key==entry.key) item(key="season_${entry.season}") { Text("Season ${entry.season}",Modifier.padding(horizontal=20.dp),style=MaterialTheme.typography.titleMedium) }
            item(key=if(series) "tv_${entry.id}" else entry.key) {
                CompactDownloadRow(group,series,selectedShow!=null,editing,online,
                    open={if(series) {selectedShow=entry.id;editing=false} else context.startActivity(Intent(context,OfflinePlayerActivity::class.java).putExtra("key",entry.key))},
                    delete={group.forEach { DownloadStore.command(context,"delete",it.key) }})
            }
        }
        if(selectedShow!=null) item(key="more_episodes") {
            Column(Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=16.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                Button(onClick={browseEpisodes=true},enabled=online,shape=CircleShape,
                    colors=ButtonDefaults.buttonColors(containerColor=Color.White,contentColor=Color.Black),
                    contentPadding=PaddingValues(horizontal=24.dp,vertical=12.dp)) {Text("View more episodes",style=MaterialTheme.typography.titleSmall)}
                if(!online) Text("Connect to the internet to browse more episodes",color=Muted,style=MaterialTheme.typography.bodySmall,modifier=Modifier.padding(top=8.dp))
            }
        }
    }
}

@Composable
private fun CompactDownloadRow(group: List<DownloadItem>, series: Boolean, episode: Boolean, editing: Boolean, online: Boolean, open: ()->Unit, delete: ()->Unit) {
    val item=group.first()
    val context=LocalContext.current
    val width=with(LocalDensity.current) { 76.dp.toPx() }
    var offset by remember(item.key) { mutableFloatStateOf(0f) }
    var dragging by remember { mutableStateOf(false) }
    val shift by animateFloatAsState(if(editing) -width else offset,if(dragging) snap() else tween(180),label="Reveal delete")
    val ready=group.all { it.state=="complete" }
    val bytes=group.sumOf { it.bytes };val total=group.sumOf { it.total }
    val active=item.state in listOf("queued","resolving","downloading")
    val status=when { !online && !ready -> "Waiting for connection"; ready -> "${bytes/1_000_000} MB"; series -> "${group.count { it.state=="complete" }}/${group.size} ready · ${bytes/1_000_000} MB"; item.state=="paused" -> "Paused · ${bytes/1_000_000} MB";item.state=="error" -> "Tap retry";item.state=="resolving" -> "Finding download…";item.state=="queued" -> "Queued";else -> "${bytes/1_000_000} / ${if(total>0) total/1_000_000 else "?"} MB" }
    Column(Modifier.padding(horizontal=16.dp)) {
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp))) {
            if(shift < -1f) Box(Modifier.align(Alignment.CenterEnd).width(76.dp).height(86.dp).background(Color(0xFF292929)).clickable(onClick=delete).semantics { contentDescription="Delete ${item.title}" },contentAlignment=Alignment.Center) {
                Icon(Icons.Rounded.Close,null,tint=Color.White)
            }
            Row(Modifier.offset { IntOffset(shift.roundToInt(),0) }.fillMaxWidth().background(MaterialTheme.colorScheme.surface)
                .draggable(rememberDraggableState { offset=(offset+it).coerceIn(-width,0f) },Orientation.Horizontal,enabled=!editing,onDragStarted={dragging=true},onDragStopped={dragging=false;offset=if(offset < -width/3) -width else 0f})
                .semantics { customActions=listOf(CustomAccessibilityAction("Show delete") {offset=-width;true}) }
                .clickable(enabled=series || ready) { if(offset<0) offset=0f else open() }
                .padding(vertical=6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(112.dp).height(70.dp).clip(RoundedCornerShape(4.dp)),contentAlignment=Alignment.Center) {
                    RemoteImage(item.poster,null,Modifier.fillMaxSize())
                    if(ready && !series) Surface(shape=CircleShape,color=Color.Black.copy(alpha=.65f),border=androidx.compose.foundation.BorderStroke(1.dp,Color.White)) { Icon(Icons.Rounded.PlayArrow,"Watch offline",Modifier.padding(7.dp).size(22.dp),tint=Color.White) }
                }
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(5.dp)) {
                    Text(if(episode) "${item.episode}. ${item.episodeTitle.ifBlank { "Episode ${item.episode}" }}" else item.title,style=MaterialTheme.typography.titleSmall,maxLines=2,overflow=TextOverflow.Ellipsis)
                    Text(if(series) "${group.size} episode${if(group.size==1) "" else "s"} · $status" else status,style=MaterialTheme.typography.bodySmall,color=Muted,maxLines=1,overflow=TextOverflow.Ellipsis)
                    if(!ready) LinearProgressIndicator(progress={if(total>0) (bytes.toFloat()/total).coerceIn(0f,1f) else 0f},modifier=Modifier.fillMaxWidth().height(3.dp),color=StreamRed,trackColor=Muted.copy(alpha=.25f),gapSize=0.dp,strokeCap=StrokeCap.Butt,drawStopIndicator={})
                }
                if(series) Icon(Icons.Rounded.ChevronRight,"View episodes",Modifier.padding(end=8.dp))
                else if(ready) Icon(Icons.Rounded.DownloadDone,"Downloaded",Modifier.padding(end=8.dp).size(24.dp))
                else IconButton(enabled=active || online,onClick={DownloadStore.command(context,if(active) "pause" else "resume",item.key)}) {Box(Modifier.semantics {contentDescription=if(active) "Pause download" else "Resume download"}) {DownloadStatusIcon(item)}}
            }
        }
        if(item.error.isNotBlank() && online && !series) Text(item.error,style=MaterialTheme.typography.bodySmall,color=Muted,modifier=Modifier.padding(start=124.dp,top=4.dp))
    }
}
