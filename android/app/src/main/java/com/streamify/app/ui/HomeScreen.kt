package com.streamify.app.ui

import android.animation.ValueAnimator
import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.streamify.app.StreamifyViewModel
import com.streamify.app.PlayerActivity
import com.streamify.app.data.Media
import com.streamify.app.data.MediaType
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@Composable
fun HomeScreen(vm: StreamifyViewModel, active: Boolean = true, settings: () -> Unit) {
    val state = vm.home
    val list = rememberLazyListState()
    val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val carouselVisible by remember { derivedStateOf {
        val layout = list.layoutInfo
        layout.visibleItemsInfo.firstOrNull { it.key == "featured" }?.let {
            val visible = minOf(it.offset + it.size, layout.viewportEndOffset) - maxOf(it.offset, layout.viewportStartOffset)
            visible > it.size * .7f
        } ?: false
    } }
    LazyColumn(state = list, verticalArrangement = Arrangement.spacedBy(20.dp), contentPadding = PaddingValues(bottom = 108.dp + bottomInset)) {
        item(key = "shortcuts") {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item { HomeShortcut("Shows") { vm.tab = "Shows" } }
                item { HomeShortcut("Movies") { vm.tab = "Movies" } }
                item { HomeShortcut("Anime") { vm.tab = "Anime" } }
                item { HomeShortcut("Live sports") { vm.tab = "Sports" } }
            }
        }
        if (vm.store.tmdbKey.isBlank()) item { Message("Welcome to Streamify", "Connect your TMDB key to discover movies and series. Live sports are ready to explore.", "Set up catalog", settings) }
        if (state.loading && state.data == null) item { Loading() }
        state.error?.let { item { ErrorBanner(it, vm::loadHome) } }
        val featured = state.data?.firstOrNull()?.items.orEmpty().take(5)
        if (featured.isNotEmpty()) item(key = "featured") {
            FeaturedCarousel(featured, vm, active && carouselVisible && !list.isScrollInProgress)
        }
        if (vm.history.any { !it.completed }) item { ContinueWatchingShelf(vm.history.filterNot { it.completed }.take(12), vm.store.serverId) }
        item {
            Card(onClick = { vm.tab = "Sports" }, shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Panel), modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
                Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.SportsBasketball, null, tint = StreamRed, modifier = Modifier.size(30.dp))
                    Column(Modifier.weight(1f).padding(horizontal = 14.dp)) {
                        Text("The game is on.", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text("Live scores, schedules & streams", color = Muted, style = MaterialTheme.typography.bodySmall)
                    }
                    Icon(Icons.AutoMirrored.Rounded.ArrowForward, "Open sports", Modifier.size(22.dp))
                }
            }
        }
        items(state.data.orEmpty(), key = { it.title }) { shelf -> MediaShelf(shelf.title, if (shelf.title == "TOP 10 Today") shelf.items.take(10) else shelf.items) { vm.selected = it } }
        item { DiscoveryShelf("For you", "recommendations", vm) }
        item { DiscoveryShelf("Trending Today", "trending", vm) }
        item { DiscoveryShelf("Only on", "provider", vm) }
        item { DiscoveryShelf("Explore genres", "genre", vm) }
        item(key = "collections") { CollectionsShelf(vm) }
        item { Text("Film and series data by TMDB", Modifier.fillMaxWidth().padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.labelSmall) }
    }
}

@Composable
private fun HomeShortcut(label: String, onClick: () -> Unit) {
    Box(Modifier.height(48.dp).clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f),
            border = BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))) {
            Text(label, Modifier.padding(horizontal = 17.dp, vertical = 10.dp), fontSize = 15.sp, lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false)
        }
    }
}

@Composable
private fun FeaturedCarousel(featured: List<Media>, vm: StreamifyViewModel, visible: Boolean) {
    val pager = rememberPagerState(pageCount = { featured.size })
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val context = LocalContext.current
    val accessibility = remember(context) { context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager }
    var screenReader by remember { mutableStateOf(accessibility.isTouchExplorationEnabled) }
    DisposableEffect(accessibility) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { screenReader = it }
        accessibility.addTouchExplorationStateChangeListener(listener)
        onDispose { accessibility.removeTouchExplorationStateChangeListener(listener) }
    }
    var playing by rememberSaveable { mutableStateOf(ValueAnimator.areAnimatorsEnabled()) }
    val dragged by pager.interactionSource.collectIsDraggedAsState()
    val autoPlay = playing && visible && !screenReader && featured.size > 1
    LaunchedEffect(pager.settledPage, autoPlay, dragged, lifecycle) {
        progress.snapTo(0f)
        if (!autoPlay || dragged) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            snapshotFlow { pager.isScrollInProgress }.first { !it }
            progress.animateTo(1f, tween(6500, easing = LinearEasing))
            pager.animateScrollToPage((pager.settledPage + 1) % featured.size, animationSpec = tween(550))
        }
    }
    Column {
        HorizontalPager(pager, key = { featured[it].key }) { index ->
            val media = featured[index]
            FeaturedHero(media, details = { vm.selected = media }, play = {
                val previous = vm.history.firstOrNull { it.media.key == media.key }
                val season = previous?.season ?: 1
                val episode = previous?.episode ?: 1
                vm.record(media, season, episode)
                context.startActivity(PlayerActivity.mediaIntent(context, media, season, episode, vm.store.serverId))
            }, save = { vm.toggleSaved(media) }, saved = vm.saved.any { it.key == media.key })
        }
        Row(Modifier.align(Alignment.CenterHorizontally).padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            featured.forEachIndexed { index, media ->
                val selected = pager.currentPage == index
                val width by animateDpAsState(if (selected) 28.dp else 6.dp, label = "Carousel indicator")
                Box(Modifier.size(48.dp).selectable(selected, role = Role.Tab, onClick = {
                    scope.launch { pager.animateScrollToPage(index) }
                }).semantics { contentDescription = "Show ${media.title}" }, contentAlignment = Alignment.Center) {
                    Box(Modifier.width(width).height(4.dp).clip(CircleShape).background(Muted.copy(alpha = .3f))) {
                        if (selected) Box(Modifier.fillMaxHeight().fillMaxWidth(if (autoPlay) progress.value.coerceAtLeast(.12f) else 1f).background(MaterialTheme.colorScheme.onSurface))
                    }
                }
            }
            if (featured.size > 1 && !screenReader) IconButton(onClick = { playing = !playing }) {
                Icon(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    if (playing) "Pause carousel" else "Resume carousel", Modifier.size(18.dp), tint = Muted)
            }
        }
    }
}

@Composable
internal fun FeaturedHero(media: Media, details: () -> Unit, play: () -> Unit, save: () -> Unit, saved: Boolean) {
    Card(onClick = details, modifier = Modifier.padding(horizontal = 16.dp), shape = RoundedCornerShape(16.dp), border = BorderStroke(1.dp, Color.White.copy(alpha = .16f))) {
        Box(Modifier.fillMaxWidth().aspectRatio(.82f)) {
            RemoteImage(media.image() ?: media.image(true), null, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to Color.Transparent, .45f to Color.Transparent, .8f to Color(0xB31B1720), 1f to Color(0xFF1B1720))))
            IconButton(onClick = details, modifier = Modifier.align(Alignment.TopEnd).padding(6.dp)) {
                Icon(Icons.Rounded.Info, "Details for ${media.title}", Modifier.size(22.dp), tint = Color.White)
            }
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(media.title, color = Color.White, fontSize = 24.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(listOf(media.year, media.type.label, "★ %.1f".format(media.rating)).filter { it.isNotBlank() }.joinToString("   ·   "),
                    color = Color(0xFFD4D4D8), style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = play, modifier = Modifier.weight(1.1f).height(42.dp), shape = CircleShape,
                        contentPadding = PaddingValues(horizontal = 10.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black)) {
                        Icon(Icons.Rounded.PlayArrow, null, Modifier.size(22.dp)); Spacer(Modifier.width(6.dp))
                        Text("Watch", fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Bold)
                    }
                    Button(onClick = save, modifier = Modifier.weight(1f).height(42.dp), shape = CircleShape, border = BorderStroke(.7.dp, Color.White.copy(alpha = .15f)),
                        contentPadding = PaddingValues(horizontal = 10.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = .24f), contentColor = Color.White)) {
                        Icon(if (saved) Icons.Rounded.Check else Icons.Rounded.Add, null, Modifier.size(22.dp)); Spacer(Modifier.width(6.dp))
                        Text(if (saved) "Added" else "My list", fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
