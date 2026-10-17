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

fun openDownloads(context: Context) { context.startActivity(Intent(context,DownloadsActivity::class.java)) }

@Composable
fun DownloadButton(media: Media, season: Int = 0, episode: Int = 0, compact: Boolean = false) {
    val context=LocalContext.current
    val store=remember { DownloadStore.get(context) }
    val downloads by store.items.collectAsState()
    val key="${media.type.path}_${media.id}_${season}_$episode"
    val existing=downloads.firstOrNull { it.key==key }
    var confirm by remember { mutableStateOf(false) }
    val action = { if(existing==null) confirm=true else openDownloads(context) }
    if(compact) IconButton(onClick=action) { Icon(if(existing?.state=="complete") Icons.Rounded.DownloadDone else Icons.Rounded.Download,"Download episode $episode") }
    else SecondaryButton(onClick=action) { Icon(if(existing?.state=="complete") Icons.Rounded.DownloadDone else Icons.Rounded.Download,null);Spacer(Modifier.width(8.dp));Text(if(existing==null) "Download" else "View download") }
    if(confirm) AlertDialog(onDismissRequest={confirm=false}, title={Text("Download ${media.title}?")},
        text={Text("Save ${if(season>0) "season $season, episode $episode" else "this movie"} on this device for offline watching. Files can be large and use mobile data. Availability varies by title.")},
        confirmButton={TextButton(onClick={confirm=false;store.enqueue(media,season,episode);openDownloads(context)}) {Text("Download")}},
        dismissButton={TextButton(onClick={confirm=false}) {Text("Cancel")}})
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
    var remove by remember { mutableStateOf<DownloadItem?>(null) }
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
    LazyColumn(Modifier.fillMaxSize().safeDrawingPadding(),contentPadding=PaddingValues(bottom=24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { if(back != null) ScreenHeading("Downloads",back) else Text("Downloads",Modifier.padding(horizontal=20.dp,vertical=20.dp),style=MaterialTheme.typography.headlineLarge) }
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
        items(downloads.sortedBy { it.title },key={it.key}) { item ->
            PagePanel(Modifier.padding(horizontal=20.dp)) {
                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                    RemoteImage(item.poster,null,Modifier.width(64.dp).height(92.dp))
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                        Text(item.title,style=MaterialTheme.typography.titleMedium,maxLines=2,overflow=TextOverflow.Ellipsis)
                        Text(item.subtitle,style=MaterialTheme.typography.bodySmall,color=Muted)
                        Text(when(item.state) { "complete" -> "Ready · ${item.bytes/1_000_000} MB";"resolving" -> "Finding download…";"queued" -> "Queued";"paused" -> "Paused";"error" -> "Needs attention";else -> "${item.bytes/1_000_000} / ${if(item.total>0) item.total/1_000_000 else "?"} MB" },style=MaterialTheme.typography.labelMedium,color=Muted)
                    }
                    IconButton(onClick={remove=item}) {Icon(Icons.Rounded.DeleteOutline,"Delete download")}
                }
                if(item.state!="complete") LinearProgressIndicator(progress={if(item.total>0) (item.bytes.toFloat()/item.total).coerceIn(0f,1f) else 0f},modifier=Modifier.fillMaxWidth())
                if(item.error.isNotBlank() && online) Text(item.error,style=MaterialTheme.typography.bodySmall,color=Muted)
                if(!online && item.state!="complete") Text("Connect to the internet to resume this download.",style=MaterialTheme.typography.bodySmall,color=Muted)
                Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                    if(item.state=="complete") SecondaryButton(onClick={context.startActivity(Intent(context,OfflinePlayerActivity::class.java).putExtra("key",item.key))}) {Icon(Icons.Rounded.PlayArrow,null);Spacer(Modifier.width(6.dp));Text("Watch offline")}
                    else if(item.state in listOf("queued","resolving","downloading")) SecondaryButton(onClick={DownloadStore.command(context,"pause",item.key)}) {Icon(Icons.Rounded.Pause,null);Spacer(Modifier.width(6.dp));Text("Pause")}
                    else if(item.state!="deleting") SecondaryButton(enabled=online,onClick={DownloadStore.command(context,"resume",item.key)}) {Icon(Icons.Rounded.Download,null);Spacer(Modifier.width(6.dp));Text(if(item.state=="error") "Retry" else "Resume")}
                }
            }
        }
    }
    remove?.let { item -> AlertDialog(onDismissRequest={remove=null},title={Text("Delete download?")},text={Text("Remove ${item.title} from this device to free up space.")},confirmButton={TextButton(onClick={DownloadStore.command(context,"delete",item.key);remove=null}) {Text("Delete")}},dismissButton={TextButton(onClick={remove=null}) {Text("Keep")}}) }
}
