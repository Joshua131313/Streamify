package com.streamify.app.data

import org.junit.Assert.*
import org.junit.Test

class SportsSearchTest {
    private val lakers = Team("13", "Los Angeles Lakers", "LAL", "", "105", "")
    private val warriors = Team("9", "Golden State Warriors", "GS", "", "99", "")
    private val game = Game("1", League.NBA, "2026-10-15T23:00Z", "in", "4th", warriors, lakers, "Chase Center", "ESPN", "")
    @Test fun matchesBothSidesAndAbbreviations() {
        assertTrue(game.matchesSportsSearch("lakers vs warriors"))
        assertTrue(game.matchesSportsSearch("LAL at GS"))
        assertTrue(game.matchesSportsSearch("live nba"))
        assertFalse(game.matchesSportsSearch("lakers vs celtics"))
    }
    @Test fun leagueNamesDoNotMatchOtherLeaguesAsSubstrings() {
        assertFalse(sportsSearchMatches("NBA", "WNBA"))
        assertTrue(sportsSearchMatches("NBA", "NBA", "basketball"))
    }
    @Test fun accentsPunctuationAndPartialNamesAreSearchable() {
        assertTrue(sportsSearchMatches("montreal", "Montréal Canadiens"))
        assertTrue(game.matchesSportsSearch("golden-sta"))
        assertFalse(game.matchesSportsSearch("vs"))
    }
    @Test fun matchupLoadsBothTeamSchedulesButLeagueOnlyDoesNotFanOut() {
        val teams = listOf(LeagueTeam(League.NBA, lakers), LeagueTeam(League.NBA, warriors))
        assertEquals(2, searchScheduleTeams("Lakers vs Warriors", teams).size)
        assertEquals(0, searchScheduleTeams("NBA", teams).size)
    }
}
