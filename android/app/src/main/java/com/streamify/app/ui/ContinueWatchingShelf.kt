package com.streamify.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.combinedClickable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.streamify.app.PlayerActivity
import com.streamify.app.data.History
import com.streamify.app.data.MediaType
import kotlin.math.ceil

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ContinueWatchingShelf(history: List<History>, provider: String, info:(com.streamify.app.data.Media)->Unit, remove:(com.streamify.app.data.Media)->Unit) {
    val context = LocalContext.current
    var selected by remember {mutableStateOf<History?>(null)}
    val haptics=androidx.compose.ui.platform.LocalHapticFeedback.current
    selected?.let {entry -> MediaActionsSheet(entry.media,{selected=null},{info(entry.media)},entry.season,entry.episode,{remove(entry.media)})}
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Continue watching", Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(history, key = { it.media.key }) { entry ->
                Column(Modifier.width(184.dp).combinedClickable(onClick={ context.startActivity(PlayerActivity.mediaIntent(context, entry.media, entry.season, entry.episode, provider)) },onLongClick={haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress);selected=entry},onLongClickLabel="Show title actions")) {
                    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(12.dp))) {
                        RemoteImage(entry.media.image(wide = true), entry.media.title, Modifier.fillMaxSize())
                        Surface(Modifier.align(Alignment.Center).size(38.dp), shape = CircleShape, color = Color.Black.copy(alpha = .65f), border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = .8f))) {
                            Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.PlayArrow, "Resume ${entry.media.title}", Modifier.size(24.dp), tint = Color.White) }
                        }
                        if (entry.durationSeconds > 0) Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = .3f)).semantics { contentDescription = "${(entry.progress * 100).toInt()} percent watched" }) {
                            Box(Modifier.fillMaxHeight().fillMaxWidth(entry.progress).background(StreamRed))
                        }
                    }
                    Text(entry.media.title, Modifier.padding(top = 8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                    val episode = if (entry.media.type == MediaType.TV) "S${entry.season} · E${entry.episode} · " else ""
                    Text(episode + if (entry.durationSeconds > 0) "${ceil((entry.durationSeconds-entry.positionSeconds).coerceAtLeast(0.0)/60).toInt()} min left" else "Recently watched",
                        Modifier.padding(top = 4.dp), color = Muted, style = MaterialTheme.typography.labelSmall, maxLines = 1)
                }
            }
        }
    }
}
