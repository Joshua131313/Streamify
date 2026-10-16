package com.streamify.app.data
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
class BaseballLiveTest {
    @Test fun nicknamePreservesMultiWordTeams() {
        fun team(name: String) = Team("",name,"","","","")
        assertEquals("Thunder",team("Oklahoma City Thunder").cardName())
        assertEquals("Diamondbacks",team("Arizona Diamondbacks").cardName())
        assertEquals("Blue Jays",team("Toronto Blue Jays").cardName())
        assertEquals("Sabres",team("Buffalo Sabres").cardName())
    }
    @Test fun pitcherIsReadFromNormalizedAndEspnFeeds() {
        assertEquals("Pitcher",parseBaseball(JSONObject("""{"pitcher":{"name":"Pitcher","summary":"4 IP"}}"""))!!.pitcher)
        assertEquals("Pitcher",parseBaseball(JSONObject("""{"pitcher":{"athlete":{"displayName":"Pitcher"}}}"""),true)!!.pitcher)
    }
    @Test fun normalizedFeedIncludesBatterAndBases() {
        val live = parseBaseball(JSONObject("""{"bases":{"first":true,"second":false,"third":true},"balls":2,"strikes":1,"outs":2,"batter":{"name":"Aaron Judge","headshot":"https://example.test/batter.png","summary":"1 for 3"}}"""))!!
        assertEquals(true, live.first); assertEquals(false, live.second); assertEquals(true, live.third)
        assertEquals(2, live.balls); assertEquals(1, live.strikes); assertEquals(2, live.outs)
        assertEquals("Aaron Judge", live.batter); assertEquals("1 for 3", live.summary)
    }
    @Test fun espnAndMissingDataKeepUnknownCountsDistinctFromZero() {
        val live = parseBaseball(JSONObject("""{"onFirst":true,"outs":0,"batter":{"athlete":{"displayName":"Batter","headshot":{"href":"https://example.test/photo"}}}}"""), true)!!
        assertTrue(live.first!!); assertNull(live.second); assertNull(live.balls); assertEquals(0, live.outs)
        assertEquals("Batter", live.batter); assertEquals("https://example.test/photo", live.headshot)
        assertNull(parseBaseball(null))
    }
}
