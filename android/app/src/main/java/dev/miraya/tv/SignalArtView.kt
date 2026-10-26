package dev.miraya.tv

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.view.View

/** Resolution-independent artwork: no internet image assets or embedded screen content. */
class SignalArtView(context: Context, private val backdrop: Boolean = false) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cyan = Color.rgb(0, 229, 255)
    private val blue = Color.rgb(59, 130, 246)
    init { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO; setLayerType(LAYER_TYPE_SOFTWARE, null) }
    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (backdrop) {
            canvas.drawColor(Color.rgb(11, 16, 32))
            paint.shader = RadialGradient(w * .75f, h * .55f, w * .7f, intArrayOf(0xFF113458.toInt(), 0xFF0B1020.toInt()), null, Shader.TileMode.CLAMP)
            canvas.drawRect(0f, 0f, w, h, paint); paint.shader = null
            val wave = Path().apply { moveTo(-w * .1f, h * .7f); cubicTo(w * .2f, h * 1.14f, w * .8f, h * 1.05f, w * 1.12f, h * .67f) }
            paint.style = Paint.Style.STROKE; paint.strokeWidth = h * .002f; paint.color = 0x503B82F6
            paint.setShadowLayer(h * .022f, 0f, 0f, blue); canvas.drawPath(wave, paint); paint.clearShadowLayer()
            paint.style = Paint.Style.FILL
            return
        }
        val tv = RectF(w * .43f, h * .12f, w * .96f, h * .76f)
        val laptop = RectF(w * .04f, h * .43f, w * .38f, h * .84f)
        fun screen(bounds: RectF) {
            paint.style = Paint.Style.FILL
            paint.shader = LinearGradient(bounds.left, bounds.top, bounds.right, bounds.bottom, intArrayOf(0xFF2488DC.toInt(), 0xFF103266.toInt(), 0xFF0A1831.toInt()), null, Shader.TileMode.CLAMP)
            canvas.drawRoundRect(bounds, 10f, 10f, paint); paint.shader = null
            paint.style = Paint.Style.STROKE; paint.strokeWidth = w * .005f; paint.color = cyan
            paint.setShadowLayer(w * .035f, 0f, 0f, cyan); canvas.drawRoundRect(bounds, 10f, 10f, paint); paint.clearShadowLayer()
            paint.style = Paint.Style.FILL
        }
        screen(tv); screen(laptop)
        paint.color = blue
        val stand = Path().apply { moveTo(w * .66f, h * .77f); lineTo(w * .72f, h * .77f); lineTo(w * .73f, h * .83f); lineTo(w * .81f, h * .86f); lineTo(w * .58f, h * .86f); lineTo(w * .66f, h * .83f); close() }
        canvas.drawPath(stand, paint)
        paint.color = cyan; canvas.drawRoundRect(RectF(w * .01f, h * .86f, w * .41f, h * .90f), 8f, 8f, paint)
        paint.style = Paint.Style.STROKE
        repeat(3) { index ->
            val path = Path().apply { moveTo(w * .2f, h * .84f); cubicTo(w * .5f, h * .92f, w * .42f, h * (.45f - index * .045f), w * .59f, h * (.47f + index * .05f)); cubicTo(w * .74f, h * (.49f + index * .06f), w * .74f, h * .91f, w * .96f, h * (.69f + index * .025f)) }
            paint.color = if (index == 1) Color.WHITE else cyan; paint.strokeWidth = w * .003f
            paint.setShadowLayer(w * .022f, 0f, 0f, cyan); canvas.drawPath(path, paint)
        }
        paint.clearShadowLayer(); paint.style = Paint.Style.FILL
    }
}
