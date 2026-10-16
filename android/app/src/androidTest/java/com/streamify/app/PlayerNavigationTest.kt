package com.streamify.app

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.json.JSONTokener

@RunWith(AndroidJUnit4::class)
class PlayerNavigationTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private fun web(view: View): WebView? = if (view is WebView) view else (view as? ViewGroup)?.let { group -> (0 until group.childCount).firstNotNullOfOrNull { web(group.getChildAt(it)) } }
    private fun launch() = ActivityScenario.launch<PlayerActivity>(PlayerActivity.streamIntent(ApplicationProvider.getApplicationContext<Context>(), "Player regression test", "https://127.0.0.1:1/unavailable"))

    @Test fun embedFrameHasRealHeightOnFirstLayout() {
        launch().use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
            scenario.onActivity { activity -> web(activity.window.decorView)!!.loadDataWithBaseURL(
                "https://appassets.androidplatform.net/player/", com.streamify.app.data.playerDocument("https://127.0.0.1:1/unavailable"), "text/html", "UTF-8", null) }
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            var dimensions = JSONObject()
            repeat(10) {
                val latch = CountDownLatch(1)
                scenario.onActivity { activity -> web(activity.window.decorView)!!.evaluateJavascript("JSON.stringify({outer:innerHeight,frame:document.querySelector('iframe')?.getBoundingClientRect().height || 0})") { result ->
                    runCatching { dimensions = JSONObject(JSONTokener(result).nextValue() as String) }
                    latch.countDown()
                } }
                assertTrue(latch.await(3, TimeUnit.SECONDS))
                if (dimensions.optDouble("frame") > 100) return@repeat
                Thread.sleep(200)
            }
            assertTrue("The embed must not collapse to a zero-height black screen: $dimensions", dimensions.optDouble("frame") > 100)
            assertEquals(dimensions.getDouble("outer"), dimensions.getDouble("frame"), 2.0)
        }
    }

    @Test fun sportsCannotSwitchToEmbedEvenAfterRecreation() {
        launch().use { scenario ->
            repeat(2) {
                assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
                assertNull(device.findObject(By.text("Try direct mode")))
                assertNull(device.findObject(By.text("Try embed mode")))
                scenario.onActivity { activity ->
                    val player = web(activity.window.decorView)!!
                    assertFalse(player.url.orEmpty().contains("appassets.androidplatform.net"))
                }
                if (it == 0) scenario.recreate()
            }
        }
    }

    @Test fun pdfCompatibilityOnlyHandlesTheKnownProviderProbe() {
        launch().use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
            scenario.onActivity { activity ->
                val script = com.streamify.app.data.sportsPdfCompatibilityScript
                web(activity.window.decorView)!!.loadDataWithBaseURL("https://embed.st/", "<html><body><script>$script</script><p>Probe fixture</p></body></html>", "text/html", "UTF-8", null)
            }
            assertNotNull(device.wait(Until.findObject(By.text("Probe fixture")), 10000))
            val latch = CountDownLatch(1)
            var result = JSONObject()
            scenario.onActivity { activity -> web(activity.window.decorView)!!.evaluateJavascript("""(() => {
                const probe = document.createElement('object'); probe.id = 'sandDetect';
                probe.setAttribute('data', 'data:application/pdf;base64,aG1t');
                document.body.appendChild(probe);
                const known = new Event('error', {cancelable:true}); probe.dispatchEvent(known);
                const other = document.createElement('object'); document.body.appendChild(other);
                const unrelated = new Event('error', {cancelable:true}); other.dispatchEvent(unrelated);
                return JSON.stringify({known:known.defaultPrevented,unrelated:unrelated.defaultPrevented});
            })()""") { value -> result = JSONObject(JSONTokener(value).nextValue() as String); latch.countDown() } }
            assertTrue(latch.await(3, TimeUnit.SECONDS))
            assertTrue(result.getBoolean("known"))
            assertFalse(result.getBoolean("unrelated"))
        }
    }

    @Test fun failedSourceKeepsNativeCloseAndRetryAvailable() {
        launch().use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
            assertNotNull(device.findObject(By.desc("Reload player")))
            device.findObject(By.desc("Close player")).click()
            device.wait(Until.gone(By.desc("Close player")), 5000)
            val deadline = System.currentTimeMillis() + 5000
            while (scenario.state != androidx.lifecycle.Lifecycle.State.DESTROYED && System.currentTimeMillis() < deadline) {
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                Thread.sleep(50)
            }
            assertEquals(androidx.lifecycle.Lifecycle.State.DESTROYED, scenario.state)
        }
    }

    @Test fun fullscreenRetainsCloseAndBackExitsFullscreenFirst() {
        launch().use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
            var callbackInvoked = false
            scenario.onActivity { activity ->
                val player = web(activity.window.decorView)!!
                player.webChromeClient!!.onShowCustomView(FrameLayout(activity), WebChromeClient.CustomViewCallback { callbackInvoked = true })
            }
            assertNotNull(device.wait(Until.findObject(By.desc("Exit fullscreen")), 5000))
            device.wait(Until.findObject(By.text("Got it")), 6000)?.click()
            assertNull(device.findObject(By.desc("Close player")))
            device.pressBack()
            assertTrue(device.wait(Until.gone(By.desc("Exit fullscreen")), 5000))
            scenario.onActivity { assertTrue(callbackInvoked) }
            assertNotNull(device.findObject(By.desc("Close player")))
            device.pressBack()
            device.wait(Until.gone(By.desc("Close player")), 5000)
            assertEquals(androidx.lifecycle.Lifecycle.State.DESTROYED, scenario.state)
        }
    }

    @Test fun nativeFullscreenFillsWindowAndReturnsWithoutReload() {
        launch().use { scenario ->
            val expand = device.wait(Until.findObject(By.desc("Enter fullscreen")), 10000)
            assertNotNull(expand)
            var original: WebView? = null
            scenario.onActivity { original = web(it.window.decorView) }
            expand.click()
            assertNotNull(device.wait(Until.findObject(By.desc("Exit fullscreen")), 10000))
            device.wait(Until.findObject(By.text("Got it")), 6000)?.click()
            device.waitForIdle()
            scenario.onActivity { activity ->
                val player = web(activity.window.decorView)!!
                assertSame(original, player)
                assertEquals(activity.window.decorView.width, player.width)
                assertEquals(activity.window.decorView.height, player.height)
            }
            device.pressBack()
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
            scenario.onActivity { assertSame(original, web(it.window.decorView)) }
        }
    }

    @Test fun fullscreenControlsFadeAndZoomCanBeReset() {
        // UiAutomator's default idle wait outlasts auto-hiding player controls.
        val config = androidx.test.uiautomator.Configurator.getInstance()
        val previousIdle = config.waitForIdleTimeout
        config.waitForIdleTimeout = 100
        try { launch().use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("Enter fullscreen")), 10000))
            scenario.onActivity { activity -> web(activity.window.decorView)!!.loadDataWithBaseURL("https://example.com",
                "<html><body style='margin:0'><video style='width:100vw;height:100vh;object-fit:contain'></video><script>const v=document.querySelector('video');Object.defineProperty(v,'videoWidth',{value:1920});Object.defineProperty(v,'videoHeight',{value:1080});</script></body></html>", "text/html", "UTF-8", null) }
            Thread.sleep(500)
            device.wait(Until.findObject(By.desc("Enter fullscreen")), 10000)!!.click()
            device.wait(Until.findObject(By.text("Got it")), 1000)?.click()
            assertTrue(device.wait(Until.gone(By.desc("Exit fullscreen")), 6000))
            device.click(device.displayWidth / 2, device.displayHeight / 2)
            assertNotNull(device.wait(Until.findObject(By.desc("Exit fullscreen")), 2000))
            device.wait(Until.findObject(By.text("Fill screen")), 2000)!!.click()
            assertNotNull(device.wait(Until.findObject(By.text("Fit screen")), 2000))
            Thread.sleep(150)
            device.findObject(By.text("Fit screen")).click()
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            // Compose redraws the label before UiAutomator invalidates its cached node.
            if (android.os.Build.VERSION.SDK_INT >= 33) InstrumentationRegistry.getInstrumentation().uiAutomation.clearCache()
            val reset = device.wait(Until.findObject(By.text("Fill screen")), 2000)
            if (reset == null) {
                val folder = ApplicationProvider.getApplicationContext<Context>().getExternalFilesDir(null)!!
                device.takeScreenshot(java.io.File(folder, "zoom-reset.png"))
                device.dumpWindowHierarchy(java.io.File(folder, "zoom-reset.xml"))
            }
            assertNotNull(reset)
            device.pressBack()
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 5000))
        } } finally { config.waitForIdleTimeout = previousIdle }
    }

    @Test fun secondaryVideoCannotUnmuteUntilSelected() {
        launch().use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("Close player")), 10000))
            scenario.onActivity { activity -> web(activity.window.decorView)!!.loadDataWithBaseURL("https://example.com",
                "<html><script>" + com.streamify.app.data.multiWatchAudioScript(false) + "</script><video></video></html>", "text/html", "UTF-8", null) }
            Thread.sleep(600)
            val latch = CountDownLatch(1)
            var muted = false
            scenario.onActivity { activity -> web(activity.window.decorView)!!.evaluateJavascript("document.querySelector('video').muted=false; document.querySelector('video').muted") { muted = it == "true"; latch.countDown() } }
            assertTrue(latch.await(3, TimeUnit.SECONDS)); assertTrue(muted)
            scenario.onActivity { activity -> web(activity.window.decorView)!!.evaluateJavascript(com.streamify.app.data.multiWatchAudioUpdate(true), null) }
            Thread.sleep(200)
            val next = CountDownLatch(1)
            scenario.onActivity { activity -> web(activity.window.decorView)!!.evaluateJavascript("document.querySelector('video').muted") { muted = it == "true"; next.countDown() } }
            assertTrue(next.await(3, TimeUnit.SECONDS)); assertFalse(muted)
        }
    }

    @Test fun sportsChatBackReturnsToPlayerAndCloseStillWorks() {
        val intent = PlayerActivity.streamIntent(ApplicationProvider.getApplicationContext<Context>(), "Chat navigation test", "https://127.0.0.1:1/unavailable", "emulator-chat-navigation")
        ActivityScenario.launch<PlayerActivity>(intent).use { scenario ->
            val chat = device.wait(Until.findObject(By.desc("Game chat")), 10000)
            assertNotNull(chat)
            chat.click()
            assertNotNull(device.wait(Until.findObject(By.text("Chat as a guest. Sign in to use your profile name.")), 5000))
            device.pressBack()
            assertTrue(device.wait(Until.gone(By.text("Chat as a guest. Sign in to use your profile name.")), 5000))
            val close = device.wait(Until.findObject(By.desc("Close player")), 5000)
            assertNotNull(close)
            close.click()
            val deadline = System.currentTimeMillis() + 5000
            while (scenario.state != androidx.lifecycle.Lifecycle.State.DESTROYED && System.currentTimeMillis() < deadline) {
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                Thread.sleep(50)
            }
            assertEquals(androidx.lifecycle.Lifecycle.State.DESTROYED, scenario.state)
        }
    }
}
