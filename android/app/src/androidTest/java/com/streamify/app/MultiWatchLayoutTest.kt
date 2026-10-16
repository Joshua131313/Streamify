package com.streamify.app

import android.app.Application
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.streamify.app.data.Stream
import com.streamify.app.ui.MultiWatchScreen
import com.streamify.app.ui.StreamifyTheme
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MultiWatchLayoutTest {
    private fun videos(view: View): List<WebView> = if (view is WebView) listOf(view) else
        (view as? ViewGroup)?.let { group -> (0 until group.childCount).flatMap { videos(group.getChildAt(it)) } }.orEmpty()
    @Test fun slotsReflowWithoutReloadingExistingPlayers() {
        val vm = StreamifyViewModel(ApplicationProvider.getApplicationContext<Application>())
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                vm.queueStream(Stream("Game 1", "https://127.0.0.1:1/first"))
                activity.setContent { StreamifyTheme { MultiWatchScreen(vm) } }
            }
            assertNotNull(device.wait(Until.findObject(By.text("Game 1")), 5000))
            var first: WebView? = null
            scenario.onActivity { first = videos(it.window.decorView).single(); vm.queueStream(Stream("Game 2", "https://127.0.0.1:1/second")) }
            assertNotNull(device.wait(Until.findObject(By.text("Game 2")), 5000))
            device.waitForIdle()
            scenario.onActivity {
                val views = videos(it.window.decorView)
                assertEquals(2, views.size); assertSame(first, views[0])
                assertEquals(views[0].width, views[1].width)
                val top = IntArray(2); val bottom = IntArray(2)
                views[0].getLocationOnScreen(top); views[1].getLocationOnScreen(bottom)
                assertEquals(top[0], bottom[0]); assertTrue(bottom[1] > top[1])
                vm.queueStream(Stream("Game 3", "https://127.0.0.1:1/third"))
            }
            assertNotNull(device.wait(Until.findObject(By.text("Live games")), 5000))
            device.waitForIdle()
            scenario.onActivity {
                val views = videos(it.window.decorView)
                assertEquals(3, views.size); assertSame(first, views[0])
                val left = IntArray(2); val right = IntArray(2)
                views[0].getLocationOnScreen(left); views[1].getLocationOnScreen(right)
                assertEquals(left[1], right[1]); assertTrue(right[0] > left[0])
            }
        }
    }
}
