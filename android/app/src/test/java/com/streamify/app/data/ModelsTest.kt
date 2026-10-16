package com.streamify.app.data

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class ModelsTest {
    @Test fun gamePlayerPayloadSurvivesActivitySerialization() {
        val home = Team("1", "Home", "HOM", "", "2", "")
        val away = Team("2", "Away", "AWY", "", "1", "")
        val game = Game("42", League.NHL, "2026-10-15T23:00Z", "in", "Live", home, away, "Arena", "TV", "https://example.com")
        val bytes = java.io.ByteArrayOutputStream()
        java.io.ObjectOutputStream(bytes).use { it.writeObject(game) }
        val restored = java.io.ObjectInputStream(java.io.ByteArrayInputStream(bytes.toByteArray())).use { it.readObject() }
        assertEquals(game, restored)
    }

    @Test fun playerFramePreservesProviderParametersAndDoesNotAllowAttributeInjection() {
        val page = playerDocument("https://example.com/embed/1?color=FFFF&season=2")
        assertTrue(page.contains("color=FFFF&amp;season=2"))
        assertTrue(page.contains("allowfullscreen"))
        assertThrows(IllegalArgumentException::class.java) { playerDocument("javascript:alert(1)") }
    }
    @Test fun teamScheduleParserSupportsObjectScoresAndCompetitionDates() {
        val json = JSONObject("""{"id":"123","competitions":[{"date":"2026-10-15T01:00Z","competitors":[{"homeAway":"home","score":{"displayValue":"4"},"team":{"id":"1","displayName":"Home","logos":[{"href":"https://example.com/logo.png"}]}},{"homeAway":"away","score":{"displayValue":"2"},"team":{"id":"2","displayName":"Away"}}]}]}""")
        val game = parseESPN(json, League.NHL)!!
        assertEquals("4", game.home.score)
        assertEquals("https://example.com/logo.png", game.home.logo)
        assertNotNull(game.localDate)
    }
    @Test fun scoreboardTimestampsAllowOmittedSecondsAndTimezoneOffsets() {
        val expected = Instant.parse("2026-10-14T23:30:00Z")
        assertEquals(expected, parseTimestamp("2026-10-14T23:30Z"))
        assertEquals(expected, parseTimestamp("2026-10-14T23:30:00Z"))
        assertEquals(expected, parseTimestamp("2026-10-14T19:30-04:00"))
        assertNull(parseTimestamp("invalid"))
    }
    @Test fun mixedSearchExcludesPeopleAndSeparatesMovieAndTVIds() {
        assertNull(Media.parse(JSONObject("""{"id":123,"media_type":"person","name":"Someone"}""")))
        val movie = Media.parse(JSONObject("""{"id":123,"media_type":"movie","title":"Film","poster_path":null}"""))!!
        val series = Media.parse(JSONObject("""{"id":123,"media_type":"tv","name":"Series","first_air_date":"2024-01-01"}"""))!!
        assertNotEquals(movie.key, series.key)
        assertNull(movie.image())
        assertEquals("Series", series.title)
        assertEquals("2024", series.year)
        assertEquals(series, Media.parse(series.json()))
    }

    @Test fun providerUrlsSubstituteMovieAndEpisodeWithoutMixingTemplates() {
        val server = MediaServer("test", "Test", "https://example.com/movie/{id}", "https://example.com/tv/{id}/{season}/{episode}")
        assertEquals("https://example.com/movie/42", server.url(Media(42, MediaType.MOVIE, "Film")))
        assertEquals("https://example.com/tv/42/2/3", server.url(Media(42, MediaType.TV, "Series"), 2, 3))
        assertEquals("https://example.com/tv/42/1/1", server.url(Media(42, MediaType.TV, "Series"), 0, -5))
    }

    @Test fun playerRejectsUnsafeOrIncompleteAddresses() {
        listOf("http://example.com", "javascript:alert(1)", "file:///etc/passwd", "intent://video", "https://", "https://user:password@example.com").forEach {
            assertFalse(it, httpsUrl(it))
        }
        assertTrue(httpsUrl("https://example.com/video?a=1"))
    }

    @Test fun streamMatchingRequiresBothFullTeamNamesCorrectSportAndRecentDate() {
        val now = 1_700_000_000_000L
        val home = Team("1", "Los Angeles Lakers", "LAL", "", "", "")
        val away = Team("2", "Boston Celtics", "BOS", "", "", "")
        val game = Game("1", League.NBA, "", "in", "", home, away, "", "", "")
        val source = listOf(StreamSource("alpha", "1"))
        val good = StreamMatch("LA Lakers vs Boston Celtics", "basketball", now, "", "", source)
        val wrongSport = good.copy(category = "baseball")
        val wrongTeam = good.copy(title = "LA Clippers vs Boston Celtics")
        val stale = good.copy(date = now - 24 * 60 * 60 * 1000)
        val empty = good.copy(sources = emptyList())
        assertEquals(good, findMatch(listOf(wrongSport, wrongTeam, stale, empty, good), game, now))
        assertNull(findMatch(listOf(wrongSport, wrongTeam, stale, empty), game, now))
        assertEquals("saintlouisblues", normalizeTeam("St. Louis Blues"))
    }

    @Test fun espnParserAcceptsReversedCompetitorOrderAndMissingOptionalFields() {
        val json = JSONObject("""{"id":"1","date":"2026-10-15T01:00:00Z","status":{"type":{"state":"in","shortDetail":"Q2 2:00"}},"competitions":[{"competitors":[{"homeAway":"away","score":"20","team":{"id":"a","displayName":"Away","abbreviation":"AWY"}},{"homeAway":"home","score":"30","team":{"id":"h","displayName":"Home","abbreviation":"HME"}}]}]}""")
        val game = parseESPN(json, League.NBA)!!
        assertTrue(game.live)
        assertEquals("Home", game.home.name)
        assertEquals("20", game.away.score)
        assertEquals("Q2 2:00", game.status)
        assertNull(parseESPN(JSONObject("""{"id":"broken"}"""), League.NBA))
    }

    @Test fun backendParserMatchesExistingScheduleContract() {
        val json = JSONObject("""{"id":"1","date":"2026-10-15T01:00:00Z","state":"post","status":"Final","homeTeam":{"id":"a","name":"Home","score":3},"awayTeam":{"id":"b","name":"Away","score":2},"venue":{"name":"Arena"},"broadcasts":["ESPN","TSN"]}""")
        val game = parseBackendGame(json, League.NHL)
        assertEquals("3", game.home.score)
        assertEquals("Arena", game.venue)
        assertEquals("ESPN · TSN", game.broadcasts)
        assertFalse(game.live)
    }
}
