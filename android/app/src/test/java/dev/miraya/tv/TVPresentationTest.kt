package dev.miraya.tv

import org.junit.Assert.*
import org.junit.Test

class TVPresentationTest {
    @Test fun fitPreservesWholeRetinaDesktopOnWideTV() {
        val layout = PresentationSettings().layout(1920, 1080, 3024, 1964)
        assertEquals(1663, layout.width); assertEquals(1080, layout.height)
        assertTrue(layout.width <= layout.areaWidth && layout.height <= layout.areaHeight)
    }
    @Test fun fillCropsButStretchChangesProportions() {
        val fill = PresentationSettings(PictureMode.FILL).layout(1920, 1080, 1600, 1000)
        assertEquals(1920, fill.width); assertEquals(1200, fill.height)
        val stretch = PresentationSettings(PictureMode.STRETCH).layout(1920, 1080, 1600, 1000)
        assertEquals(1920, stretch.width); assertEquals(1080, stretch.height)
    }
    @Test fun safeMarginIsAppliedOnEveryEdgeAndClipsFillInsideIt() {
        for (mode in PictureMode.entries) {
            val result = PresentationSettings(mode, 5).layout(1920, 1080, 1920, 1080)
            assertEquals(1728, result.areaWidth); assertEquals(972, result.areaHeight)
            assertEquals(1728, result.width); assertEquals(972, result.height)
        }
    }
    @Test fun portraitContentFitsWithoutCropping() {
        val result = PresentationSettings().layout(1920, 1080, 1080, 1920)
        assertEquals(608, result.width); assertEquals(1080, result.height)
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsExcessiveMargin() { PresentationSettings(edgeInsetPercent = 11) }
}
