package com.streamify.app

import android.content.Intent
import android.widget.VideoView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.streamify.app.downloads.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DownloadsPolishTest {
    private val context=InstrumentationRegistry.getInstrumentation().targetContext
    private val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    @Test fun downloadedShowLinksToMoreEpisodes() {
        val store=DownloadStore.get(context)
        val item=DownloadItem("more_episodes_test",1396,"Breaking Bad",season=1,episode=1,state="paused")
        store.update(item)
        try {ActivityScenario.launch(DownloadsActivity::class.java).use {
            device.wait(Until.findObject(By.text("Breaking Bad")),10000)!!.click()
            val more=device.wait(Until.findObject(By.text("View more episodes")),5000)!!
            more.click()
            assertTrue(device.wait(Until.gone(By.text("View more episodes")),5000))
            device.pressBack()
            assertNotNull(device.wait(Until.findObject(By.text("View more episodes")),5000))
        }} finally {store.remove(item.key)}
    }
    @Test fun pinchSwitchesBetweenFitAndFill() {
        val store=DownloadStore.get(context);val key="pinch_control"
        File(context.getExternalFilesDir(null),"download-prototype/control.mp4").copyTo(store.file(key),overwrite=true)
        try {ActivityScenario.launch<OfflinePlayerActivity>(Intent(context,OfflinePlayerActivity::class.java).putExtra("key",key)).use {scenario ->
            lateinit var video:VideoView
            scenario.onActivity {a->
                video=(a.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0) as android.view.ViewGroup).getChildAt(0) as VideoView
                video.setOnCompletionListener {video.seekTo(0);video.start()}
            }
            Thread.sleep(1000)
            var fitWidth=0
            scenario.onActivity {fitWidth=video.width}
            val surface=device.findObject(UiSelector().description("Offline player canvas"))
            assertTrue(surface.pinchOut(90,25));Thread.sleep(500)
            scenario.onActivity {assertTrue("Fill should enlarge the video",video.width>fitWidth)}
            assertTrue(surface.pinchIn(90,25));Thread.sleep(500)
            scenario.onActivity {assertEquals("Fit should restore video bounds",fitWidth,video.width)}
        }} finally {store.file(key).delete()}
    }
    @Test fun downloadPrefersFullHdThenFallsBack() {
        val qualities=org.json.JSONObject("""{"360":{"url":"low"},"720":{"url":"hd"},"1080":{"url":"fullhd"}}""")
        assertEquals("fullhd",DownloadResolver.preferredQualityUrl(qualities))
        qualities.remove("1080");assertEquals("hd",DownloadResolver.preferredQualityUrl(qualities))
        qualities.remove("720");assertEquals("low",DownloadResolver.preferredQualityUrl(qualities))
    }
    @Test fun swipeRevealsDeleteWithoutDeleting() {
        val store=DownloadStore.get(context)
        val item=DownloadItem("polish_test",999,"Swipe test movie",state="paused",bytes=50,total=100)
        store.update(item)
        try { ActivityScenario.launch(DownloadsActivity::class.java).use {
            val title=device.wait(Until.findObject(By.text(item.title)),10000)!!
            val y=title.visibleCenter.y
            device.swipe(device.displayWidth*3/4,y,device.displayWidth/4,y,25)
            val delete=device.wait(Until.findObject(By.desc("Delete ${item.title}")),5000)
            assertNotNull(delete);assertNotNull(store.get(item.key))
            device.takeScreenshot(File(context.getExternalFilesDir(null),"downloads-swipe.png"))
            delete!!.click()
            assertTrue(device.wait(Until.gone(By.text(item.title)),10000))
            assertNull(store.get(item.key))
        } } finally {store.remove(item.key)}
    }
    @Test fun offlinePlayerExitAndPipControls() {
        Configurator.getInstance().waitForIdleTimeout=300
        val store=DownloadStore.get(context);val key="pip_control"
        context.getSharedPreferences("offline-positions",0).edit().remove(key).commit()
        File(context.getExternalFilesDir(null),"download-prototype/control.mp4").copyTo(store.file(key),overwrite=true)
        try {
            ActivityScenario.launch<OfflinePlayerActivity>(Intent(context,OfflinePlayerActivity::class.java).putExtra("key",key)).use { scenario ->

                lateinit var video: VideoView
                scenario.onActivity { a ->
                    video=(a.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0) as android.view.ViewGroup).getChildAt(0) as VideoView
                    video.setOnCompletionListener { video.seekTo(0);video.start() }
                    val root=a.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0) as android.view.ViewGroup
                    val exit=(root.getChildAt(1) as android.view.ViewGroup).getChildAt(0)
                    assertEquals("Exit offline player",exit.contentDescription)
                    assertTrue(exit.isShown)
                }
                Thread.sleep(1000)
                scenario.onActivity { a ->
                    val root=a.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0) as android.view.ViewGroup
                    val play=(root.getChildAt(2) as android.view.ViewGroup).getChildAt(1)
                    play.performClick();assertFalse(video.isPlaying)
                    play.performClick();assertTrue(video.isPlaying)
                    (root.getChildAt(2) as android.view.ViewGroup).getChildAt(0).performClick()
                }
                lateinit var preview:SeekPreview
                scenario.onActivity { a ->
                    val root=a.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0) as android.view.ViewGroup
                    preview=(0 until root.childCount).map {root.getChildAt(it)}.filterIsInstance<SeekPreview>().first()
                    (root.getChildAt(2) as android.view.ViewGroup).getChildAt(1).performClick()
                    preview.preview(1000)
                    preview.follow(root,.1f)
                }
                var decoded=false
                repeat(100) { if(!decoded) { Thread.sleep(100);scenario.onActivity { decoded=(preview.getChildAt(0) as android.widget.ImageView).drawable!=null } } }
                assertTrue("Seek preview should decode a frame",decoded)
                device.takeScreenshot(File(context.getExternalFilesDir(null),"offline-controls.png"))
                scenario.onActivity {preview.hidePreview();video.start()}
                assertNotNull(device.wait(Until.findObject(By.desc("Player volume")),3000))
                assertNotNull(device.findObject(By.desc("Cast to TV")))
                device.wait(Until.findObject(By.textStartsWith("Speed (")),3000)!!.click()
                device.wait(Until.findObject(By.text("1.5×")),3000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.text("Speed (1.5×)")),3000))
                device.wait(Until.findObject(By.text("Audio & Subtitles")),3000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.text("Subtitles")),3000))
                device.takeScreenshot(File(context.getExternalFilesDir(null),"offline-tracks.png"))
                device.wait(Until.findObject(By.desc("Close playback settings")),3000)!!.click()
                device.wait(Until.findObject(By.desc("Lock screen")),3000)!!.click()
                assertNull(device.findObject(By.desc("Exit offline player")))
                device.click(device.displayWidth/2,device.displayHeight/2)
                val unlock=device.wait(Until.findObject(By.desc("Hold to unlock screen")),3000)!!
                unlock.click();assertNull(device.findObject(By.desc("Exit offline player")))
                val point=unlock.visibleCenter
                val holdStart=android.os.SystemClock.uptimeMillis()
                val instrumentation=InstrumentationRegistry.getInstrumentation()
                instrumentation.sendPointerSync(android.view.MotionEvent.obtain(holdStart,holdStart,android.view.MotionEvent.ACTION_DOWN,point.x.toFloat(),point.y.toFloat(),0))
                Thread.sleep(1400)
                instrumentation.sendPointerSync(android.view.MotionEvent.obtain(holdStart,android.os.SystemClock.uptimeMillis(),android.view.MotionEvent.ACTION_UP,point.x.toFloat(),point.y.toFloat(),0))
                Thread.sleep(400)
                assertNotNull(device.wait(Until.findObject(By.desc("Exit offline player")),3000))
                device.click(device.displayWidth/2,device.displayHeight/3)
                Thread.sleep(500)
                assertNull(device.findObject(By.desc("Exit offline player")))
                var before=0f
                scenario.onActivity {before=it.window.attributes.screenBrightness}
                device.swipe(device.displayWidth/12,device.displayHeight*3/4,device.displayWidth/12,device.displayHeight/3,25)
                scenario.onActivity {assertTrue(it.window.attributes.screenBrightness>before)}
                assertNull(device.findObject(By.desc("Exit offline player")))
                val inst=InstrumentationRegistry.getInstrumentation()
                repeat(2) {
                    val down=android.os.SystemClock.uptimeMillis()
                    inst.sendPointerSync(android.view.MotionEvent.obtain(down,down,android.view.MotionEvent.ACTION_DOWN,device.displayWidth/4f,device.displayHeight/2f,0))
                    Thread.sleep(20)
                    inst.sendPointerSync(android.view.MotionEvent.obtain(down,android.os.SystemClock.uptimeMillis(),android.view.MotionEvent.ACTION_UP,device.displayWidth/4f,device.displayHeight/2f,0))
                    Thread.sleep(50)
                }
                Thread.sleep(400)
                assertNull(device.findObject(By.desc("Exit offline player")))
                device.pressHome();Thread.sleep(1500)
                scenario.onActivity { assertTrue(it.isInPictureInPictureMode) }
                context.sendBroadcast(Intent("com.streamify.app.OFFLINE_TOGGLE").setPackage(context.packageName))
                Thread.sleep(300)
                scenario.onActivity { assertFalse(video.isPlaying) }
                context.sendBroadcast(Intent("com.streamify.app.OFFLINE_TOGGLE").setPackage(context.packageName))
                Thread.sleep(300)
                scenario.onActivity { assertTrue(video.isPlaying) }
            }
            context.getSharedPreferences("offline-positions",0).edit().remove(key).commit()
            ActivityScenario.launch<OfflinePlayerActivity>(Intent(context,OfflinePlayerActivity::class.java).putExtra("key",key)).use { scenario ->
                scenario.onActivity { a ->
                    val root=a.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0) as android.view.ViewGroup
                    (root.getChildAt(0) as VideoView).setOnCompletionListener { }
                    (root.getChildAt(1) as android.view.ViewGroup).getChildAt(0).performClick()
                    assertTrue(a.isFinishing)
                }

                repeat(50) { if(scenario.state != androidx.lifecycle.Lifecycle.State.DESTROYED) Thread.sleep(100) }
                assertEquals(androidx.lifecycle.Lifecycle.State.DESTROYED,scenario.state)
            }
        } finally {store.file(key).delete()}
    }
}
