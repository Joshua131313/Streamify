package com.streamify.app.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.time.LocalDate

class SportsScheduleTest {
    private val date = LocalDate.of(2026, 10, 24)

    @Test fun temporaryDenialRecoversOncePerDate() = runBlocking {
        val calls = mutableMapOf<String, Int>()
        val result = loadSportsSchedule(League.NBA, date, retryDelayMillis = 0) { url ->
            val count = (calls[url] ?: 0) + 1
            calls[url] = count
            if (count == 1) throw HttpStatusException(403, "denied")
            "{\"events\":[]}"
        }
        assertFalse(result.partial)
        assertEquals(listOf(2, 2, 2), calls.values.toList())
    }

    @Test fun failedBackendFallsBackToPublicSchedule() = runBlocking {
        var upstreamCalls = 0
        val result = loadSportsSchedule(League.NBA, date, "https://example.com", 0) { url ->
            if (url.startsWith("https://example.com")) throw HttpStatusException(401, "denied")
            upstreamCalls++
            "{\"events\":[]}"
        }
        assertEquals(3, upstreamCalls)
        assertFalse(result.partial)
    }

    @Test fun incompleteDatesAreMarkedPartial() = runBlocking {
        val result = loadSportsSchedule(League.NBA, date, retryDelayMillis = 0) { url ->
            if (url.contains("dates=20261024")) throw HttpStatusException(403, "denied")
            "{\"events\":[]}"
        }
        assertTrue(result.partial)
    }

    @Test fun persistentFailureHasSportsMessageAndBoundedRetries() = runBlocking {
        var calls = 0
        try {
            loadSportsSchedule(League.NBA, date, retryDelayMillis = 0) {
                calls++
                throw HttpStatusException(403, "Check your API key")
            }
            fail("Expected an unavailable schedule")
        } catch (error: IOException) {
            assertTrue(error.message!!.contains("sports provider"))
            assertFalse(error.message!!.contains("API key"))
        }
        assertEquals(6, calls)
    }

    @Test fun rateLimitIsNotImmediatelyRetried() = runBlocking {
        var calls = 0
        try {
            loadSportsSchedule(League.NBA, date, retryDelayMillis = 0) {
                calls++
                throw HttpStatusException(429, "rate limit")
            }
            fail("Expected a rate limit")
        } catch (error: IOException) {
            assertTrue(error.message!!.contains("Wait a moment"))
        }
        assertEquals(3, calls)
    }

    @Test(expected = CancellationException::class)
    fun cancelledRequestDoesNotRetryOrFallBack(): Unit = runBlocking {
        loadSportsSchedule(League.NBA, date, "https://example.com", 0) { throw CancellationException() }
        Unit
    }
}
