package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.streamify.app.*
import com.streamify.app.data.*
import kotlinx.coroutines.*
import kotlin.coroutines.coroutineContext

data class SportsSearchResults(val teams: List<LeagueTeam> = emptyList(), val games: List<Game> = emptyList(), val loading: Boolean = true, val partial: Boolean = false)

@Composable
fun rememberSportsSearch(vm: StreamifyViewModel, query: String): SportsSearchResults {
    val teams by produceState<Pair<List<LeagueTeam>, Boolean>?>(null) {
        value = coroutineScope { League.entries.map { league -> async {
            try { SportsData.teams(league) to false } catch (_: Exception) { coroutineContext.ensureActive(); emptyList<LeagueTeam>() to true }
        } }.awaitAll().let { rows -> rows.flatMap { it.first } to rows.any { it.second } } }
    }
    val daily by produceState<Pair<List<Game>, Boolean>?>(null, vm.day) {
        value = null
        value = coroutineScope { League.entries.map { league -> async {
            try { vm.repository.schedule(league, vm.day).let { it.games to it.partial } } catch (_: Exception) { coroutineContext.ensureActive(); emptyList<Game>() to true }
        } }.awaitAll().let { rows -> rows.flatMap { it.first } to rows.any { it.second } } }
    }
    val schedules by produceState<Pair<List<Game>, Boolean>?>(null, query, teams) {
        value = null
        delay(350)
        value = coroutineScope { searchScheduleTeams(query, teams?.first.orEmpty()).map { team -> async {
            try { SportsData.teamSchedule(team) to false } catch (_: Exception) { coroutineContext.ensureActive(); emptyList<Game>() to true }
        } }.awaitAll().let { rows -> rows.flatMap { it.first } to rows.any { it.second } } }
    }
    return SportsSearchResults(
        teams?.first.orEmpty().filter { sportsSearchMatches(query, it.team.name, it.team.abbreviation, it.league.name, it.league.sport) },
        (daily?.first.orEmpty() + schedules?.first.orEmpty()).distinctBy { it.key }.filter { it.matchesSportsSearch(query) }
            .sortedWith(compareByDescending<Game> { it.live }.thenByDescending { it.state != "post" }.thenBy { it.date }),
        teams == null || daily == null || schedules == null,
        teams?.second == true || daily?.second == true || schedules?.second == true)
}

fun LazyListScope.sportsSearchResults(results: SportsSearchResults, query: String, tab: String, selectTab: (String) -> Unit, vm: StreamifyViewModel, choose: (League?) -> Unit) {
    val leagues = League.entries.filter { sportsSearchMatches(query, it.name, it.sport, it.description()) }
    if (leagues.isNotEmpty()) item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(leagues) { league -> FilterPill(league.name, false, { choose(league) }, leading = { LeagueLogo(league, Modifier.size(28.dp)) }) }
    } }
    item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        item { FilterPill("Games · ${results.games.size}", tab == "Games", { selectTab("Games") }) }
        item { FilterPill("Teams · ${results.teams.size}", tab == "Teams", { selectTab("Teams") }) }
    } }
    if (results.loading) item { SportsLoading("Searching teams & games") }
    if (results.partial) item { Text("Some results are unavailable. Clear the search and try again to reload.", Modifier.padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.bodySmall) }
    if (tab == "Teams") {
        items(results.teams, key = { "search-team-${it.league}-${it.team.id}" }) { TeamButton(it.team, it.league, vm) }
        if (!results.loading && results.teams.isEmpty()) item { Message("No matching teams", "Try a team name, abbreviation, or league.") }
    } else {
    item { Text("Games on ${vm.day}, plus season schedules for the closest matching teams.", Modifier.padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.bodySmall) }
    items(results.games, key = { "search-game-${it.key}" }) { GameCard(it) { vm.selectedGame = it } }
    if (!results.loading && results.games.isEmpty()) item { Message("No matching games", "Try a team, abbreviation, or matchup such as Lakers vs Warriors. You can also choose a different date.") }
    }
}
