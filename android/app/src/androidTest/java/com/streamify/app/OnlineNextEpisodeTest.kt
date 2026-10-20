package com.streamify.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.streamify.app.data.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate

@RunWith(AndroidJUnit4::class)
class OnlineNextEpisodeTest {
    @Test fun missingDatesDoNotDisableKnownEpisodes() {
        fun item(date:String)=Episode(2,"Second episode","","",date)
        val today=LocalDate.of(2026,10,20)
        assertTrue(episodeAvailable(item(""),today))
        assertTrue(episodeAvailable(item("null"),today))
        assertTrue(episodeAvailable(item("2026-10-20"),today))
        assertTrue(episodeAvailable(item("2020-01-01"),today))
        assertFalse(episodeAvailable(item("2026-10-21"),today))
    }
    @Test fun transientFailureRecoversAndFinalFailureRemainsDistinctFromSeriesEnd() = runBlocking {
        var attempts=0
        val next=retryEpisodeLookup {
            attempts++
            if(attempts<3) error("Temporary network failure")
            NextEpisode(2,1,"New season")
        }
        assertEquals(3,attempts)
        assertEquals(2,next.season)
        assertNull(retryEpisodeLookup<NextEpisode?> {null})
        attempts=0
        val result=runCatching {retryEpisodeLookup<NextEpisode> {attempts++;error("Offline")}}
        assertTrue(result.isFailure)
        assertEquals(3,attempts)
    }
    @Test fun cancelledLookupDoesNotRetry() = runBlocking {
        var attempts=0
        val job=launch {
            retryEpisodeLookup {attempts++;awaitCancellation()}
        }
        yield()
        job.cancelAndJoin()
        assertEquals(1,attempts)
    }
}
