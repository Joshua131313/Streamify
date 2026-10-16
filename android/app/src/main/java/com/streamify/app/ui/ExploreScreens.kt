package com.streamify.app.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.streamify.app.*
import com.streamify.app.data.*
import com.streamify.app.data.Collection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

@Composable
fun ScreenHeading(title: String, back: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Text(title, Modifier.weight(1f), fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun Choice(label: String, options: List<Pair<Int, String>>, selected: Int, select: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        SecondaryButton(onClick = { open = true }, modifier = Modifier.widthIn(max = 260.dp).heightIn(min = 44.dp),
            shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            border = BorderStroke(1.dp, Muted.copy(alpha = .28f)),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
            Text(options.firstOrNull { it.first == selected }?.second ?: label, Modifier.weight(1f, fill = false),
                style = MaterialTheme.typography.labelLarge, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(18.dp), tint = Muted)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (id, name) -> DropdownMenuItem(text = { Text(name) }, onClick = { select(id); open = false }) }
        }
    }
}

/** Small visible control with a 48dp tap target; long choices remain readable in the menu. */
@Composable
private fun CompactChoice(label: String, options: List<Pair<Int, String>>, selected: Int, select: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(Modifier.widthIn(max = 120.dp).height(48.dp).clickable(role = Role.Button, onClickLabel = "Choose $label") { open = true }, contentAlignment = Alignment.Center) {
        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .08f))
            .height(30.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(options.firstOrNull { it.first == selected }?.second ?: label, Modifier.weight(1f, fill = false),
                fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.width(4.dp))
            Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(13.dp), tint = Muted)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (id, name) -> DropdownMenuItem(text = { Text(name) }, onClick = { select(id); open = false }) }
        }
    }
}

@Composable
fun CollectionArt(collection: Collection, modifier: Modifier) {
    val context = LocalContext.current
    val bitmap by produceState<Bitmap?>(null, collection.id) {
        value = withContext(Dispatchers.IO) { context.assets.open("collections/${collection.backdrop}").use { BitmapFactory.decodeStream(it) } }
    }
    Box(modifier.background(Panel)) { bitmap?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) } }
}

@Composable
private fun CollectionTile(collection: Collection, vm: StreamifyViewModel, modifier: Modifier = Modifier) {
    Card(onClick = { vm.navigate(Destination.CollectionDetail(collection)) }, modifier = modifier, shape = RoundedCornerShape(16.dp)) {
        Box(Modifier.fillMaxWidth().height(180.dp)) {
            CollectionArt(collection, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .9f)))))
            Column(Modifier.align(Alignment.BottomStart).padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(collection.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = Color.White)
                Text("Explore collection →", color = Color(0xFFCCD0D8), style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable
fun CollectionsShelf(vm: StreamifyViewModel) {
    Column {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Collections", Modifier.weight(1f), fontSize = 18.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            SecondaryButton(onClick = { vm.navigate(Destination.Collections) }, contentPadding = PaddingValues(horizontal = 4.dp),
                colors = ButtonDefaults.textButtonColors(contentColor = Muted)) {
                Text("Explore all", fontSize = 11.sp, lineHeight = 14.sp, maxLines = 1, softWrap = false)
                Spacer(Modifier.width(4.dp)); Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, Modifier.size(14.dp))
            }
        }
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(vm.store.collections.filter { it.featured }, key = { it.id }) { CollectionTile(it, vm, Modifier.width(260.dp)) }
        }
    }
}

@Composable
fun CollectionsScreen(vm: StreamifyViewModel) {
    var search by rememberSaveable { mutableStateOf("") }
    var genre by rememberSaveable { mutableIntStateOf(0) }
    val genres by produceState<List<Genre>>(emptyList()) { try { value = vm.repository.genres(MediaType.MOVIE) } catch (_: Exception) { coroutineContext.ensureActive() } }
    val items = vm.store.collections.filter { it.name.contains(search.trim(), true) && (genre == 0 || genre in it.genres) }
    Column {
        ScreenHeading("Collections", vm::back)
        LazyVerticalGrid(GridCells.Adaptive(240.dp), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            item(span = { GridItemSpan(maxLineSpan) }) { SectionLabel("A whole world to explore", "Discover the stories that belong together.") }
            item(span = { GridItemSpan(maxLineSpan) }) { Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                PageSearchField(search, { search = it }, "Find a collection")
                Choice("All genres", listOf(0 to "All genres") + genres.filter { item -> vm.store.collections.any { item.id in it.genres } }.map { it.id to it.name }, genre, { genre = it })
            } }
            items(items, key = { it.id }) { CollectionTile(it, vm) }
            if (items.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { Message("No collections match", "Try another name or genre.", "Clear filters", { search = ""; genre = 0 }) }
        }
    }
}

@Composable
fun CollectionScreen(collection: Collection, vm: StreamifyViewModel) {
    var retry by remember { mutableIntStateOf(0) }
    val state by produceState(LoadState<CollectionDetails>(loading = true), collection.id, retry) {
        value = LoadState(loading = true)
        try { value = LoadState(vm.repository.collection(collection.id)) } catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
    }
    LazyVerticalGrid(catalogGridCells(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) { Column {
            ScreenHeading("Collections", vm::back)
            Box(Modifier.fillMaxWidth().height(230.dp).clip(RoundedCornerShape(20.dp))) {
                CollectionArt(collection, Modifier.fillMaxSize())
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Canvas))))
                Text("${collection.name} Collection", Modifier.align(Alignment.BottomStart).padding(20.dp), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            }
            state.data?.let { details ->
                Text("${details.movies.size} movies · Release order", Modifier.padding(top = 20.dp), color = StreamRed, style = MaterialTheme.typography.labelLarge)
                if (details.overview.isNotBlank()) Text(details.overview, Modifier.padding(top = 16.dp), color = Muted, style = MaterialTheme.typography.bodyMedium)
            }
        } }
        if (state.loading) item(span = { GridItemSpan(maxLineSpan) }) { Loading() }
        state.error?.let { item(span = { GridItemSpan(maxLineSpan) }) { ErrorBanner(it) { retry++ } } }
        items(state.data?.movies.orEmpty(), key = { it.key }) { media -> MediaPoster(media, { vm.selected = media }, roomy = true) }
        if (!state.loading && state.error == null && state.data?.movies.isNullOrEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { Message("No movies yet", "This collection does not have released titles in the catalog.") }
    }
}

@Composable
fun PersonScreen(id: Int, vm: StreamifyViewModel) {
    var retry by remember { mutableIntStateOf(0) }
    val state by produceState(LoadState<Person>(loading = true), id, retry) {
        value = LoadState(loading = true)
        try { value = LoadState(vm.repository.person(id)) } catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
    }
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { ScreenHeading("Cast profile", vm::back) }
        if (state.loading) item { Loading() }
        state.error?.let { item { ErrorBanner(it) { retry++ } } }
        state.data?.let { person ->
            item { Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                RemoteImage(person.image.takeIf { it.startsWith('/') }?.let { "https://image.tmdb.org/t/p/h632$it" }, person.name, Modifier.width(160.dp).height(220.dp).clip(RoundedCornerShape(18.dp)))
                Text(person.name, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                Text(listOf(person.birthday, person.birthplace).filter { it.isNotBlank() }.joinToString(" · "), color = Muted)
                Text(person.biography.ifBlank { "No biography available." }, color = Muted, style = MaterialTheme.typography.bodyMedium)
            } }
            item { MediaShelf("Known for", person.credits) { vm.selected = it } }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
fun DiscoveryShelf(title: String, category: String, vm: StreamifyViewModel) {
    val configuration = LocalConfiguration.current
    val heading = if (category == "genre" && (configuration.screenWidthDp < 380 || configuration.fontScale > 1.15f)) "Genres" else title
    var type by rememberSaveable { mutableStateOf(MediaType.MOVIE) }
    var selection by rememberSaveable { mutableIntStateOf(if (category == "genre") 16 else 8) }
    var retry by remember { mutableIntStateOf(0) }
    val genres by produceState<List<Genre>>(emptyList(), type) { try { value = vm.repository.genres(type) } catch (_: Exception) { coroutineContext.ensureActive() } }
    val validGenres = genres.map { it.id }.toSet()
    val favoriteGenres = (vm.account.genres.mapNotNull { it.toIntOrNull() } + vm.history.flatMap { it.media.genreIds })
        .filter { it in validGenres }.groupingBy { it }.eachCount().entries.sortedByDescending { it.value }.take(3).joinToString(",") { it.key.toString() }
    val cacheKey = "$category:$type:$selection:${vm.settingsRevision}:$favoriteGenres"
    val state by produceState(vm.discoveryCache[cacheKey] ?: LoadState<MediaPage>(loading = true), cacheKey, retry) {
        value = vm.discoveryCache[cacheKey] ?: LoadState(loading = true)
        val path = when (category) {
            "recommendations" -> if (favoriteGenres.isNotEmpty()) "discover/${type.path}" else "trending/${type.path}/day"
            "trending" -> "trending/${type.path}/day"
            else -> "discover/${type.path}"
        }
        val params = when (category) {
            "recommendations" -> if (favoriteGenres.isNotEmpty()) mapOf("with_genres" to favoriteGenres) else emptyMap()
            "provider" -> mapOf("with_watch_providers" to selection.toString(), "watch_region" to "US")
            "genre" -> mapOf("with_genres" to selection.toString())
            else -> emptyMap()
        }
        try { value = LoadState(vm.repository.catalog(path, type, params = params)); vm.discoveryCache[cacheKey] = value }
        catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(heading, Modifier.weight(1f), fontSize = 18.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            CompactChoice("media type", MediaType.entries.map { it.ordinal to if (it == MediaType.MOVIE) "Movies" else "Series" }, type.ordinal) {
                type = MediaType.entries[it]; if (category == "genre") selection = 16
            }
            if (category == "provider") CompactChoice("provider", catalogProviders.map { it.id to it.name }, selection) { selection = it }
            if (category == "genre") CompactChoice("genre", genres.map { it.id to it.name }, selection) { selection = it }
        }
        if (state.loading) Loading()
        state.error?.let { ErrorBanner(it) { retry++ } }
        MediaShelf("", state.data?.items.orEmpty()) { vm.selected = it }
    }
}
