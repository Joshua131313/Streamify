package com.streamify.app

import android.webkit.WebView
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlayerPipTest {
    @Test fun compactSourcePickerOpens() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val context = instrumentation.targetContext
        val intent = PlayerActivity.mediaIntent(context, com.streamify.app.data.Media(862, com.streamify.app.data.MediaType.MOVIE, "Toy Story"), 1, 1, com.streamify.app.data.LocalStore(context).serverId)
        ActivityScenario.launch<PlayerActivity>(intent).use {
            assertNotNull(device.wait(Until.findObject(By.desc("Choose source")), 8000))
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "player-redesign.png"))
            device.findObject(By.desc("Choose source")).click()
            assertNotNull(device.wait(Until.findObject(By.text("Playback source")), 5000))
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "player-sources.png"))
        }
    }
    @Test fun activeVideoEntersPipOnHomeAndHidesChrome() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        Configurator.getInstance().waitForIdleTimeout = 100
        val intent = PlayerActivity.streamIntent(instrumentation.targetContext, "PiP playback test", "https://playback.example.test/")
        ActivityScenario.launch<PlayerActivity>(intent).use { scenario ->
            lateinit var player: PlayerActivity
            assertNotNull(device.wait(Until.findObject(By.desc("Player options")), 8000))
            scenario.onActivity { activity ->
                player = activity
                fun find(view: View): WebView? = if(view is WebView) view else (view as? ViewGroup)?.let { group -> (0 until group.childCount).firstNotNullOfOrNull { find(group.getChildAt(it)) } }
                val web = find(activity.window.decorView)!!
                web.stopLoading()
                web.loadDataWithBaseURL("https://playback.example.test/", """<html><body style="background:black;color:white"><video></video>Picture-in-picture fixture<script>
                    const v=document.querySelector('video');
                    Object.defineProperty(v,'paused',{value:false,writable:true});
                    v.pause=()=>{v.paused=true;};
                    v.play=()=>{v.paused=false;return Promise.resolve();};
                    Object.defineProperty(v,'ended',{value:false});
                    Object.defineProperty(v,'readyState',{value:4});
                </script></body></html>""", "text/html", "UTF-8", null)
            }
            Thread.sleep(1500)
            device.pressHome()
            var pip = false
            repeat(20) {
                instrumentation.runOnMainSync { pip = player.isInPictureInPictureMode }
                if (!pip) Thread.sleep(250)
            }
            assertTrue("Home enters native PiP", pip)
            assertTrue(device.wait(Until.gone(By.desc("Player options")), 5000))
            Thread.sleep(1500)
            val pipWindow = device.findObject(By.pkg("com.streamify.app"))
            assertNotNull(pipWindow)
            val bounds = pipWindow.visibleBounds
            device.click(bounds.centerX(), bounds.centerY())
            val pause = device.wait(Until.findObject(By.desc("Pause")), 5000)
            assertNotNull("PiP exposes a Pause action", pause)
            pause.click()
            val play = device.wait(Until.findObject(By.desc("Play")), 5000)
            assertNotNull("Pausing the video changes the action to Play", play)
            play.click()
            assertNotNull("Playing the video changes the action to Pause", device.wait(Until.findObject(By.desc("Pause")), 5000))
            device.takeScreenshot(java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "player-pip.png"))
        }
    }
}
