package dev.miraya.tv

import kotlin.math.roundToInt

enum class PictureMode(val wire: String) {
    FIT("fit"), FILL("fill"), STRETCH("stretch");
    companion object { fun parse(value: String) = entries.firstOrNull { it.wire == value } }
}

data class PresentationSettings(val mode: PictureMode = PictureMode.FIT, val edgeInsetPercent: Int = 0) {
    init { require(edgeInsetPercent in 0..10) { "Screen margin must be between 0 and 10 percent" } }
    fun layout(viewWidth: Int, viewHeight: Int, videoWidth: Int, videoHeight: Int): PictureLayout {
        require(viewWidth > 0 && viewHeight > 0 && videoWidth > 0 && videoHeight > 0)
        val areaWidth = (viewWidth * (1 - edgeInsetPercent / 50.0)).roundToInt().coerceAtLeast(1)
        val areaHeight = (viewHeight * (1 - edgeInsetPercent / 50.0)).roundToInt().coerceAtLeast(1)
        if (mode == PictureMode.STRETCH) return PictureLayout(areaWidth, areaHeight, areaWidth, areaHeight)
        val x = areaWidth.toDouble() / videoWidth; val y = areaHeight.toDouble() / videoHeight
        val scale = if (mode == PictureMode.FIT) minOf(x, y) else maxOf(x, y)
        return PictureLayout((videoWidth * scale).roundToInt().coerceAtLeast(1), (videoHeight * scale).roundToInt().coerceAtLeast(1), areaWidth, areaHeight)
    }
}

data class PictureLayout(val width: Int, val height: Int, val areaWidth: Int, val areaHeight: Int)
data class TVDisplay(val width: Int, val height: Int, val panelWidth: Int, val panelHeight: Int, val refreshRate: Double, val presentation: PresentationSettings)
