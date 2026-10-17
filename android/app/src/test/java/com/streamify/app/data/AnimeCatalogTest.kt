package com.streamify.app.data

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AnimeCatalogTest {
    @Test fun animeIdsCannotCollideWithTmdbIds() {
        val anime = Media(21, MediaType.ANIME, "One Piece", poster = "https://s4.anilist.co/cover.jpg")
        assertNotEquals(Media(21, MediaType.TV, "Other title").key, anime.key)
        assertEquals(anime, Media.parse(anime.json()))
        assertEquals("https://s4.anilist.co/cover.jpg", anime.image())
    }
    @Test fun sourceSelectionNeverFallsBackToTheOtherLanguage() {
        val html = """<div class="type" data-type="sub"><li data-sv-id="323" data-link-id="sub-token">HD-1</li></div>
            <div class="type" data-type="dub"><li data-sv-id="323" data-link-id="dub-token">HD-1</li></div>"""
        assertEquals("sub-token", Anikoto.sourceToken(html, "sub", "323"))
        assertEquals("dub-token", Anikoto.sourceToken(html, "dub", "323"))
        assertNull(Anikoto.sourceToken(html, "dub", "missing"))
        assertFalse(Anikoto.watchUrl("https://evil.test/watch/cowboy"))
        assertFalse(Anikoto.watchUrl("https://anikoto.cz@evil.test/watch/cowboy"))
        assertTrue(Anikoto.watchUrl("https://anikoto.cz/watch/cowboy-bebop-kb7hu"))
    }
    @Test fun episodeParsingPreservesIdentityAndServerToken() {
        val episodes = Anikoto.episodes("""<a data-num="2" data-mal="1" data-ids="opaque-token"></a><a data-num="special" data-ids="other"></a>""")
        assertEquals(listOf(AnikotoEpisode(2, 1, "opaque-token")), episodes)
    }
    @Test fun scheduledEpisodesAreNotOfferedBeforeAiring() {
        assertEquals(0, AnimeCatalog.episodeCount(JSONObject("""{"status":"NOT_YET_RELEASED","episodes":12}""")))
        assertEquals(4, AnimeCatalog.episodeCount(JSONObject("""{"status":"RELEASING","episodes":12,"nextAiringEpisode":{"episode":5}}""")))
        assertEquals(12, AnimeCatalog.episodeCount(JSONObject("""{"status":"FINISHED","episodes":12}""")))
    }
    @Test fun networkErrorsExplainActualFailure() {
        assertTrue(playerLoadError(-2).contains("address could not be found"))
        assertTrue(playerLoadError(-11).contains("secure connection"))
    }
}
