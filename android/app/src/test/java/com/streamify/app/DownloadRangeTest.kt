package com.streamify.app
import com.streamify.app.downloads.DownloadRange
import org.junit.Assert.*
import org.junit.Test
class DownloadRangeTest {
    @Test fun requiresMatchingPartialResponse() {
        assertTrue(DownloadRange.valid(206,"bytes 1024-4095/4096",1024,4096))
        assertFalse(DownloadRange.valid(200,"bytes 1024-4095/4096",1024,4096))
        assertFalse(DownloadRange.valid(206,"bytes 0-4095/4096",1024,4096))
        assertFalse(DownloadRange.valid(206,"bytes 1024-8191/8192",1024,4096))
        assertFalse(DownloadRange.valid(206,null,1024,4096))
    }
}
