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
    @Test fun providersKeepEpisodeAndLanguageExplicit() {
        val anime = Media(21, MediaType.ANIME, "One Piece")
        animeServers.forEach {
            val language = it.id.substringAfterLast('-')
            assertTrue(it.url(anime, 1, 108).endsWith("/21/108/$language"))
            assertTrue(httpsUrl(it.url(anime)))
        }
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
