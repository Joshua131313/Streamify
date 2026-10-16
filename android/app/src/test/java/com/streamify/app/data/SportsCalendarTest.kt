package com.streamify.app.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class SportsCalendarTest {
    @Test fun watchIsAvailableOnlyLiveOrWithinOneHourBeforeStart() {
        val now = java.time.Instant.parse("2026-10-16T12:00:00Z")
        val team = Team("1", "Team", "T", "", "", "")
        val game = Game("1", League.NBA, now.plusSeconds(3600).toString(), "pre", "", team, team, "", "", "")
        assertTrue(game.canWatch(now))
        assertTrue(game.copy(date = now.toString()).canWatch(now))
        assertFalse(game.copy(date = now.plusSeconds(3601).toString()).canWatch(now))
        assertFalse(game.copy(date = now.minusSeconds(1).toString()).canWatch(now))
        assertFalse(game.copy(state = "post").canWatch(now))
        assertFalse(game.copy(date = "invalid").canWatch(now))
        assertTrue(game.copy(state = "in", date = now.minusSeconds(7200).toString()).canWatch(now))
    }

    @Test fun finalDatesExcludeFutureAndAllowHistoryWhenAvailable() {
        val today = LocalDate.of(2026, 10, 15)
        assertEquals(today..today, sportsDateWindow(today, finalOnly = true))
        val historic = sportsDateWindow(today, finalOnly = true, earliestAvailable = today.minusDays(13))
        assertTrue(today.minusDays(1) in historic)
        assertFalse(today.plusDays(1) in historic)
        val team = Team("1", "Team", "T", "", "", "")
        val game = Game("1", League.NBA, "2026-10-15T12:00:00Z", "post", "Final", team, team, "", "", "")
        assertTrue(game.isFinalOnOrBefore(today))
        assertFalse(game.copy(date = "2026-10-17T12:00:00Z").isFinalOnOrBefore(today))
        assertFalse(game.copy(state = "pre").isFinalOnOrBefore(today))
        assertTrue(game.copy(date = "2026-10-13T12:00:00Z").isFinalOnOrBefore(today))
    }
    @Test fun markersAndUnavailableWarningsFollowSelectedLeagues() {
        val day = LocalDate.of(2026, 10, 15)
        val events = CalendarEvents(mapOf(day to setOf(League.NBA, League.NFL, League.NHL)), setOf(League.WNBA))
        assertEquals(setOf(League.NBA), events.forLeagues(setOf(League.NBA)).days[day])
        assertTrue(events.forLeagues(setOf(League.NBA)).unavailable.isEmpty())
        assertEquals(setOf(League.NBA, League.NHL), events.forLeagues(setOf(League.NBA, League.NHL)).days[day])
        assertEquals(events, events.forLeagues(League.entries.toSet()))
    }
    @Test fun windowIncludesExactlyFourteenDaysAcrossYearBoundary() {
        val start = LocalDate.of(2026, 12, 26)
        val window = sportsDateWindow(start)
        assertEquals(LocalDate.of(2027, 1, 8), window.endInclusive)
        assertFalse(start.minusDays(1) in window)
        assertFalse(start.plusDays(14) in window)
    }

    @Test fun rangeQueriesDistinguishUnavailableFromEmptySchedules() = runBlocking {
        val urls = mutableListOf<String>()
        val result = loadCalendarEvents(LocalDate.of(2026, 10, 15)) { url ->
            urls.add(url)
            if (url.contains("/nhl/")) throw HttpStatusException(403, "Unavailable")
            "{\"events\":[]}"
        }
        assertEquals(80, urls.size)
        assertTrue(urls.any { it.contains("dates=20261014&") })
        assertTrue(urls.any { it.contains("dates=20261029&") })
        assertFalse(urls.any { it.contains("dates=20261030&") })
        assertEquals(setOf(League.NHL), result.unavailable)
        assertTrue(result.days.isEmpty())
    }
}
