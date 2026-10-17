package com.streamify.app

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.streamify.app.data.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AnimeFlowTest {
    @Test fun catalogAndDubPreferenceOpenCorrectPlayer() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        Configurator.getInstance().waitForIdleTimeout = 100
        val catalog = AnimeCatalog.catalog(1, "Cowboy Bebop", false)
        val anime = catalog.items.first { it.id == 1 }
        assertEquals(MediaType.ANIME, anime.type)
        assertTrue(AnimeCatalog.episodes(anime.id).isNotEmpty())
        val store = LocalStore(context)
        val original = store.animeServerId
        val sub = Anikoto.resolve(anime, 1, "anime-anikoto-323-sub")
        val dub = Anikoto.resolve(anime, 1, "anime-anikoto-323-dub")
        assertTrue(sub.url.contains("/sub"))
        assertTrue(dub.url.contains("/dub"))
        assertNotEquals(sub.url, dub.url)
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { a -> androidx.lifecycle.ViewModelProvider(a)[StreamifyViewModel::class.java].selected = anime }
                var choice = device.wait(Until.findObject(By.text("Watch dub")), 8000)
                if (choice == null) { device.swipe(500,1500,500,650,25); choice = device.wait(Until.findObject(By.text("Watch dub")), 5000) }
                assertNotNull(choice)
                choice!!.click()
                device.wait(Until.findObject(By.text("HD-1 · DUB")), 3000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.desc("Choose source")), 45000))
                assertEquals("anime-anikoto-323-dub", LocalStore(context).animeServerId)
                assertNotNull(device.findObject(By.text("HD-1 · DUB")))
                Thread.sleep(30000)
                assertNull("Embed must load without native HTTP error", device.findObject(By.textContains("Source returned HTTP")))
                val playback = java.util.concurrent.atomic.AtomicReference("")
                val measured = java.util.concurrent.CountDownLatch(1)
                InstrumentationRegistry.getInstrumentation().runOnMainSync {
                    val activity = androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).filterIsInstance<PlayerActivity>().first()
                    fun web(v: android.view.View): android.webkit.WebView? = if (v is android.webkit.WebView) v else
                        (v as? android.view.ViewGroup)?.let { g -> (0 until g.childCount).firstNotNullOfOrNull { web(g.getChildAt(it)) } }
                    web(activity.window.decorView)!!.evaluateJavascript("JSON.stringify(Array.from(document.querySelectorAll('video')).map(v=>({time:v.currentTime,ready:v.readyState,paused:v.paused})))") {
                        playback.set(it); measured.countDown()
                    }
                }
                assertTrue(measured.await(5, java.util.concurrent.TimeUnit.SECONDS))
                java.io.File(context.getExternalFilesDir(null), "anime-playback.json").writeText(playback.get())
                device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "anime-player.png"))
                val videos = org.json.JSONArray(org.json.JSONTokener(playback.get()).nextValue() as String)
                assertTrue("Anime must actually play, not merely load its page: ${playback.get()}",
                    (0 until videos.length()).any { videos.getJSONObject(it).optDouble("time") > 2 && videos.getJSONObject(it).optInt("ready") >= 2 })
                device.findObject(By.desc("Close player")).click()
            }
            val intent = PlayerActivity.mediaIntent(context, anime, 1, 2, "streamex")
            assertEquals("anime-anikoto-323-dub", intent.getStringExtra("provider"))
            val otherAccount = LocalStore(context) { "anime-isolation-test" }
            assertEquals("anime-anikoto-323-sub", otherAccount.animeServerId)
        } finally { store.animeServerId = original }
    }
}
