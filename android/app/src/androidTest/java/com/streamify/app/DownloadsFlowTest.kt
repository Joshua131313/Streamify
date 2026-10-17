package com.streamify.app

import android.content.Intent
import android.content.pm.ActivityInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.streamify.app.downloads.*
import com.streamify.app.data.*
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import androidx.test.uiautomator.UiDevice
import java.io.File

@RunWith(AndroidJUnit4::class)
class DownloadsFlowTest {
    private val context=InstrumentationRegistry.getInstrumentation().targetContext
    private fun until(test: ()->Boolean) { val end=System.currentTimeMillis()+90000;while(!test() && System.currentTimeMillis()<end) Thread.sleep(250);assertTrue("Timed out",test()) }
    @Test fun providerMovieAndEpisodeResolve() {
        for(item in listOf(DownloadItem("test",597,"Titanic"),DownloadItem("test",1396,"Breaking Bad",season=1,episode=1))) {
            assertTrue(DownloadResolver.resolve(item).startsWith("https://"))
        }
    }
    @Test fun transferPausesResumesAndDeletes() {
        ActivityScenario.launch(DownloadsActivity::class.java).use {
            val store=DownloadStore.get(context)
            val key=store.enqueue(Media(1396,MediaType.TV,"Breaking Bad"),1,1)
            try {
                until { (store.get(key)?.bytes ?: 0)>1048576 || store.get(key)?.state=="error" }
                assertNotEquals(store.get(key)?.error,"error",store.get(key)?.state)
                DownloadStore.command(context,"pause",key)
                until { store.get(key)?.state=="paused" }
                Thread.sleep(2000)
                val paused=store.file(key).length()
                Thread.sleep(1500)
                assertEquals(paused,store.file(key).length())
                DownloadStore.command(context,"resume",key)
                until { (store.get(key)?.bytes ?: 0)>paused+1048576 || store.get(key)?.state=="error" }
                assertNotEquals(store.get(key)?.error,"error",store.get(key)?.state)
            } finally { DownloadStore.command(context,"delete",key);until { store.get(key)==null };assertFalse(store.file(key).exists()) }
        }
    }
    @Test fun offlinePlayerStartsLandscapeWithoutNetwork() {
        val store=DownloadStore.get(context)
        val key="offline_control"
        File(context.getExternalFilesDir(null),"download-prototype/control.mp4").copyTo(store.file(key),overwrite=true)
        val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val wifi=device.executeShellCommand("settings get global wifi_on").trim()!="0"
        val data=device.executeShellCommand("settings get global mobile_data").trim()=="1"
        try {
            device.executeShellCommand("svc wifi disable");device.executeShellCommand("svc data disable")
            ActivityScenario.launch<OfflinePlayerActivity>(Intent(context,OfflinePlayerActivity::class.java).putExtra("key",key)).use { scenario ->
                Thread.sleep(2000)
                scenario.onActivity { activity ->
                    assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE,activity.requestedOrientation)
                    val root=activity.findViewById<android.view.ViewGroup>(android.R.id.content)
                    val video=(root.getChildAt(0) as android.view.ViewGroup).getChildAt(0) as android.widget.VideoView
                    assertTrue(video.currentPosition>500)
                    assertTrue(activity.resources.configuration.screenWidthDp>activity.resources.configuration.screenHeightDp)
                }
                device.takeScreenshot(File(context.getExternalFilesDir(null),"downloads-offline-landscape.png"))
            }
        } finally { if(wifi) device.executeShellCommand("svc wifi enable");if(data) device.executeShellCommand("svc data enable");store.file(key).delete() }
    }
}
