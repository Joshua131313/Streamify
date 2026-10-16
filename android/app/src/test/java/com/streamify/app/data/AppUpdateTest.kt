package com.streamify.app.data

import org.junit.Test
import org.junit.Assert.*

class AppUpdateTest {
    private fun manifest(url: String = "https://github.com/Joshua131313/streamify/releases/download/android-v3/Streamify.apk", code: Int = 3, hash: String = "a".repeat(64), size: Long = 1234) = """{"versionCode":$code,"versionName":"1.0.2","url":"$url","sha256":"$hash","size":$size}"""
    @Test fun parsesValidRelease() { assertEquals(3L, AppUpdate.parse(manifest()).versionCode) }
    @Test fun rejectsOtherRepositoriesAndUnsafeAddresses() {
        listOf("http://github.com/Joshua131313/streamify/releases/download/android-v3/app.apk", "https://github.com/attacker/streamify/releases/download/android-v3/app.apk", "https://github.com.evil.test/Joshua131313/streamify/releases/download/android-v3/app.apk", "https://github.com@evil.test/Joshua131313/streamify/releases/download/android-v3/app.apk").forEach { assertFalse(AppUpdate.trustedAsset(it)) }
    }
    @Test fun rejectsInvalidVersionsSizesAndDigests() {
        listOf(manifest(code=0), manifest(hash="invalid"), manifest(size=0), manifest(size=300000000)).forEach { raw -> assertTrue(runCatching { AppUpdate.parse(raw) }.isFailure) }
    }
}
