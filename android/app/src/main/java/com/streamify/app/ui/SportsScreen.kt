package com.streamify.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.lazy.rememberLazyListState
import kotlinx.coroutines.launch
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.CircleShape
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.streamify.app.*
import com.streamify.app.R
import com.streamify.app.data.*
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.coroutines.coroutineContext

fun League.accent() = when(this) { League.NFL -> Color(0xFFB6A5ED); League.NBA -> Color(0xFFF5A45D); League.WNBA -> Color(0xFFFB8673); League.NHL -> Color(0xFF7BC7F2); League.MLB -> Color(0xFF70C9A6) }
fun League.description() = when(this) { League.NFL -> "American football"; League.NBA, League.WNBA -> "Basketball"; League.NHL -> "Hockey"; League.MLB -> "Baseball" }

@Composable
fun LeagueLogo(league: League, modifier: Modifier = Modifier) {
    Image(painterResource(when(league) { League.NFL -> R.drawable.league_nfl; League.NBA -> R.drawable.league_nba; League.WNBA -> R.drawable.league_wnba; League.NHL -> R.drawable.league_nhl; League.MLB -> R.drawable.league_mlb }), league.name, modifier, contentScale = ContentScale.Fit)
}

@Composable
fun SportsScreen(vm: StreamifyViewModel) {
    val owner = LocalLifecycleOwner.current
    var view by rememberSaveable { mutableStateOf(if (vm.selectedLeagues.size == League.entries.size) "Home" else "Games") }
    var status by rememberSaveable { mutableStateOf("All games") }
    var query by rememberSaveable { mutableStateOf("") }
    var search by rememberSaveable { mutableStateOf(false) }
    var onlyFavorites by rememberSaveable { mutableStateOf(false) }
    var layout by rememberSaveable { mutableStateOf("List") }
    var leaguePicker by rememberSaveable { mutableStateOf(false) }
    var searchTab by rememberSaveable { mutableStateOf("Games") }
    LaunchedEffect(owner, vm.selectedLeagues, vm.day) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            try { while (true) { vm.loadSports(refresh = true); delay(60_000) } } finally { vm.stopSportsRefresh() }
        }
    }
    val state = vm.sports
    val games = state.data?.games.orEmpty().filter { game ->
        game.league in vm.selectedLeagues && (when(status) { "Live" -> game.live; "Final" -> game.isFinalOnOrBefore(LocalDate.now()); "Upcoming" -> game.state == "pre" && parseTimestamp(game.date)?.let { it.toEpochMilli() in System.currentTimeMillis()..System.currentTimeMillis() + 7_200_000 } == true; else -> true }) &&
            (!onlyFavorites || vm.isFollowing(game.league, game.home) || vm.isFollowing(game.league, game.away))
    }
    val scroll = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val searchFocus = remember { FocusRequester() }
    LaunchedEffect(vm.sportsSearchRequested) {
        if (vm.sportsSearchRequested) {
            search = true
            scroll.scrollToItem(0)
            withFrameNanos { }
            searchFocus.requestFocus()
            vm.sportsSearchRequested = false
        }
    }
    fun home() { search = false; query = ""; view = "Home"; status = "All games"; onlyFavorites = false; vm.chooseLeague(null); vm.chooseDay(LocalDate.now()); scope.launch { scroll.scrollToItem(0) } }
    fun choose(league: League?) { view = "Games"; status = "All games"; vm.chooseLeague(league); search = false; query = ""; scope.launch { scroll.scrollToItem(0) } }
    BackHandler(search || view != "Home") { if (search) { search = false; query = "" } else home() }
    if (leaguePicker) LeagueFilterDialog(vm.selectedLeagues, { leaguePicker = false }) { leagues ->
        vm.chooseLeagues(leagues)
        view = "Games"
        leaguePicker = false
    }
    val results = if (search) rememberSportsSearch(vm, query) else null
    Column {
    if (view != "Home" || search) Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { if (search) { search = false; query = "" } else home() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, if (search) "Close sports search" else "Back to sports home") }
        Text(if (search) "Search sports" else if (view == "Channels") "Sports channels" else "${if (vm.selectedLeagues.size == League.entries.size) "All leagues" else League.entries.filter { it in vm.selectedLeagues }.joinToString(" + ") { it.name }} schedule", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
    LazyColumn(state = scroll, modifier = Modifier.weight(1f), contentPadding = PaddingValues(top = 12.dp, bottom = rootContentBottomPadding()), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (view == "Home" && !search) SectionLabel("Every game. Your teams.", "Scores, schedules, and a front-row seat.")
            PageSearchField(query, { query = it; search = it.isNotBlank() }, "Search teams & games", Modifier.focusRequester(searchFocus))
            if (!search) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("GAME DAY", Modifier.weight(1f), color = Muted, style = MaterialTheme.typography.labelMedium)
                SecondaryButton(onClick = { vm.navigate(Destination.MultiWatch) }, shape = RoundedCornerShape(12.dp),
                    border = BorderStroke(1.dp, Muted.copy(alpha = .25f)), colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Icon(Icons.Rounded.GridView, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp))
                    Text("Multi-watch · ${vm.multiWatch.size}/4", maxLines = 1, fontSize = 12.sp)
                }
            }
        } }
        if (results != null) {
            sportsSearchResults(results, query, searchTab, { searchTab = it }, vm, ::choose)
        } else {
            item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                item { SportsNavTile("All", view == "Home", { home() }) { Icon(Icons.Rounded.Home, null, Modifier.size(30.dp)) } }
                item { SportsNavTile("Live now", view == "Games" && status == "Live", { choose(null); status = "Live"; vm.chooseDay(LocalDate.now()) }) { Icon(Icons.Rounded.Sensors, null, Modifier.size(28.dp), tint = if (view == "Games" && status == "Live") StreamRed else Muted) } }
                items(League.entries) { league -> SportsNavTile(league.name, vm.selectedLeagues == setOf(league) && view == "Games", { choose(league) }) { LeagueLogo(league, Modifier.size(36.dp)) } }
                item { SportsNavTile("Channels", view == "Channels", { view = "Channels" }) { Icon(Icons.Rounded.LiveTv, null, Modifier.size(30.dp)) } }
            } }
            if (view == "Home") {
                for (league in League.entries) {
                    item { Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        LeagueLogo(league, Modifier.size(36.dp)); Text(league.name, Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        SecondaryButton(onClick = { choose(league) }) { Text("View all", style = MaterialTheme.typography.labelMedium) }
                    } }
                    val leagueGames = state.data?.games.orEmpty().filter { it.league == league }.take(3)
                    items(leagueGames, key = { "home-${it.key}" }) { GameCard(it) { vm.selectedGame = it } }
                    if (leagueGames.isEmpty()) item { Text(if (state.loading) "Updating games…" else if (state.error != null || state.data?.partial == true) "Schedule temporarily unavailable." else "No games scheduled today.", Modifier.padding(horizontal = 20.dp), color = Muted) }
                }
            } else if (view == "Channels") {
                item { SportsChannels() }
            } else {
                item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item { FilterPill(if (vm.selectedLeagues.size == League.entries.size) "All leagues" else "Leagues (${vm.selectedLeagues.size})", true, { leaguePicker = true }, leading = { Icon(Icons.Rounded.Tune, null, Modifier.size(16.dp)) }) }
                    items(listOf("All games", "Live", "Upcoming", "Final")) { value -> FilterPill(value, status == value, { status = value; if (value == "Upcoming" || value == "Final" || value == "Live") vm.chooseDay(LocalDate.now()) }, leading = if(value == "Live") ({ Icon(Icons.Rounded.Sensors,null,Modifier.size(16.dp),tint=if(status=="Live") StreamRed else Muted) }) else null) }
                    item { FilterPill("Following", onlyFavorites, { onlyFavorites = !onlyFavorites }) }
                } }
                if (status != "Live") item { SportsScheduleControls(vm.day, layout, state.loading, vm.selectedLeagues, status == "Final", { date -> if (status != "Final" || date <= LocalDate.now()) vm.chooseDay(date) }, { layout = it }, { vm.loadSports(true) }) }
                if (state.loading) {
                    item { SportsLoading() }
                    if (state.data == null) items(2) { GamePlaceholder() }
                }
                state.error?.let { item { ErrorBanner(it) { vm.loadSports(true) } } }
                if (state.data?.partial == true) item { ErrorBanner("Some leagues or dates could not be loaded.") { vm.loadSports(true) } }
                if (!state.loading && state.error == null && games.isEmpty()) item { Message("No games here", if (status == "Upcoming") "No games start in the next two hours." else "Try another day or filter. Follow a team from its profile.") }
                if (layout == "Slider" && status != "Live") item { LazyRow { items(games, key = { it.key }) { Box(Modifier.width(340.dp)) { GameCard(it) { vm.selectedGame = it } } } } }
                else items(games, key = { it.key }) { GameCard(it) { vm.selectedGame = it } }
                item { Text("Scores refresh every minute. Times are local.", Modifier.padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.labelSmall) }
            }
        }
    }
}

}

@Composable
private fun SportsNavTile(label: String, selected: Boolean, onClick: () -> Unit, icon: @Composable () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(16.dp),
        color = if (selected) MaterialTheme.colorScheme.onSurface.copy(alpha = .14f) else Panel,
        border = BorderStroke(1.dp, if (selected) Muted.copy(alpha = .6f) else Muted.copy(alpha = .08f))) {
        Column(Modifier.width(76.dp).padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(36.dp), contentAlignment = Alignment.Center) { icon() }
            Text(label, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1)
        }
    }
}

@Composable
fun GameCard(game: Game, select: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var expanded by rememberSaveable(game.key) { mutableStateOf(false) }
    val play = { context.startActivity(com.streamify.app.PlayerActivity.gameIntent(context, game)) }
    Card(onClick = select, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp), shape = RoundedCornerShape(18.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .06f)),
        colors = CardDefaults.cardColors(containerColor = Panel, contentColor = MaterialTheme.colorScheme.onSurface)) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Surface(color = if (game.live) StreamRed.copy(alpha = .14f) else Muted.copy(alpha = .08f), shape = CircleShape) {
                    Text(if (game.live) "● LIVE" else if (game.state == "post") "FINAL" else "UPCOMING", Modifier.padding(horizontal = 10.dp, vertical = 5.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (game.live) StreamRed else Muted)
                }
                Text(game.localDate?.format(DateTimeFormatter.ofPattern("MMM d")).orEmpty(), Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.End, style = MaterialTheme.typography.labelSmall, color = Muted)
                if (game.canWatch()) Button(onClick = play, shape = CircleShape, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black)) {
                    Icon(Icons.Rounded.PlayArrow, null, Modifier.size(22.dp)); Spacer(Modifier.width(4.dp)); Text("Watch", fontSize = 15.sp, maxLines = 1)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                MatchTeam(game.away, Modifier.weight(1f))
                Column(Modifier.widthIn(min = 100.dp, max = 130.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (game.league == League.MLB && game.live) {
                        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(5.dp)) {
                            Text(game.away.score.ifBlank { "—" },fontSize=20.sp,fontWeight=FontWeight.Bold,maxLines=1,softWrap=false)
                            BaseballDiamond(game.baseball)
                            Text(game.home.score.ifBlank { "—" },fontSize=20.sp,fontWeight=FontWeight.Bold,maxLines=1,softWrap=false)
                        }
                    } else Text(if (game.state == "pre") gameTime(game) else "${game.away.score.ifBlank { "—" }} : ${game.home.score.ifBlank { "—" }}",fontSize=if(game.state=="pre") 16.sp else 22.sp,maxLines=1,softWrap=false,fontWeight=FontWeight.Bold,textAlign=androidx.compose.ui.text.style.TextAlign.Center)
                    Text(if (game.state != "pre") game.status else "vs", style = MaterialTheme.typography.labelSmall, color = Muted, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
                MatchTeam(game.home, Modifier.weight(1f))
            }
            if (game.league == League.MLB && game.live) {
                SecondaryButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(vertical = 4.dp)) {
                    Text(if (expanded) "Hide matchup" else "Batter & pitcher", style = MaterialTheme.typography.labelSmall)
                    Spacer(Modifier.width(6.dp)); Icon(if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null, Modifier.size(18.dp))
                }
                androidx.compose.animation.AnimatedVisibility(expanded) { BaseballCardLive(game.baseball) }
            }

        }
    }
}

@Composable
private fun MatchTeam(team: Team, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        RemoteImage(team.logo, null, Modifier.size(36.dp).padding(2.dp), ContentScale.Fit)
        Text(team.cardName(), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (team.record.isNotBlank()) Text(team.record, fontSize = 10.sp, color = Muted)
    }
}

@Composable
fun TeamRow(team: Team, score: Boolean, trailing: (@Composable () -> Unit)? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        RemoteImage(team.logo, null, Modifier.size(38.dp).padding(2.dp), ContentScale.Fit)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) { Text(team.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold); if (team.record.isNotBlank()) Text(team.record, style = MaterialTheme.typography.labelSmall, color = Muted) }
        if (score) Text(team.score.ifBlank { "—" }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        trailing?.invoke()
    }
}

@Composable
fun TeamButton(team: Team, league: League, vm: StreamifyViewModel) {
    Card(onClick = { vm.navigate(Destination.TeamDetail(league, team)) }, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp), shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = Panel, contentColor = MaterialTheme.colorScheme.onSurface)) {
        Row(Modifier.padding(20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.weight(1f)) { TeamRow(team, false) }; Icon(Icons.Rounded.ChevronRight, "Team schedule and roster", Modifier.size(20.dp), tint = Muted) }
    }
}

fun gameTime(game: Game): String = parseTimestamp(game.date)?.atZone(ZoneId.systemDefault())?.format(DateTimeFormatter.ofPattern("h:mm a")) ?: game.status

@Composable
private fun BaseballDiamond(live: BaseballLive?) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        androidx.compose.foundation.Canvas(Modifier.size(48.dp).semantics { contentDescription = "Bases: first ${live?.first}, second ${live?.second}, third ${live?.third}; ${live?.outs ?: "unknown"} outs" }) {
            val r = size.width * .15f
            listOf(Triple(.72f,.48f,live?.first),Triple(.5f,.26f,live?.second),Triple(.28f,.48f,live?.third)).forEach { (x,y,occupied) ->
                val cx=size.width*x; val cy=size.height*y
                val path=androidx.compose.ui.graphics.Path().apply { moveTo(cx,cy-r);lineTo(cx+r,cy);lineTo(cx,cy+r);lineTo(cx-r,cy);close() }
                drawPath(path, if(occupied==true) Color(0xFFF0C674) else Color(0xFF414751))
            }
            repeat(3) { i -> drawCircle(if(live?.outs != null && i<live.outs) Color(0xFFF0C674) else Color(0xFF414751), size.width*.045f, androidx.compose.ui.geometry.Offset(size.width*(.34f+i*.16f),size.height*.82f)) }
        }
        Text(if(live?.balls!=null && live.strikes!=null) "${live.balls}–${live.strikes}" else "—", color=Muted, style=MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun BaseballCardLive(live: BaseballLive?) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf(Triple("AT BAT",live?.batter.orEmpty(),live?.summary.orEmpty()),Triple("PITCHING",live?.pitcher.orEmpty(),live?.pitcherSummary.orEmpty())).forEachIndexed { index, (label,name,summary) ->
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                val photo=if(index==0) live?.headshot else live?.pitcherHeadshot
                if(!photo.isNullOrBlank()) RemoteImage(photo,null,Modifier.size(36.dp).clip(CircleShape),ContentScale.Fit)
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
                    Text(label,color=Muted,style=MaterialTheme.typography.labelSmall)
                    Text(name.ifBlank { "Awaiting live update" },style=MaterialTheme.typography.titleSmall,maxLines=1,overflow=TextOverflow.Ellipsis)
                    if(summary.isNotBlank()) Text(summary,color=Muted,style=MaterialTheme.typography.bodySmall,maxLines=2,overflow=TextOverflow.Ellipsis)
                }
            }
        }
    }
}
