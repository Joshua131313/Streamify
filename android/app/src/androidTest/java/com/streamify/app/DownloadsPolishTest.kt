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
                device.takeScreenshot(File(context.getExternalFilesDir(null),"offline-controls.png"))
                device.wait(Until.findObject(By.textStartsWith("Speed (")),3000)!!.click()
                device.wait(Until.findObject(By.text("1.5×")),3000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.text("Speed (1.5×)")),3000))
                device.wait(Until.findObject(By.text("Audio & Subtitles")),3000)!!.click()
                assertNotNull(device.wait(Until.findObject(By.text("Subtitles")),3000))
                device.takeScreenshot(File(context.getExternalFilesDir(null),"offline-tracks.png"))
                device.wait(Until.findObject(By.desc("Close playback settings")),3000)!!.click()
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


