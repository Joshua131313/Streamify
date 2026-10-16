package com.streamify.app.data

import java.text.Normalizer
import java.util.Locale

fun sportsSearchTerms(query: String): List<String> = Normalizer.normalize(query.lowercase(Locale.ROOT), Normalizer.Form.NFD)
    .replace(Regex("\\p{M}+"), "").replace(Regex("[^a-z0-9]+"), " ").trim().split(Regex("\\s+"))
    .filter { it.isNotBlank() && it !in setOf("vs", "versus", "at", "v") }

fun sportsSearchMatches(query: String, vararg fields: String): Boolean {
    val words = sportsSearchTerms(fields.joinToString(" "))
    val terms = sportsSearchTerms(query)
    return terms.isNotEmpty() && terms.all { term -> words.any { it.startsWith(term) } }
}

fun Game.matchesSportsSearch(query: String) = sportsSearchMatches(query, home.name, home.abbreviation,
    away.name, away.abbreviation, league.name, league.sport, venue, broadcasts,
    if (live) "live" else if (state == "post") "final finished" else "upcoming scheduled")

/** Fetch schedules only for teams named by the query, rather than every team in a league. */
fun searchScheduleTeams(query: String, teams: List<LeagueTeam>): List<LeagueTeam> {
    val terms = sportsSearchTerms(query).filter { it.length >= 2 }
    return teams.map { item -> item to terms.count { sportsSearchMatches(it, item.team.name, item.team.abbreviation) } }
        .filter { it.second > 0 }.sortedByDescending { it.second }.take(6).map { it.first }
}
