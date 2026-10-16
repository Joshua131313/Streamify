package com.streamify.app.data

import org.junit.Assert.*
import org.junit.Test

class VideoFillTest {
    @Test fun wideScreenFillsWithoutStretching() {
        val fill = videoFill(2400f, 1080f, 240f, 0f, 1920f, 1080f)!!
        assertEquals(1.25f, fill.scale, .001f)
        assertEquals(0f, fill.offsetX, .001f)
        assertEquals(0f, fill.offsetY, .001f)
    }
    @Test fun offCenterProviderVideoIsCenteredBeforeCropping() {
        val fill = videoFill(2400f, 1080f, 300f, 250f, 1800f, 750f)!!
        assertEquals(1.44f, fill.scale, .001f)
        assertEquals(-122.4f, fill.offsetY, .001f)
    }
    @Test fun rejectsUnknownOrThumbnailDimensions() {
        assertNull(videoFill(2400f, 1080f, 0f, 0f, 0f, 0f))
        assertNull(videoFill(2400f, 1080f, 0f, 0f, 10f, 10f))
        assertNull(videoFill(2400f, 1080f, Float.NaN, 0f, 1920f, 1080f))
    }
}
