package com.streamify.app.data

import org.junit.Assert.*
import org.junit.Test

class CloudContractsTest {
    @Test fun webMediaIdentityKeepsMovieAndSeriesSeparate() {
        val movie = CloudMediaRef.parse(mapOf("mediaId" to 42L, "mediaType" to "movie"))!!
        val series = CloudMediaRef.parse(mapOf("mediaId" to 42, "mediaType" to "tv"))!!
        assertNotEquals(movie.key, series.key)
        assertEquals("tv-42", series.documentId)
    }
    @Test fun malformedWebReferencesAreIgnored() {
        assertNull(CloudMediaRef.parse(mapOf("mediaId" to -1, "mediaType" to "movie")))
        assertNull(CloudMediaRef.parse(mapOf("mediaId" to 12, "mediaType" to "person")))
        assertNull(CloudMediaRef.parse(emptyMap()))
    }
    @Test fun followedTeamsNormalizeFeedAliasesToExistingWebAbbreviations() {
        assertEquals("NHL:LA", teamCloudKey(League.NHL, "LAK"))
        assertEquals("NBA:NY", teamCloudKey(League.NBA, "NYK"))
        assertEquals("MLB:CHW", teamCloudKey(League.MLB, "CWS"))
        assertNotEquals(teamCloudKey(League.NFL, "NY"), teamCloudKey(League.NBA, "NY"))
    }
    @Test fun genreIdsSurviveLocalPersistenceForWebHistory() {
        val media = Media(1, MediaType.TV, "Example", genreIds = listOf(18, 35))
        assertEquals(media, Media.parse(media.json()))
    }
}
