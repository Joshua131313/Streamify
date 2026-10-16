package com.streamify.app

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import androidx.lifecycle.ViewModelProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Integration check against the public Android release feed; run on the bootstrap (code 2) build. */
@RunWith(AndroidJUnit4::class)
class UpdateFlowTest {
    @Test fun checksDownloadsVerifiesAndOpensInstaller() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        Configurator.getInstance().waitForIdleTimeout = 100
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.desc("More options")), 10000))
            device.findObject(By.desc("More options")).click()
            device.wait(Until.findObject(By.text("Settings")), 5000).click()
            device.wait(Until.findObject(By.text("Check for updates")), 5000).click()
            val download = device.wait(Until.findObject(By.text("Download update")), 30000)
            assertNotNull("Newer public release should be available", download)
            download.click()
            val install = device.wait(Until.findObject(By.text("Install update")), 120000)
            assertNotNull("APK must pass hash, package and signing checks", install)
            scenario.onActivity { activity ->
                val state = ViewModelProvider(activity)[UpdateViewModel::class.java]
                assertTrue(state.ready?.isFile == true)
                assertTrue(state.available!!.versionCode > BuildConfig.VERSION_CODE)
            }
            install.click()
            assertNotNull("Android installer should request confirmation", device.wait(Until.findObject(By.text("Update")), 10000))
            device.takeScreenshot(java.io.File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "update-installer.png"))
            device.findObject(By.text("Cancel"))?.click()
        }
    }
}
