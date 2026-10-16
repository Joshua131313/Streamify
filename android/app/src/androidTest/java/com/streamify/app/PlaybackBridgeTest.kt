package com.streamify.app

import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.streamify.app.data.playbackProgressScript
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class PlaybackBridgeTest {
    @Test fun trustedVideoResumesAndReportsPosition() {
        val latch = CountDownLatch(1)
        var position = 0.0
        var duration = 0.0
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                assertTrue(WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
                val web = WebView(activity)
                web.settings.javaScriptEnabled = true
                WebViewCompat.addWebMessageListener(web, "StreamifyProgress", setOf("https://progress.example.test")) { _, message, origin, _, _ ->
                    assertEquals("https://progress.example.test", origin.toString())
                    val sample = JSONObject(message.data!!)
                    position = sample.getDouble("position"); duration = sample.getDouble("duration"); latch.countDown()
                }
                WebViewCompat.addDocumentStartJavaScript(web, playbackProgressScript(120.0), setOf("https://progress.example.test"))
                activity.setContentView(web)
                // Deterministic HTMLMediaElement fixture: validates real WebView origin-scoped injection and seek, with no external video dependency.
                web.loadDataWithBaseURL("https://progress.example.test/", """<html><body><video style="width:320px;height:180px"></video><script>
                  var v=document.querySelector('video');
                  Object.defineProperty(v,'duration',{value:1800});
                  Object.defineProperty(v,'currentTime',{value:0,writable:true});
                  Object.defineProperty(v,'paused',{value:false});
                  setTimeout(function(){v.dispatchEvent(new Event('loadedmetadata'));v.dispatchEvent(new Event('timeupdate'));},500);
                </script></body></html>""", "text/html", "UTF-8", null)
            }
            assertTrue(latch.await(10,TimeUnit.SECONDS))
            assertEquals(120.0,position,.01);assertEquals(1800.0,duration,.01)
        }
    }
}
