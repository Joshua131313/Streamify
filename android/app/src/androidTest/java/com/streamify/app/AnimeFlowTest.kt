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
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { a -> androidx.lifecycle.ViewModelProvider(a)[StreamifyViewModel::class.java].selected = anime }
                var choice = device.wait(Until.findObject(By.text("Watch dub")), 8000)
                if (choice == null) { device.swipe(500,1500,500,650,25); choice = device.wait(Until.findObject(By.text("Watch dub")), 5000) }
                assertNotNull(choice)
                choice!!.click()
                device.wait(Until.findObject(By.text("VidNest · DUB")), 3000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.desc("Choose source")), 8000))
                assertEquals("anime-nest-dub", LocalStore(context).animeServerId)
                assertNotNull(device.findObject(By.text("VidNest · DUB")))
                Thread.sleep(30000)
                assertNull("Embed must load without native HTTP error", device.findObject(By.textContains("Source returned HTTP")))
                device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "anime-player.png"))
                device.findObject(By.desc("Close player")).click()
            }
            val intent = PlayerActivity.mediaIntent(context, anime, 1, 2, "streamex")
            assertEquals("anime-nest-dub", intent.getStringExtra("provider"))
            val otherAccount = LocalStore(context) { "anime-isolation-test" }
            assertEquals("anime-nest-sub", otherAccount.animeServerId)
        } finally { store.animeServerId = original }
    }
}
