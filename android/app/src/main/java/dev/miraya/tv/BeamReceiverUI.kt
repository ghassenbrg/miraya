package dev.miraya.tv

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/** Static approved artwork and native, remote-first Beam surfaces. No video/background render loop. */
class BeamReceiverUI(context: Context) : FrameLayout(context) {
    private val scale = (resources.displayMetrics.widthPixels / resources.displayMetrics.density / 960f).coerceIn(.75f, 1.5f)
    fun unit(value: Int) = (value * scale * resources.displayMetrics.density).roundToInt()
    fun label(value: String, size: Int, color: Int = WHITE, medium: Boolean = false) = TextView(context).apply {
        text = value; textSize = size * scale; setTextColor(color)
        typeface = Typeface.create(if (medium) "sans-serif-medium" else "sans-serif", Typeface.NORMAL)
        includeFontPadding = false
    }
    fun button(value: String, destructive: Boolean = false, action: () -> Unit) = Button(context).apply {
        text = value; textSize = 15 * scale; isAllCaps = false; typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        setTextColor(ColorStateList(arrayOf(intArrayOf(android.R.attr.state_focused), intArrayOf()), intArrayOf(if (destructive) RED else INK, WHITE)))
        minHeight = unit(52); minimumHeight = unit(52); minimumWidth = 0; minWidth = 0
        setPadding(unit(19), unit(12), unit(19), unit(12))
        background = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), surface(WHITE, 10, if (destructive) 0xFFFFA4AC.toInt() else FOCUS, 2))
            addState(intArrayOf(android.R.attr.state_pressed), surface(0xFFCDDDF4.toInt(), 10, FOCUS, 2))
            addState(intArrayOf(), surface(if (destructive) RED else PANEL, 10, if (destructive) 0xFFE98A94.toInt() else 0xFF40526D.toInt(), 1))
        }
        isFocusable = true; isFocusableInTouchMode = true
        defaultFocusHighlightEnabled = false
        setOnTouchListener { view, event -> if (event.actionMasked == android.view.MotionEvent.ACTION_DOWN) view.requestFocus(); false }
        setOnClickListener { action() }
    }
    fun remoteAction(value: String, icon: Int, destructive: Boolean = false, action: () -> Unit): View {
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; isFocusable = true; isFocusableInTouchMode = true; isClickable = true
            contentDescription = value; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES; defaultFocusHighlightEnabled = false
            setPadding(unit(8), unit(5), unit(8), unit(5))
        }
        val circle = FrameLayout(context)
        val image = ImageView(context).apply { setImageResource(icon); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        circle.addView(image, LayoutParams(unit(24), unit(24), Gravity.CENTER))
        column.addView(circle, LinearLayout.LayoutParams(unit(58), unit(58)))
        column.addView(label(value, 14, WHITE, true).apply { gravity = Gravity.CENTER; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = unit(8) })
        fun focus(on: Boolean) { circle.background = surface(if (on) WHITE else if (destructive) RED else PANEL, 32, if (on) { if (destructive) 0xFFFFA4AC.toInt() else FOCUS } else 0xFF40526D.toInt(), if (on) 2 else 1); image.setColorFilter(if (on) { if (destructive) RED else INK } else WHITE) }
        column.setOnTouchListener { view, event -> if (event.actionMasked == android.view.MotionEvent.ACTION_DOWN) view.requestFocus(); false }
        focus(false); column.setOnFocusChangeListener { _, on -> focus(on) }; column.setOnClickListener { action() }
        return column
    }
    fun surface(color: Int, radius: Int, stroke: Int? = null, width: Int = 1) = GradientDrawable().apply {
        setColor(color); cornerRadius = unit(radius).toFloat(); stroke?.let { setStroke(unit(width).coerceAtLeast(1), it) }
    }
    fun glass() = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0xF71A293F.toInt(), 0xF70B1527.toInt())).apply {
        cornerRadius = unit(14).toFloat(); setStroke(unit(1).coerceAtLeast(1), 0x88788FA8.toInt())
    }

    val friendlyName = label("This TV", 18, WHITE, true)
    val badge = label("Preparing the local connection", 12, SECONDARY)
    val title = label("Getting ready", 42, WHITE, true)
    val detail = label("Preparing this TV’s secure connection.", 18, 0xFFEAF0F8.toInt())
    val code = label("", 78, WHITE, true)
    val pairingHint = label("", 14, WHITE)
    val expiry = label("", 12, SECONDARY)
    val footer = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }
    val footerActions = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
    val footerHint = label("Keep Miraya open here. On your Mac, choose this TV and Share.", 12, 0xFFD0DBEA.toInt())
    private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }

    init {
        addView(ImageView(context).apply {
            setImageResource(R.drawable.beam_lake); scaleType = ImageView.ScaleType.CENTER_CROP
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LayoutParams(-1, -1))
        addView(View(context).apply { background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0x44030B1B, 0x08030B1B, 0x55030B1B)) }, LayoutParams(-1, -1))
        val safe = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(unit(48), unit(27), unit(48), unit(27)) }
        addView(safe, LayoutParams(-1, -1))
        val header = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        header.addView(ImageView(context).apply { setImageResource(R.drawable.beam_mark); contentDescription = "Miraya" }, LinearLayout.LayoutParams(unit(36), unit(36)))
        val wordmark = FrameLayout(context)
        wordmark.addView(ImageView(context).apply { setImageResource(R.drawable.beam_wordmark); scaleType = ImageView.ScaleType.FIT_CENTER; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }, LayoutParams(unit(96), unit(42), Gravity.CENTER_VERTICAL or Gravity.START))
        header.addView(wordmark, LinearLayout.LayoutParams(0, -1, 1f).apply { marginStart = unit(10) })
        val room = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.END }
        friendlyName.maxWidth = unit(340); friendlyName.maxLines = 1; friendlyName.ellipsize = android.text.TextUtils.TruncateAt.END
        friendlyName.gravity = Gravity.END; badge.gravity = Gravity.END
        room.addView(friendlyName, LinearLayout.LayoutParams(-1, -2)); room.addView(badge, LinearLayout.LayoutParams(-1, -2).apply { topMargin = unit(5) })
        header.addView(room, LinearLayout.LayoutParams(unit(340), -2)); safe.addView(header, LinearLayout.LayoutParams(-1, unit(68)))
        safe.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        title.gravity = Gravity.CENTER; title.maxLines = 2
        detail.gravity = Gravity.CENTER; detail.maxWidth = unit(630); detail.setLineSpacing(unit(3).toFloat(), 1.08f)
        content.addView(title, LinearLayout.LayoutParams(-1, -2))
        content.addView(detail, LinearLayout.LayoutParams(-2, -2).apply { topMargin = unit(14) })
        code.apply {
            typeface = Typeface.create("monospace", Typeface.BOLD); letterSpacing = .035f; gravity = Gravity.CENTER
            setPadding(unit(24), unit(9), unit(24), unit(9)); minWidth = unit(422); background = glass()
            visibility = View.GONE; isSingleLine = true
            setAutoSizeTextTypeUniformWithConfiguration((44 * scale).toInt(), (78 * scale).toInt(), 1, android.util.TypedValue.COMPLEX_UNIT_SP)
        }
        content.addView(code, LinearLayout.LayoutParams(-2, -2).apply { topMargin = unit(18) })
        pairingHint.apply { gravity = Gravity.CENTER; maxWidth = unit(640); visibility = View.GONE }
        content.addView(pairingHint, LinearLayout.LayoutParams(-2, -2).apply { topMargin = unit(14) })
        expiry.apply { gravity = Gravity.CENTER; visibility = View.GONE }
        content.addView(expiry, LinearLayout.LayoutParams(-2, -2).apply { topMargin = unit(12) })
        footer.addView(footerActions)
        footerHint.gravity = Gravity.CENTER
        footer.addView(footerHint, LinearLayout.LayoutParams(-1, -2).apply { topMargin = unit(16) })
        safe.addView(footer, LinearLayout.LayoutParams(-1, -2))
    }
    fun ready(name: String, discovery: Boolean = true) {
        friendlyName.text = name; code.visibility = View.GONE; pairingHint.visibility = View.GONE; expiry.visibility = View.GONE
        title.text = "Ready for your Mac"; detail.text = "Open Miraya on your Mac.\nChoose this TV, then Share."
        content.translationY = -unit(36).toFloat()
        title.textSize = 42 * scale; badge.text = if (discovery) "Local network available" else "Discovery unavailable · see details"
        detail.background = null
    }
    fun pairing(value: String?) {
        if (value == null) { code.visibility = View.GONE; pairingHint.visibility = View.GONE; expiry.visibility = View.GONE; return }
        content.translationY = 0f
        title.text = "Compare with your Mac"; title.textSize = 32 * scale
        detail.text = "Confirm these six digits match your Mac."; detail.background = null
        showCode(value); pairingHint.text = "Choose “Numbers match” on your Mac, then approve here."; pairingHint.visibility = View.VISIBLE
        expiry.text = "Comparison expires after 90 seconds"; expiry.visibility = View.VISIBLE
    }
    fun approval(name: String, value: String?) {
        content.translationY = 0f
        title.text = "Allow $name?"; title.textSize = 32 * scale
        detail.text = "Only allow this if you are connecting from your Mac now."; detail.background = null
        value?.let { showCode(it) }
        pairingHint.text = "Your screen and optional system audio will appear here."; pairingHint.visibility = View.VISIBLE
        expiry.text = "Approval expires after 30 seconds"; expiry.visibility = View.VISIBLE
    }
    private fun showCode(value: String) { code.text = value.chunked(3).joinToString(" "); code.contentDescription = "Comparison code ${value.toCharArray().joinToString(" ")}"; code.visibility = View.VISIBLE }
    fun waitingForPicture() {
        code.visibility = View.GONE; pairingHint.visibility = View.GONE; expiry.visibility = View.GONE
        title.text = "Mac verified"; title.textSize = 36 * scale; detail.text = "Waiting for the first picture from your Mac."
    }
    companion object {
        val WHITE = Color.rgb(244, 247, 251)
        val INK = Color.rgb(16, 27, 47)
        val PANEL = Color.rgb(24, 37, 58)
        val SECONDARY = Color.rgb(208, 219, 234)
        val FOCUS = Color.rgb(189, 215, 255)
        val RED = Color.rgb(190, 44, 60)
    }
}
