package dev.miraya.tv

import android.content.Context
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Native UI checks: remote focus, safe approval, panel containment and symmetric picture controls. */
@RunWith(AndroidJUnit4::class)
class BeamInterfaceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private lateinit var scenario: ActivityScenario<MainActivity>
    @Before fun launch() {
        context.getSharedPreferences("presentation", Context.MODE_PRIVATE).edit().clear().commit()
        Identity(context).rename("Living Room TV")
        scenario = ActivityScenario.launch(MainActivity::class.java)
        assertTrue(device.wait(Until.hasObject(By.text("Ready for your Mac")), 15000))
        device.waitForIdle()
    }
    @After fun finish() {
        screenshot("last")
        val tree = File(context.getExternalFilesDir(null), "beam-tv-tree.xml")
        device.dumpWindowHierarchy(tree)
        device.executeShellCommand("cp ${tree.absolutePath} /sdcard/Download/miraya-beam-review/${tree.name}")
        scenario.close()
    }
    private fun screenshot(name: String) {
        device.waitForIdle()
        val file = File(context.getExternalFilesDir(null), "beam-tv-$name.png")
        assertTrue(device.takeScreenshot(file))
        device.executeShellCommand("mkdir -p /sdcard/Download/miraya-beam-review")
        device.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/miraya-beam-review/${file.name}")
    }
    @Test fun readyScreenUsesRemoteFocusAndReadableIdentity() {
        val details = device.wait(Until.findObject(By.text("Connection details")), 3000)
        assertNotNull(details); assertTrue("Initial focus must be visible", details.isFocused)
        assertNotNull(device.findObject(By.text("Living Room TV")))
        assertNotNull(device.findObject(By.textContains("Keep Miraya open here")))
        screenshot("ready")
    }
    @Test fun approvalRetainsCodeDefaultsToDeclineAndRespondsExactlyOnce() {
        scenario.onActivity { it.onPairingCode("481729") }
        assertNotNull(device.wait(Until.findObject(By.text("481 729")), 3000))
        assertNull(device.findObject(By.text("Allow"))); screenshot("pairing")
        val calls = AtomicInteger(); val denied = CountDownLatch(1)
        scenario.onActivity { it.approve("MacBook Pro") { allowed -> assertFalse(allowed); calls.incrementAndGet(); denied.countDown() } }
        val decline = device.wait(Until.findObject(By.text("Decline")), 3000)
        assertNotNull(decline); assertTrue("Approval must default to the safe action", decline.isFocused)
        scenario.onActivity { it.onPairingCode(null) }
        assertNotNull(device.wait(Until.findObject(By.text("481 729")), 2000))
        screenshot("approval")
        device.pressBack(); assertTrue(denied.await(3, TimeUnit.SECONDS))
        scenario.onActivity { it.dismissApproval(); it.dismissApproval() }
        device.waitForIdle(); assertEquals(1, calls.get())
    }
    @Test fun lateDiscoveryCannotReplaceAnApprovedConnection() {
        scenario.onActivity { it.onPairingCode("481729") }
        assertNotNull(device.wait(Until.findObject(By.text("481 729")), 3000))
        val allowed = CountDownLatch(1)
        scenario.onActivity { it.approve("MacBook Pro") { yes -> assertTrue(yes); allowed.countDown() } }
        val allow = device.wait(Until.findObject(By.text("Allow")), 3000)
        assertNotNull(allow); allow.click(); assertTrue(allowed.await(3, TimeUnit.SECONDS))
        scenario.onActivity { it.onListening(7421, "192.0.2.42", true) }
        assertNotNull(device.wait(Until.findObject(By.text("Mac verified")), 3000))
        assertNull(device.findObject(By.text("Ready for your Mac")))
    }
    @Test fun detailsKeepFocusInsideAndBackClosesPanelFirst() {
        device.findObject(By.text("Connection details")).click()
        assertNotNull(device.wait(Until.findObject(By.textContains("app viewport")), 3000))
        repeat(4) { device.pressDPadLeft() }; device.waitForIdle()
        val focused = device.findObject(By.focused(true)); assertNotNull(focused)
        assertTrue("D-pad must not escape behind the panel", focused.visibleBounds.left >= device.displayWidth * .45)
        screenshot("details"); device.pressBack()
        assertNotNull(device.wait(Until.findObject(By.text("Ready for your Mac")), 3000))
        assertTrue(device.findObject(By.text("Connection details")).isFocused)
    }
    @Test fun livePicturePanelPreservesSharingAndMarginSupportsFullRange() {
        scenario.onActivity { it.onStreaming("MacBook Pro", true) }
        val fit = device.wait(Until.findObject(By.desc("Fit / Fill")), 3000)
        assertNotNull(fit); screenshot("controls")
        fit.click()
        assertNotNull(device.wait(Until.findObject(By.text("TV picture")), 3000))
        device.findObject(By.textContains("Edge Margin")).click()
        screenshot("edge-open")
        val slider = device.wait(Until.findObject(By.clazz("android.widget.SeekBar")), 3000)
        assertNotNull(slider); slider.click()
        repeat(12) { device.pressDPadRight() }; device.waitForIdle()
        scenario.onActivity { assertEquals(10, it.displayInfo().presentation.edgeInsetPercent) }
        repeat(12) { device.pressDPadLeft() }; device.waitForIdle()
        scenario.onActivity { assertEquals(0, it.displayInfo().presentation.edgeInsetPercent) }
        screenshot("margin"); device.pressBack()
        assertNotNull(device.wait(Until.findObject(By.desc("Stop")), 3000))
        assertNull("Closing a picture panel must not stop sharing", device.findObject(By.text("Ready for your Mac")))
    }
}
