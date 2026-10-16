package com.streamify.app.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import org.json.JSONObject
import kotlin.coroutines.coroutineContext

data class LeagueTeam(val league: League, val team: Team)
data class RosterPlayer(val name: String, val number: String, val position: String, val height: String)
data class TeamProfile(val team: Team, val location: String, val venue: String, val games: List<Game>, val roster: List<RosterPlayer>, val scheduleUnavailable: Boolean, val rosterUnavailable: Boolean)
data class StatRow(val label: String, val away: String, val home: String)
data class GameCenter(val game: Game, val scoring: List<StatRow>, val stats: List<StatRow>, val latest: String)

object SportsData {
    suspend fun teamSchedule(item: LeagueTeam): List<Game> = get("${base(item.league)}/teams/${encode(item.team.id)}/schedule")
        .optJSONArray("events").objects().mapNotNull { parseESPN(it, item.league) }.sortedBy { it.date }
    private fun base(league: League) = "https://site.api.espn.com/apis/site/v2/sports/${league.sport}/${league.name.lowercase()}"
    private suspend fun get(url: String) = JSONObject(request(url))
    private fun team(json: JSONObject): Team = Team(json.text("id"), json.text("displayName"), json.text("abbreviation"),
        json.optJSONArray("logos")?.optJSONObject(0)?.text("href").orEmpty().ifBlank { json.text("logo") }, "", json.optJSONObject("record")?.optJSONArray("items")?.optJSONObject(0)?.text("summary").orEmpty())
    suspend fun teams(league: League): List<LeagueTeam> = get("${base(league)}/teams?limit=1000").optJSONArray("sports").objects()
        .flatMap { it.optJSONArray("leagues").objects() }.flatMap { it.optJSONArray("teams").objects() }.mapNotNull { it.optJSONObject("team") }
        .map { LeagueTeam(league, team(it)) }

    suspend fun profile(league: League, original: Team): TeamProfile = coroutineScope {
        val root = "${base(league)}/teams/${encode(original.id)}"
        suspend fun optional(url: String): JSONObject? = try { get(url) } catch (_: Exception) { coroutineContext.ensureActive(); null }
        val info = async { get(root) }
        val schedule = async { optional("$root/schedule") }
        val roster = async { optional("$root/roster") }
        val json = info.await().getJSONObject("team")
        val scheduleJson = schedule.await()
        val rosterJson = roster.await()
        val athletes = rosterJson?.optJSONArray("athletes").objects().flatMap { group -> group.optJSONArray("items")?.objects() ?: listOf(group) }
        TeamProfile(team(json), json.text("location"), json.optJSONObject("franchise")?.optJSONObject("venue")?.text("fullName").orEmpty(),
            scheduleJson?.optJSONArray("events").objects().mapNotNull { parseESPN(it, league) }.sortedBy { it.date },
            athletes.map { RosterPlayer(it.text("displayName"), it.text("jersey"), it.optJSONObject("position")?.text("abbreviation").orEmpty(), it.text("displayHeight")) }, scheduleJson == null, rosterJson == null)
    }

    suspend fun center(game: Game): GameCenter {
        val json = get("${base(game.league)}/summary?event=${encode(game.id)}")
        val header = json.optJSONObject("header")
        val fresh = header?.let { parseESPN(it, game.league) } ?: game
        val competitors = header?.optJSONArray("competitions")?.optJSONObject(0)?.optJSONArray("competitors").objects()
        fun side(name: String) = competitors.firstOrNull { it.text("homeAway") == name }
        val awayPeriods = side("away")?.optJSONArray("linescores").objects()
        val homePeriods = side("home")?.optJSONArray("linescores").objects()
        val periods = (0 until maxOf(awayPeriods.size, homePeriods.size)).map { i -> StatRow("${if (game.league == League.MLB) "Inning" else "Period"} ${i + 1}", awayPeriods.getOrNull(i)?.text("displayValue")?.ifBlank { awayPeriods[i].text("value") } ?: "—", homePeriods.getOrNull(i)?.text("displayValue")?.ifBlank { homePeriods[i].text("value") } ?: "—") }
        val teams = json.optJSONObject("boxscore")?.optJSONArray("teams").objects()
        fun stats(id: String) = teams.firstOrNull { it.optJSONObject("team")?.text("id") == id }?.optJSONArray("statistics").objects().associateBy { it.text("name") }
        val away = stats(game.away.id)
        val home = stats(game.home.id)
        val rows = (away.keys + home.keys).map { key -> StatRow((away[key] ?: home.getValue(key)).text("label").ifBlank { key }, away[key]?.text("displayValue") ?: "—", home[key]?.text("displayValue") ?: "—") }
        val latest = json.optJSONArray("plays")?.let { plays -> plays.optJSONObject(plays.length() - 1)?.text("text") }.orEmpty()
            .ifBlank { json.optJSONObject("drives")?.optJSONObject("current")?.optJSONArray("plays")?.objects()?.lastOrNull()?.text("text").orEmpty() }
        return GameCenter(fresh, periods, rows, latest)
    }
}
