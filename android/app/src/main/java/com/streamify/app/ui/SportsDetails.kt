package com.streamify.app.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.streamify.app.*
import com.streamify.app.data.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

@Composable
fun GameScreen(game: Game, vm: StreamifyViewModel, back: () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    var retry by remember { mutableIntStateOf(0) }
    var tab by rememberSaveable(game.key) { mutableStateOf("Overview") }
    var center by remember(game.key) { mutableStateOf(LoadState<GameCenter>(loading = true)) }
    LaunchedEffect(owner, game.key, retry) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                try { center = LoadState(SportsData.center(game)) } catch (error: Exception) { coroutineContext.ensureActive(); center = LoadState(center.data, error = error.localizedMessage) }
                delay(60_000)
            }
        }
    }
    val current = center.data?.game ?: game
    val streams by produceState(LoadState<List<Stream>>(loading = true), game.key, retry) {
        value = LoadState(loading = true)
        try { value = LoadState(vm.repository.streams(current)) } catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
    }
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
            Text("Game center", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            if (httpsUrl(game.link)) Surface(onClick = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(game.link))) } },
                modifier = Modifier.semantics { contentDescription = "Open game on ESPN" }, color = Color(0xFFD71920), shape = RoundedCornerShape(12.dp)) {
                Row(Modifier.heightIn(min = 48.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Image(painterResource(com.streamify.app.R.drawable.espn_logo), null, Modifier.width(54.dp).height(20.dp), contentScale = ContentScale.Fit)
                    Icon(Icons.Rounded.NorthEast, null, Modifier.size(14.dp), tint = Color.White)
                }
            }
        } }
        item { Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(if (current.live) "● LIVE · ${current.status}" else current.status, color = game.league.accent())
            Text("${current.away.name}\nat ${current.home.name}", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text("${gameTime(current)} · ${current.localDate ?: ""}\n${current.venue}", color = Muted)
        } }
        item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
            listOf(current.away, current.home).forEach { team -> TeamRow(team, current.state != "pre") {
                IconButton(onClick = { vm.toggleTeam(game.league, team) }) { Icon(if (vm.isFollowing(game.league, team)) Icons.Rounded.Star else Icons.Rounded.StarBorder, "Follow ${team.name}", tint = game.league.accent()) }
            } }
        } }
        item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(listOf("Overview", "Scoring", "Team stats", "Latest play", "Chat")) { value -> FilterPill(value, value == tab, { tab = value }) }
        } }
        if (tab == "Chat") {
            item { LiveChat(current, vm) }
        } else {
            if (center.loading) item { Loading() }
            center.error?.let { item { ErrorBanner("Detailed feed unavailable. The schedule score is shown above.") { retry++ } } }
            when (tab) {
                "Overview" -> {
                    item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
                        Text("Game information", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        Text("${current.away.name} at ${current.home.name}. ${current.status}.", color = Muted)
                        Text(current.broadcasts.ifBlank { "Broadcast not announced" }, color = Muted)
                        if (current.canWatch()) Button(onClick = { context.startActivity(PlayerActivity.gameIntent(context, current)) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black)) { Icon(Icons.Rounded.PlayArrow, null); Spacer(Modifier.width(8.dp)); Text("Watch game") }
                        SecondaryButton(onClick = {
                        streams.data?.firstOrNull()?.let { vm.queueStream(it.copy(label = "${game.away.abbreviation} vs ${game.home.abbreviation}")) }
                        vm.navigate(Destination.MultiWatch)
                    }, enabled = !streams.data.isNullOrEmpty() && vm.multiWatch.size < 4, modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black)) { Icon(Icons.Rounded.GridView, null); Spacer(Modifier.width(8.dp)); Text("Add to multi-watch") }
                    } }
                    item { TeamButton(current.away, game.league, vm) }
                    item { TeamButton(current.home, game.league, vm) }
                }
                "Scoring", "Team stats" -> {
                    val rows = if (tab == "Scoring") center.data?.scoring.orEmpty() else center.data?.stats.orEmpty()
                    if (tab == "Scoring" && rows.isNotEmpty()) item { ScoringTable(current, rows) }
                    if (tab == "Team stats") {
                    item { Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.SpaceBetween) { Text(current.away.abbreviation, color = game.league.accent()); Text(tab); Text(current.home.abbreviation, color = game.league.accent()) } }
                    items(rows) { row -> Surface(Modifier.fillMaxWidth().padding(horizontal = 20.dp), shape = RoundedCornerShape(14.dp), color = Panel) {
                        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(row.away, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                            Text(row.label, Modifier.weight(2f), color = Muted, style = MaterialTheme.typography.bodySmall, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            Text(row.home, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                        }
                    } }
                    }
                    if (rows.isEmpty()) item { Message("Awaiting ${tab.lowercase()}", "A breakdown is not available in the current feed.") }
                }
                "Latest play" -> item { Text(center.data?.latest?.ifBlank { "No play update available yet." } ?: "No play update available yet.", Modifier.padding(20.dp), color = Muted) }
            }
        }
    }
}

@Composable
fun TeamScreen(destination: Destination.TeamDetail, vm: StreamifyViewModel) {
    var tab by rememberSaveable { mutableStateOf("Schedule") }
    var retry by remember { mutableIntStateOf(0) }
    val state by produceState(LoadState<TeamProfile>(loading = true), destination.team.id, destination.league, retry) {
        value = LoadState(loading = true)
        try { value = LoadState(SportsData.profile(destination.league, destination.team)) } catch (error: Exception) { coroutineContext.ensureActive(); value = LoadState(error = error.localizedMessage) }
    }
    val team = state.data?.team ?: destination.team
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { ScreenHeading("${destination.league} · Team", vm::back) }
        item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
            RemoteImage(team.logo, team.name, Modifier.size(100.dp), ContentScale.Fit)
            Text(team.name, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            state.data?.let { Text(listOf(it.location, it.venue, team.record).filter { it.isNotBlank() }.joinToString(" · "), color = Muted) }
            val followed = vm.isFollowing(destination.league, team)
            SecondaryButton(onClick = { vm.toggleTeam(destination.league, team) }, modifier = Modifier.heightIn(min = 48.dp)) { Icon(if (followed) Icons.Rounded.Star else Icons.Rounded.StarBorder, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text(if (followed) "Following" else "Follow team") }
        } }
        item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { items(listOf("Schedule", "Results", "Roster")) { value -> FilterPill(value, tab == value, { tab = value }) } } }
        if (state.loading) item { Loading() }
        state.error?.let { item { ErrorBanner(it) { retry++ } } }
        state.data?.let { profile ->
            if (tab == "Roster") {
                items(profile.roster) { player -> Surface(Modifier.fillMaxWidth().padding(horizontal = 20.dp), shape = RoundedCornerShape(16.dp), color = Panel) {
                    Row(Modifier.padding(18.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(player.number, Modifier.width(32.dp), color = destination.league.accent(), style = MaterialTheme.typography.titleMedium)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(player.name, style = MaterialTheme.typography.titleSmall)
                            Text("${player.position} · ${player.height}", color = Muted, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                } }
                if (profile.roster.isEmpty()) item { Message("No roster available", if (profile.rosterUnavailable) "The roster service could not be reached." else "Players have not been announced.") }
            } else {
                val games = if (tab == "Results") profile.games.filter { it.state == "post" }.reversed() else profile.games.filter { it.state == "in" || (it.state != "post" && parseTimestamp(it.date)?.isAfter(java.time.Instant.now()) == true) }
                items(games, key = { it.key }) { game -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { Text(game.localDate.toString(), Modifier.padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.labelMedium); GameCard(game) { vm.selectedGame = game } } }
                if (games.isEmpty()) item { Message("No ${tab.lowercase()} available", if (profile.scheduleUnavailable) "The schedule service could not be reached." else "Check back when games are announced.") }
            }
        }
    }
}

private data class SportsChannel(val name: String, val description: String, val access: String, val url: String)
private val channels = listOf(
    SportsChannel("Red Bull TV", "Action sports, live events & replays", "Free", "https://www.redbull.tv/en_US"),
    SportsChannel("CBS Sports HQ", "24/7 sports news, highlights & analysis", "Free", "https://www.cbssports.com/watch/live"),
    SportsChannel("CBS Sports Golazo", "Soccer matches, news & highlights", "Free", "https://www.cbssports.com/watch/cbs-sports-golazo-network"),
    SportsChannel("ESPN", "Live sports & ESPN networks", "Subscription / TV provider", "https://www.espn.com/watch/"),
    SportsChannel("FOX Sports", "Live events & sports coverage", "Subscription / TV provider", "https://www.foxsports.com/live"),
    SportsChannel("FS1", "Live games & studio shows", "Subscription / TV provider", "https://www.foxsports.com/live/fs1"),
    SportsChannel("FS2", "More live sports", "Subscription / TV provider", "https://www.foxsports.com/live/fs2"))
private data class ChannelProvider(val name: String, val base: String, val suffix: String, val initial: String)
private val channelProviders = listOf(ChannelProvider("Ripple Plays", "https://rippleplays.shop/newhub/stream-", ".php", "1"), ChannelProvider("Stream HD 24/7", "https://shd247.xyz/source", ".html", "020"), ChannelProvider("Streams Center", "https://streams.center/embed/ch", ".php", "50"), ChannelProvider("Pro Streams", "https://prostreams.shop/now/stream-", ".php", "3"))

@Composable
fun SportsChannels() {
    val context = LocalContext.current
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Text("Sports channels", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text("Stream providers", style = MaterialTheme.typography.titleLarge)
        channelProviders.forEach { provider ->
            var number by rememberSaveable(provider.name) { mutableStateOf(provider.initial) }
            PagePanel {
                Text(provider.name, style = MaterialTheme.typography.titleMedium)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(number, { number = it.filter(Char::isDigit).take(5) }, label = { Text("Channel") }, shape = RoundedCornerShape(12.dp), singleLine = true, modifier = Modifier.weight(1f))
                    Button(onClick = { context.startActivity(PlayerActivity.streamIntent(context, provider.name, provider.base + number + provider.suffix)) }, modifier = Modifier.heightIn(min = 48.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black), enabled = number.isNotBlank()) { Text("Watch", maxLines = 1) }
                }
            }
        }
        Text("Broadcasters", style = MaterialTheme.typography.titleLarge)
        Text("Opens the broadcaster site. Availability varies by region.", color = Muted, style = MaterialTheme.typography.bodySmall)
        channels.forEach { channel -> Card(onClick = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(channel.url))) } }, shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = Panel, contentColor = MaterialTheme.colorScheme.onSurface)) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { Text(channel.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold); Text(channel.description, color = Muted, style = MaterialTheme.typography.bodyMedium); Text("${channel.access} ↗", color = StreamRed, style = MaterialTheme.typography.labelMedium) }
        } }
    }
}

@Composable
internal fun ScoringTable(game: Game, periods: List<StatRow>) {
    val scroll = rememberScrollState()
    val names = listOf("Team", game.away.abbreviation, game.home.abbreviation)
    val totals = listOf("Total", game.away.score.ifBlank { "—" }, game.home.score.ifBlank { "—" })
    Surface(Modifier.fillMaxWidth().padding(horizontal = 20.dp), shape = RoundedCornerShape(16.dp), color = Panel) {
        Row(Modifier.padding(vertical = 8.dp)) {
            Column(Modifier.width(64.dp)) { names.forEach { value -> Box(Modifier.height(48.dp).fillMaxWidth(),contentAlignment=Alignment.Center) { Text(value,style=MaterialTheme.typography.labelMedium,maxLines=1) } } }
            Row(Modifier.weight(1f).horizontalScroll(scroll)) {
                periods.forEachIndexed { i, period ->
                    val width = (maxOf(period.home.length,period.away.length,2)*9+22).coerceAtLeast(46).dp
                    Column(Modifier.width(width)) { listOf("${i+1}",period.away,period.home).forEachIndexed { index,value ->
                        Box(Modifier.height(48.dp).fillMaxWidth(),contentAlignment=Alignment.Center) { Text(value,maxLines=1,softWrap=false,style=MaterialTheme.typography.bodyMedium,color=if(index==0) Muted else MaterialTheme.colorScheme.onSurface) }
                    } }
                }
            }
            Column(Modifier.width((maxOf(game.away.score.length,game.home.score.length,3)*10+20).coerceAtLeast(64).dp)) {
                totals.forEach { value -> Box(Modifier.height(48.dp).fillMaxWidth(),contentAlignment=Alignment.Center) { Text(value,fontWeight=FontWeight.Bold,maxLines=1,softWrap=false,style=MaterialTheme.typography.bodyMedium) } }
            }
        }
    }
}
