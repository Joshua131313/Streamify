package com.streamify.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.streamify.app.LoadState
import com.streamify.app.PlayerActivity
import com.streamify.app.StreamifyViewModel
import com.streamify.app.data.*
import kotlinx.coroutines.CancellationException

/** Independent browse feeds: opening a category never changes or focuses Search. */
@Composable
fun CategoryScreen(vm: StreamifyViewModel, type: MediaType) {
    val title = when (type) { MediaType.MOVIE -> "Movies"; MediaType.TV -> "Shows"; MediaType.ANIME -> "Anime" }
    var category by rememberSaveable { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    val context = LocalContext.current
    val genres by produceState<List<Pair<String, String>>>(emptyList(), type) {
        value = if (type == MediaType.ANIME) listOf("Action", "Adventure", "Comedy", "Drama", "Fantasy", "Romance", "Sci-Fi", "Sports", "Thriller").map { it to it }
        else try { vm.repository.genres(type).map { it.id.toString() to it.name } } catch (e: CancellationException) { throw e } catch (_: Exception) { emptyList() }
    }
    Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF23352D), Canvas), endY = 1200f))) {
        Box(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 16.dp)) {
            FilledTonalIconButton(onClick = { vm.tab = "Home" }, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back to home")
            }
            Text(title, Modifier.align(Alignment.Center), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            IconButton(onClick = { vm.browse(type); vm.mediaSearchRequest++; vm.tab = "Browse" }, modifier = Modifier.align(Alignment.CenterEnd)) {
                Icon(Icons.Rounded.Search, "Search $title")
            }
        }
        LazyColumn(state = list, contentPadding = PaddingValues(bottom = 116.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            item(key = "categories") {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Box {
                        Button(onClick = { menu = true }, shape = CircleShape, colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = .16f), contentColor = Color.White)) {
                            Text(genres.firstOrNull { it.first == category }?.second ?: "Categories")
                            Spacer(Modifier.width(12.dp)); Icon(Icons.Rounded.ExpandMore, null)
                        }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DropdownMenuItem(text = { Text("All $title") }, onClick = { category = ""; menu = false })
                            genres.forEach { (id, label) -> DropdownMenuItem(text = { Text(label) }, onClick = { category = id; menu = false }) }
                        }
                    }
                }
            }
            item(key = "featured:$category") {
                CategoryFeed(vm, type, category, false) { media ->
                    media.firstOrNull()?.let { featured ->
                        FeaturedHero(featured, details = { vm.selected = featured }, play = {
                            val previous = vm.history.firstOrNull { it.media.key == featured.key && !it.completed }
                            val season = previous?.season ?: 1; val episode = previous?.episode ?: 1
                            vm.record(featured, season, episode)
                            context.startActivity(PlayerActivity.mediaIntent(context, featured, season, episode, vm.store.serverId))
                        }, save = { vm.toggleSaved(featured) }, saved = vm.saved.any { it.key == featured.key })
                        Spacer(Modifier.height(24.dp))
                        MediaShelf("Popular $title", media) { vm.selected = it }
                    }
                }
            }
            item(key = "rated:$category") {
                CategoryFeed(vm, type, category, true) { media -> MediaShelf("Top rated $title", media) { vm.selected = it } }
            }
            item { Text(if (type == MediaType.ANIME) "Anime catalog by AniList" else "Film and series data by TMDB", Modifier.padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.labelSmall) }
        }
    }
}

@Composable
private fun CategoryFeed(vm: StreamifyViewModel, type: MediaType, genre: String, rated: Boolean, content: @Composable (List<Media>) -> Unit) {
    val key = "category:${type.name}:$genre:$rated:${vm.store.tmdbKey.hashCode()}"
    var retry by remember { mutableIntStateOf(0) }
    val state by produceState(vm.discoveryCache[key] ?: LoadState<MediaPage>(loading = true), key, retry) {
        value = vm.discoveryCache[key] ?: LoadState(loading = true)
        if (value.data != null) return@produceState
        try {
            val page = if (type == MediaType.ANIME) AnimeCatalog.catalog(1, "", rated, genre.ifBlank { null })
            else if (genre.isBlank()) vm.repository.catalog("${type.path}/${if (rated) "top_rated" else "popular"}", type)
            else vm.repository.catalog("discover/${type.path}", type, params = mapOf("with_genres" to genre, "sort_by" to if (rated) "vote_average.desc" else "popularity.desc", "vote_count.gte" to "200"))
            value = LoadState(page); vm.discoveryCache[key] = value
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { value = LoadState(error = e.message ?: "Unable to load titles") }
    }
    Column {
        if (state.loading) Loading()
        state.error?.let { ErrorBanner(it) { retry++ } }
        state.data?.items?.let { if (it.isEmpty()) Text("No titles in this category yet.", Modifier.padding(20.dp), color = Muted) else content(it) }
    }
}
