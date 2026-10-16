package com.streamify.app.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.streamify.app.LoadState
import com.streamify.app.Destination
import com.streamify.app.PlayerActivity
import com.streamify.app.StreamifyViewModel
import com.streamify.app.data.*
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

@Composable
fun DetailScreen(media: Media, vm: StreamifyViewModel, back: () -> Unit) {
    val context = LocalContext.current
    var retry by remember { mutableIntStateOf(0) }
    val state by produceState(LoadState<Details>(loading = true), media.key, retry, vm.settingsRevision) {
        value = LoadState(loading = true)
        try { value = LoadState(vm.repository.details(media)) }
        catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
    }
    val previous = vm.history.firstOrNull { it.media.key == media.key }
    var season by rememberSaveable(media.key) { mutableIntStateOf(previous?.season ?: 1) }
    var episodeRetry by remember { mutableIntStateOf(0) }
    val episodes by produceState(LoadState<List<Episode>>(), media.key, season, episodeRetry) {
        if (media.type == MediaType.TV) {
            value = LoadState(loading = true)
            try { value = LoadState(vm.repository.episodes(media.id, season)) }
            catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
        }
    }
    val details = state.data
    val title = details?.media ?: media
    val saved = vm.saved.any { it.key == media.key }
    fun play(number: Int = 1, selectedSeason: Int = season) {
        vm.record(title, selectedSeason, number)
        val server = vm.store.servers.firstOrNull { it.id == vm.store.serverId } ?: vm.store.servers.first()
        context.startActivity(PlayerActivity.mediaIntent(context, title, selectedSeason, number, server.id))
    }
    val list = rememberLazyListState()
    val previewVisible by remember { derivedStateOf { list.layoutInfo.visibleItemsInfo.firstOrNull { it.index == 0 }?.let { (it.offset + it.size).coerceAtMost(list.layoutInfo.viewportEndOffset) - it.offset.coerceAtLeast(list.layoutInfo.viewportStartOffset) > it.size / 2 } == true } }
    PullDownDetail(list, vm::returnHome) { detailModifier ->
    LazyColumn(state = list, modifier = detailModifier, contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
        item {
            Box {
                TrailerPreview(details?.trailer, title.image(true), previewVisible)
                
                FilledIconButton(onClick = back, modifier = Modifier.padding(12.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.Black.copy(alpha = .55f), contentColor = Color.White)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
            }
        }
        item {
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(title.title, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                Text(listOf(title.year, title.type.label, "★ %.1f".format(title.rating), details?.runtime.orEmpty()).filter { it.isNotBlank() }.joinToString(" · "), color = Muted)
                details?.genres?.takeIf { it.isNotEmpty() }?.let { Text(it, style = MaterialTheme.typography.labelLarge, color = StreamRed) }
                }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = { play(previous?.episode ?: 1, previous?.season ?: season) }, modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black)) {
                        Icon(Icons.Rounded.PlayArrow, null)
                        Spacer(Modifier.width(8.dp))
                        Text(if (media.type == MediaType.TV && previous != null) "Watch S${previous.season} E${previous.episode}" else "Watch")
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SecondaryButton(onClick = { vm.toggleSaved(title) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Icon(if (saved) Icons.Rounded.Check else Icons.Rounded.Add, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(if (saved) "Saved" else "My list", maxLines = 1)
                    }
                    details?.trailer?.let { url -> SecondaryButton(onClick = {
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                    }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Icon(Icons.Rounded.SmartDisplay, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Trailer", maxLines = 1) } }
                    }
                }
                Text(title.overview.ifBlank { "No synopsis available." }, style = MaterialTheme.typography.bodyMedium, color = Muted)
            }
        }
        if (state.loading) item { Loading() }
        state.error?.let { item { ErrorBanner(it) { retry++ } } }
        if (media.type == MediaType.TV) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionLabel("Episodes", modifier = Modifier.padding(horizontal = 20.dp))
                Box(Modifier.padding(horizontal = 20.dp)) {
                    var choosing by remember { mutableStateOf(false) }
                    SecondaryButton(onClick = { choosing = true }) { Text("Season $season");Spacer(Modifier.width(12.dp));Icon(Icons.Rounded.ExpandMore,null) }
                    DropdownMenu(choosing, { choosing = false }) {
                        details?.seasons.orEmpty().forEach { choice -> DropdownMenuItem(text = { Text(choice.name) }, onClick = { season=choice.number;choosing=false }) }
                    }
                }
                }
            }
            if (episodes.loading) item { Loading() }
            episodes.error?.let { item { ErrorBanner(it) { episodeRetry++ } } }
            if (!episodes.loading && episodes.error == null && episodes.data?.isEmpty() == true) item { Message("No episodes yet", "Episodes for this season will appear when available.") }
            items(episodes.data.orEmpty(), key = { "episode-${season}-${it.number}" }) { episode ->
                Column(Modifier.padding(horizontal = 20.dp).fillMaxWidth().clickable { play(episode.number) }, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Box(Modifier.width(128.dp).height(76.dp).clip(RoundedCornerShape(8.dp))) {
                            RemoteImage(episode.still.takeIf { it.startsWith("/") }?.let { "https://image.tmdb.org/t/p/w342$it" }, null, Modifier.fillMaxSize())
                            Surface(Modifier.align(Alignment.Center).size(34.dp), shape = androidx.compose.foundation.shape.CircleShape, color = Color.Black.copy(alpha=.6f), border = androidx.compose.foundation.BorderStroke(1.dp, Color.White)) {
                                Box(contentAlignment=Alignment.Center) { Icon(Icons.Rounded.PlayArrow,"Watch episode ${episode.number}",tint=Color.White) }
                            }
                            if(previous?.season==season && previous.episode==episode.number && previous.durationSeconds>0) {
                                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(3.dp).background(Color.White.copy(alpha=.3f))) { Box(Modifier.fillMaxHeight().fillMaxWidth(previous.progress).background(StreamRed)) }
                            }
                        }
                        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                            Text("${episode.number}. ${episode.title}",style=MaterialTheme.typography.titleSmall,maxLines=3,overflow=TextOverflow.Ellipsis)
                            Text(if(episode.runtime>0) "${episode.runtime} min" else episode.date,color=Muted,style=MaterialTheme.typography.labelMedium)
                        }
                    }
                    Text(episode.overview.ifBlank { "Episode synopsis unavailable." }, maxLines=4,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodyMedium,color=Muted)
                }
            }
        }
        if (details?.cast?.isNotEmpty() == true) item {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("The cast", Modifier.padding(horizontal = 20.dp), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(details.cast) { credit -> Column(Modifier.width(104.dp).clickable(enabled = credit.id > 0) { vm.navigate(Destination.PersonDetail(credit.id)) }) {
                        RemoteImage(credit.image.takeIf { it.startsWith("/") }?.let { "https://image.tmdb.org/t/p/w185$it" }, null, Modifier.width(104.dp).height(136.dp).clip(RoundedCornerShape(12.dp)))
                        Text(credit.name, Modifier.padding(top = 10.dp), style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(credit.character, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.labelSmall, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    } }
                }
            }
        }
        item { MediaShelf("More like this", details?.related.orEmpty()) { vm.selected = it } }
    }
}
}
