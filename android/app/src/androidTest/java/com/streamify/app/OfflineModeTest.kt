package com.streamify.app

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OfflineModeTest {
    @Test fun startsOfflineAndReturnsToBrowsingWhenReconnected() {
        val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val wifi=device.executeShellCommand("settings get global wifi_on").trim()!="0"
        val data=device.executeShellCommand("settings get global mobile_data").trim()=="1"
        try {
            device.executeShellCommand("svc wifi disable");device.executeShellCommand("svc data disable")
            ActivityScenario.launch(MainActivity::class.java).use {
                assertNotNull(device.wait(Until.findObject(By.text("You’re offline")),15000))
                assertNotNull(device.findObject(By.text("Downloads")))
                assertFalse(device.hasObject(By.textContains("Unable to resolve host")))
                device.executeShellCommand("svc wifi enable")
                assertTrue(device.wait(Until.gone(By.text("You’re offline")),30000))
                assertNotNull(device.wait(Until.findObject(By.desc("Downloads")),10000))
            }
        } finally {
            device.executeShellCommand(if(wifi) "svc wifi enable" else "svc wifi disable")
            device.executeShellCommand(if(data) "svc data enable" else "svc data disable")
        }
    }
}
