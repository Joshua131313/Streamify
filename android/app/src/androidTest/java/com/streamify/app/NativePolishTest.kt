package com.streamify.app

import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.streamify.app.data.*
import com.streamify.app.ui.*
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class NativePolishTest {
    private val device get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    @Test fun homeKeepsScrollAfterClosingDetails() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { a -> androidx.lifecycle.ViewModelProvider(a)[StreamifyViewModel::class.java].returnHome() }
            Thread.sleep(3000)
            var heading = device.findObject(By.text("Explore genres"))
            var attempts = 0
            while (heading == null && attempts++ < 24) {
                device.swipe(500,1500,500,650,25)
                Thread.sleep(350)
                heading = device.findObject(By.text("Explore genres"))
            }
            assertNotNull("Scrolled home heading must be visible", heading)
            val before = heading!!.visibleBounds.top
            scenario.onActivity { a -> androidx.lifecycle.ViewModelProvider(a)[StreamifyViewModel::class.java].selected = Media(1396,MediaType.TV,"Breaking Bad") }
            assertNotNull(device.wait(Until.findObject(By.desc("Back")),10000))
            device.findObject(By.desc("Back")).click()
            val restored = device.wait(Until.findObject(By.text("Explore genres")),5000)
            assertNotNull("Returning from details must keep the home scroll", restored)
            assertEquals(before, restored!!.visibleBounds.top)
        }
    }
    @Test fun detailPreviewAndEpisodeLayoutSnapshot() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                val vm=androidx.lifecycle.ViewModelProvider(a)[StreamifyViewModel::class.java]
                a.setContent { StreamifyTheme { Surface { DetailScreen(Media(1396,MediaType.TV,"Breaking Bad"),vm) {} } } }
            }
            assertNotNull(device.wait(Until.findObject(By.text("My list")),10000))
            device.wait(Until.findObject(By.desc("Unmute trailer")),20000)
            Thread.sleep(5000)
            val context=InstrumentationRegistry.getInstrumentation().targetContext
            device.takeScreenshot(File(context.getExternalFilesDir(null),"detail-preview.png"))
            val frameHeight = java.util.concurrent.atomic.AtomicReference(0.0)
            val measured = java.util.concurrent.CountDownLatch(1)
            scenario.onActivity { a ->
                fun web(v:android.view.View):android.webkit.WebView? = if(v is android.webkit.WebView) v else (v as? android.view.ViewGroup)?.let { g -> (0 until g.childCount).firstNotNullOfOrNull { web(g.getChildAt(it)) } }
                web(a.window.decorView)?.evaluateJavascript("JSON.stringify({state:window.previewState,time:p.getCurrentTime(),frame:p.getIframe().getBoundingClientRect().toJSON()})") { value ->
                    File(context.getExternalFilesDir(null),"trailer-state.txt").writeText(value)
                    runCatching { val json = org.json.JSONObject(org.json.JSONTokener(value).nextValue() as String); frameHeight.set(json.getJSONObject("frame").getDouble("height")) }
                    measured.countDown()
                }
            }
            assertTrue(measured.await(5, java.util.concurrent.TimeUnit.SECONDS))
            assertTrue("Trailer iframe must have visible height", frameHeight.get() > 100)
            device.swipe(500,1800,500,600,30)
            Thread.sleep(700)
            device.takeScreenshot(File(context.getExternalFilesDir(null),"detail-episodes.png"))
        }
    }
    @Test fun nativePullOnlyDismissesPastThresholdAtTop() {
        val dismissed=AtomicInteger(0)
        lateinit var state: androidx.compose.foundation.lazy.LazyListState
        Configurator.getInstance().waitForIdleTimeout=100
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { a -> a.setContent { StreamifyTheme { Surface {
                val list=rememberLazyListState()
                androidx.compose.runtime.SideEffect { state = list }
                PullDownDetail(list,{dismissed.incrementAndGet()}) { modifier ->
                    LazyColumn(modifier, state = list) { items(40) { i -> Text("Row $i",Modifier.fillMaxWidth().height(70.dp).padding(16.dp)) } }
                }
            } } } }
            assertNotNull(device.wait(Until.findObject(By.text("Row 0")),5000))
            device.swipe(500,600,500,680,20);Thread.sleep(5000)
            assertEquals(0,dismissed.get())
            device.swipe(500,1400,500,500,30);Thread.sleep(300)
            device.swipe(500,600,500,850,20);Thread.sleep(300)
            assertEquals(0,dismissed.get())
            kotlinx.coroutines.runBlocking { kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { state.scrollToItem(0) } }
            Thread.sleep(300)
            assertNotNull(device.findObject(By.text("Row 0")))
            device.swipe(500,500,500,1700,40)
            Thread.sleep(500)
            assertTrue(dismissed.get()>0)
        }
    }
    @Test fun longScoresAndSearchAutofocus() {
        Configurator.getInstance().waitForIdleTimeout=100
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { a ->
                val vm=androidx.lifecycle.ViewModelProvider(a)[StreamifyViewModel::class.java]
                vm.tab="Browse"
            }
            assertNotNull(device.wait(Until.findObject(By.clazz("android.widget.EditText").focused(true)),10000))
            device.pressBack()
            val game=Game("score",League.NBA,"2026-10-16T00:00:00Z","in","4th",Team("1","Oklahoma City Thunder","OKC","","122",""),Team("2","Toronto Raptors","TOR","","120",""),"","","")
            scenario.onActivity { a -> a.setContent { StreamifyTheme { Surface { Column(Modifier.fillMaxSize().statusBarsPadding(),verticalArrangement=Arrangement.spacedBy(20.dp)) {
                GameCard(game) {}
                ScoringTable(game,listOf(StatRow("1","123","122"),StatRow("2","1000","999"),StatRow("3","120","122"),StatRow("4","20","25")))
            } } } } }
            val score=device.wait(Until.findObject(By.text("120 : 122")),5000)
            assertNotNull(score);assertTrue(score.visibleBounds.height()<100)
            assertNotNull(device.findObject(By.text("Thunder")))
            device.takeScreenshot(File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null),"compact-scores.png"))
        }
    }
}
