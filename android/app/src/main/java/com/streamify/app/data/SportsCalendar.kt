package com.streamify.app.data

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

internal fun sportsDateWindow(today: LocalDate = LocalDate.now(), finalOnly: Boolean = false,
    earliestAvailable: LocalDate = today) = earliestAvailable..if (finalOnly) today else today.plusDays(13)

internal fun Game.isFinalOnOrBefore(today: LocalDate) = state == "post" && localDate?.let { it <= today } == true

data class CalendarEvents(val days: Map<LocalDate, Set<League>>, val unavailable: Set<League>)

internal fun CalendarEvents.forLeagues(selected: Set<League>) = CalendarEvents(
    days.mapValues { (_, leagues) -> leagues.intersect(selected) }, unavailable.intersect(selected)
)

private val calendarRequests = Semaphore(3)
private var cachedCalendar: Triple<LocalDate, Long, CalendarEvents>? = null

internal suspend fun calendarEvents(today: LocalDate): CalendarEvents {
    cachedCalendar?.let { if (it.first == today && System.currentTimeMillis() - it.second < 600_000 && it.third.unavailable.isEmpty()) return it.third }
    return loadCalendarEvents(today).also { cachedCalendar = Triple(today, System.currentTimeMillis(), it) }
}

/** ESPN scoreboard accepts single dates; bound concurrency and include local-midnight edges. */
internal suspend fun loadCalendarEvents(today: LocalDate, fetch: suspend (String) -> String = { request(it) }): CalendarEvents {
    val window = sportsDateWindow(today)
    val days = mutableMapOf<LocalDate, MutableSet<League>>()
    val unavailable = mutableSetOf<League>()
    val format = DateTimeFormatter.BASIC_ISO_DATE
    val results = coroutineScope {
        League.entries.flatMap { league ->
            (-1L..14L).map { offset -> async {
                try {
                    val day = today.plusDays(offset).format(format)
                    val json = calendarRequests.withPermit {
                        JSONObject(fetch("https://site.api.espn.com/apis/site/v2/sports/${league.sport}/${league.name.lowercase()}/scoreboard?dates=$day&limit=100"))
                    }
                    league to Result.success(json.getJSONArray("events").objects().mapNotNull { parseESPN(it, league) })
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    league to Result.failure<List<Game>>(error)
                }
            } }
        }.awaitAll()
    }
    results.forEach { (league, result) ->
        if (result.isFailure) unavailable.add(league)
        result.getOrDefault(emptyList()).forEach { game ->
            val date = game.localDate
            if (date != null && date in window) days.getOrPut(date) { mutableSetOf() }.add(league)
        }
    }
    return CalendarEvents(days, unavailable)
}
