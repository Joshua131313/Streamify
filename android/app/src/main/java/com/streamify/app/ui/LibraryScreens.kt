package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.streamify.app.*
import com.streamify.app.data.*
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

@Composable
fun BrowseScreen(vm: StreamifyViewModel) {
    val searchFocus = remember { FocusRequester() }
    var lastFocusRequest by rememberSaveable { mutableStateOf(-1) }
    LaunchedEffect(vm.mediaSearchRequest) { if (lastFocusRequest != vm.mediaSearchRequest) { withFrameNanos { }; searchFocus.requestFocus(); lastFocusRequest = vm.mediaSearchRequest } }
    LaunchedEffect(Unit) { if (vm.catalog.data == null) vm.loadCatalog() }
    val genres by produceState<List<Genre>>(emptyList(), vm.browseType) {
        try { value = vm.repository.genres(vm.browseType) } catch (_: Exception) { coroutineContext.ensureActive() }
    }
    val state = vm.catalog
    LazyVerticalGrid(catalogGridCells(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = rootContentBottomPadding()),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            PageSearchField(vm.query, vm::search, if (vm.browseType == MediaType.ANIME) "Search anime" else "Search movies & series", Modifier.focusRequester(searchFocus))
        }
        if (vm.query.isBlank()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel("Find your next favorite")
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        item { FilterPill("Movies", vm.browseType == MediaType.MOVIE, { vm.browse(MediaType.MOVIE) }) }
                        item { FilterPill("Series", vm.browseType == MediaType.TV, { vm.browse(MediaType.TV) }) }
                        item { FilterPill("Anime", vm.browseType == MediaType.ANIME, { vm.browse(MediaType.ANIME) }) }
                        item { FilterPill("Collections", false, { vm.navigate(Destination.Collections) }) }
                    }
                    if (vm.browseType != MediaType.ANIME) LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        item { Choice("Genre", listOf(0 to "All genres") + genres.map { it.id to it.name }, vm.browseGenre) { vm.filterCatalog(genre = it) } }
                        item { Choice("Provider", listOf(0 to "All providers") + catalogProviders.map { it.id to it.name }, vm.browseProvider) { vm.filterCatalog(provider = it) } }
                    }
                }
            }
            if (vm.searches.isNotEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Recent searches", Modifier.weight(1f), style = MaterialTheme.typography.titleSmall, color = Muted)
                        SecondaryButton(onClick = vm::clearSearches) { Text("Clear") }
                    }
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(vm.searches) { term -> FilterPill(term, false, { vm.search(term) }, leading = { Icon(Icons.Rounded.History, null, Modifier.size(16.dp)) }) }
                    }
                }
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            if (vm.query.isBlank()) LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                item { FilterPill("Popular", vm.browseSort == "popular", { vm.browse(sort = "popular") }) }
                item { FilterPill("Top rated", vm.browseSort == "top_rated", { vm.browse(sort = "top_rated") }) }
            } else SectionLabel("Search results", "${if (vm.browseType == MediaType.ANIME) "Anime" else "Movies and series"} matching “${vm.query}”")
        }
        state.error?.let { item(span = { GridItemSpan(maxLineSpan) }) { ErrorBanner(it) { vm.loadCatalog() } } }
        items(state.data?.items.orEmpty(), key = { it.key }) { media -> MediaPoster(media, { vm.rememberSearch(); vm.selected = media }, roomy = true) }
        if (state.loading) item(span = { GridItemSpan(maxLineSpan) }) { Loading() }
        if (!state.loading && state.error == null && state.data?.items?.isEmpty() == true) item(span = { GridItemSpan(maxLineSpan) }) {
            Message("No matches", "Try a different title or change your filters.")
        }
        if (!state.loading && (state.data?.page ?: 1) < (state.data?.pages ?: 1)) item(span = { GridItemSpan(maxLineSpan) }) {
            SecondaryButton(onClick = { vm.loadCatalog(more = true) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Load more") }
        }
    }
}

@Composable
fun LibraryScreen(vm: StreamifyViewModel) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var history by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var type by rememberSaveable { mutableIntStateOf(-1) }
    fun matches(media: Media) = media.title.contains(query.trim(), true) && (type < 0 || media.type.ordinal == type)
    val saved = vm.saved.filter(::matches)
    val watched = vm.history.filter { matches(it.media) }
    val empty = if (history) vm.history.isEmpty() else vm.saved.isEmpty()
    LazyVerticalGrid(catalogGridCells(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = rootContentBottomPadding()),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                SectionLabel("Made for your downtime", "Your saved favorites and everything you’ve started.")
                SecondaryButton(onClick = { com.streamify.app.downloads.openDownloads(context) }) {
                    Icon(Icons.Rounded.Download, null, Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("View downloads")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (vm.account.uid == null) Icons.Rounded.PhoneAndroid else Icons.Rounded.CloudDone, null, Modifier.size(16.dp), tint = Muted)
                    Text(if (vm.account.uid == null) "Guest library · on this device" else if (vm.account.pendingWrites) "Waiting to sync" else if (vm.account.offline) "Offline · cached library" else "Synced with your web account", color = Muted, style = MaterialTheme.typography.bodySmall)
                }
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    item { FilterPill("Saved · ${vm.saved.size}", !history, { history = false }) }
                    item { FilterPill("History · ${vm.history.size}", history, { history = true }) }
                }
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                PageSearchField(query, { query = it }, if (history) "Search your history" else "Search your list")
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(listOf(-1 to "All", 0 to "Movies", 1 to "Series", 2 to "Anime")) { (value, name) -> FilterPill(name, type == value, { type = value }) }
                }
            }
        }
        if (empty) item(span = { GridItemSpan(maxLineSpan) }) {
            PagePanel {
                Message(if (history) "Start something great" else "Keep the good ones",
                    if (history) "Titles you open in the player will appear here." else "Save a movie or series and find it here whenever you’re ready.",
                    "Explore titles", { vm.tab = "Browse" })
            }
        } else if ((history && watched.isEmpty()) || (!history && saved.isEmpty())) item(span = { GridItemSpan(maxLineSpan) }) {
            Message("No titles match", "Try another name or media type.", "Clear filters", { query = ""; type = -1 })
        }
        if (history) items(watched, key = { it.media.key }, span = { GridItemSpan(maxLineSpan) }) { item ->
            Card(onClick = { vm.selected = item.media }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = Panel, contentColor = MaterialTheme.colorScheme.onSurface)) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    RemoteImage(item.media.image(), null, Modifier.width(64.dp).height(94.dp).clip(RoundedCornerShape(10.dp)))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(item.media.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(if (item.media.type == MediaType.TV) "S${item.season} · E${item.episode}" else item.media.year, color = Muted, style = MaterialTheme.typography.bodySmall)
                        if (item.durationSeconds > 0) {
                            LinearProgressIndicator(progress = { item.progress }, modifier = Modifier.fillMaxWidth().height(3.dp), color = StreamRed, trackColor = Muted.copy(alpha = .2f), drawStopIndicator = {})
                            Text(if (item.completed) "Watched" else "${kotlin.math.ceil((item.durationSeconds-item.positionSeconds).coerceAtLeast(0.0)/60).toInt()} min left", color = Muted, style = MaterialTheme.typography.labelSmall)
                        } else Text("View title", color = Muted, style = MaterialTheme.typography.labelSmall)
                    }
                    IconButton(onClick = { vm.removeHistory(item.media) }) { Icon(Icons.Rounded.Close, "Remove ${item.media.title} from history", Modifier.size(20.dp), tint = Muted) }
                }
            }
        } else items(saved, key = { it.key }) { media -> MediaPoster(media, { vm.selected = media }, roomy = true) }
    }
}
