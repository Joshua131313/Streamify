package com.streamify.app.data
import org.junit.Test
import org.junit.Assert.*
class PlaybackCheckpointTest {
    private val media = Media(1, MediaType.MOVIE, "Test")
    @Test fun frequentEventsProduceMinuteCloudWritesAndFinalFlush() {
        var now = 1_000_000L
        val writes = mutableListOf<Pair<History,Boolean>>()
        val tracker = PlaybackCheckpoint(History(media), { entry, cloud -> writes += entry to cloud }, { now })
        repeat(125) { i -> now += 1000; tracker.sample(i+5.0, 3600.0) }
        assertEquals(3, writes.count { it.second })
        tracker.flush(); tracker.flush()
        assertEquals(4, writes.count { it.second })
        assertEquals(129.0, writes.last().first.positionSeconds, .001)
        assertTrue(writes.size <= 27)
    }
    @Test fun invalidLiveAndLoadingSamplesNeverEraseResume() {
        val writes = mutableListOf<History>()
        val tracker = PlaybackCheckpoint(History(media, positionSeconds=700.0, durationSeconds=3600.0), { entry, _ -> writes += entry })
        tracker.sample(0.0,3600.0); tracker.sample(Double.NaN,3600.0); tracker.sample(20.0,Double.POSITIVE_INFINITY)
        tracker.sample(50.0,30.0);tracker.sample(4000.0,3600.0);tracker.flush()
        assertTrue(writes.isEmpty())
        tracker.sample(710.0,3600.0)
        assertEquals(710.0,writes.single().positionSeconds,.001)
    }
    @Test fun completionAndEpisodeIdentityAreExplicit() {
        val entry = History(Media(2,MediaType.TV,"Show"),2,3,positionSeconds=950.0,durationSeconds=1000.0)
        assertTrue(entry.completed); assertFalse(entry.resumable)
        assertTrue(entry.copy(positionSeconds=500.0).resumable)
        assertEquals(3,entry.episode)
    }
}
