package com.streamify.app

import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.streamify.app.data.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class CategoryBrowseTest {
    @Test fun shortcutsOpenDedicatedFeedsAndDetailsPreservePosition() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            for ((label, type) in listOf("Movies" to MediaType.MOVIE, "Shows" to MediaType.TV, "Anime" to MediaType.ANIME)) {
                scenario.onActivity { a -> ViewModelProvider(a)[StreamifyViewModel::class.java].returnHome() }
                device.wait(Until.findObject(By.text(label)), 10000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.desc("Back to home")), 5000))
                assertNotNull(device.findObject(By.text("Categories")))
                assertFalse(device.hasObject(By.clazz("android.widget.EditText")))
                scenario.onActivity { a -> assertEquals(label, ViewModelProvider(a)[StreamifyViewModel::class.java].tab) }
                assertNotNull(device.wait(Until.findObject(By.text("Watch")), 30000))
                val context = InstrumentationRegistry.getInstrumentation().targetContext
                device.takeScreenshot(File(context.getExternalFilesDir(null), "browse-$label.png"))
                device.swipe(500,1500,500,650,25)
                Thread.sleep(600)
                val heading = device.wait(Until.findObject(By.text("Popular $label")), 5000)
                assertNotNull(heading)
                val top = heading!!.visibleBounds.top
                scenario.onActivity { a -> ViewModelProvider(a)[StreamifyViewModel::class.java].selected = Media(if(type==MediaType.ANIME)1 else 1396, type, "Test details") }
                device.wait(Until.findObject(By.desc("Back")), 10000)!!.click()
                assertEquals(top, device.wait(Until.findObject(By.text("Popular $label")), 5000)!!.visibleBounds.top)
                device.findObject(By.desc("Back to home")).click()
            }
        }
    }
}

