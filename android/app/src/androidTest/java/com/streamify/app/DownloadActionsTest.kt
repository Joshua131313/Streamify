package com.streamify.app

import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.streamify.app.data.*
import com.streamify.app.downloads.*
import com.streamify.app.ui.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DownloadActionsTest {
    @Test fun progressUpdatesAndLongPressActions() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        Configurator.getInstance().waitForIdleTimeout=200
        val store=DownloadStore.get(context)
        val movie=Media(987654,MediaType.MOVIE,"Menu test movie")
        val entry=DownloadItem("movie_987654_0_0",movie.id,movie.title,state="downloading",bytes=25,total=100)
        store.update(entry)
        var removed by mutableStateOf(false)
        try {ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { it.setContent {StreamifyTheme {Surface {Column(Modifier.fillMaxSize().statusBarsPadding()) {
                DownloadButton(movie)
                if(!removed) ContinueWatchingShelf(listOf(History(movie)),"streamex",{}, {removed=true})
            }}}} }
            assertNotNull(device.wait(Until.findObject(By.text("Downloading · 25%")),5000))
            store.update(entry.copy(bytes=75))
            assertNotNull(device.wait(Until.findObject(By.text("Downloading · 75%")),5000))
            device.wait(Until.findObject(By.text(movie.title)),5000)!!.longClick()
            assertNotNull(device.wait(Until.findObject(By.text("More info")),5000))
            assertNotNull(device.findObject(By.text("Remove from row")))
            device.takeScreenshot(File(context.getExternalFilesDir(null),"download-actions.png"))
            device.findObject(By.text("Remove from row")).click()
            assertTrue(device.wait(Until.gone(By.text(movie.title)),5000))
            assertTrue(removed)
            store.update(entry.copy(state="complete",bytes=100))
            assertNotNull(device.wait(Until.findObject(By.text("Downloaded")),5000))
        }} finally {store.remove(entry.key)}
    }
}
