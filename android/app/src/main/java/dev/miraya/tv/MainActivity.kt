package dev.miraya.tv

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.text.InputFilter
import android.text.InputType
import android.net.ConnectivityManager
import android.net.Network
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity(), ReceiverServer.Listener, SurfaceHolder.Callback {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var root: FrameLayout
    private lateinit var surfaceView: SurfaceView
    private lateinit var home: LinearLayout
    private lateinit var homeFrame: FrameLayout
    private lateinit var friendlyName: TextView
    private lateinit var namingHint: TextView
    private lateinit var title: TextView
    private lateinit var detail: TextView
    private lateinit var network: TextView
    private lateinit var badge: TextView
    private lateinit var code: TextView
    private lateinit var controls: LinearLayout
    private lateinit var streamingName: TextView
    private lateinit var stopButton: Button
    private lateinit var refreshButton: Button
    @Volatile private var server: ReceiverServer? = null
    @Volatile private var active = false
    @Volatile private var currentSurface: Surface? = null
    private var identity: Identity? = null
    private var dialog: AlertDialog? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var streaming = false
    private var videoWidth = 1920
    private var videoHeight = 1080
    private var port = 7421
    private var generation = 0
    private val hideControls = Runnable { if (streaming) { controls.visibility = View.GONE; surfaceView.requestFocus() } }
    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { refreshAddress() }
        override fun onLost(network: Network) { refreshAddress() }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        buildUI()
    }
    override fun onStart() {
        super.onStart(); active = true; generation++
        val started = generation
        title.text = "Getting ready…"; detail.text = "Preparing a secure connection for your Mac."
        try {
            multicastLock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager).createMulticastLock("Miraya discovery").apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) { }
        try { connectivity.registerDefaultNetworkCallback(networkCallback) } catch (_: Exception) { }
        Thread({
            try {
                val prepared = identity ?: Identity(applicationContext)
                main.post {
                    if (active && generation == started) {
                        identity = prepared; code.text = prepared.pairingCode; updateName()
                        server = ReceiverServer(applicationContext, prepared, this)
                    }
                }
            } catch (_: Exception) {
                onStatus("Secure connection unavailable", "The TV could not create its security identity. Check free storage and reopen Miraya.")
            }
        }, "Miraya identity").start()
    }
    override fun onStop() {
        active = false; generation++; main.removeCallbacks(hideControls)
        dismissApproval(); server?.close(); server = null
        try { connectivity.unregisterNetworkCallback(networkCallback) } catch (_: Exception) { }
        try { multicastLock?.release() } catch (_: Exception) { }; multicastLock = null
        setStreaming(false)
        super.onStop()
    }

    private fun buildUI() {
        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = SurfaceView(this).apply { holder.addCallback(this@MainActivity); isFocusable = true; isFocusableInTouchMode = true }
        root.addView(surfaceView, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> layoutVideo() }
        homeFrame = FrameLayout(this)
        homeFrame.addView(SignalArtView(this, true), FrameLayout.LayoutParams(-1, -1))
        home = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(52), dp(28), dp(52), dp(22)) }
        homeFrame.addView(home, FrameLayout.LayoutParams(-1, -1))
        root.addView(homeFrame, FrameLayout.LayoutParams(-1, -1))
        val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val branding = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        branding.addView(label("Miraya", 32, WHITE, true).apply { letterSpacing = -.04f })
        branding.addView(label("YOUR SCREEN, ON THE BIG SCREEN.", 10, MUTED).apply { letterSpacing = .18f; setPadding(0, dp(3), 0, 0) })
        header.addView(branding, LinearLayout.LayoutParams(0, -2, 1f))
        badge = label("Starting", 14, ACCENT).apply { setPadding(dp(14), dp(8), dp(14), dp(8)); background = rounded(PANEL, 30) }
        header.addView(badge); home.addView(header)
        val columns = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        home.addView(columns, LinearLayout.LayoutParams(-1, 0, 1f))
        val intro = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(12), dp(24), dp(12)) }
        columns.addView(intro, LinearLayout.LayoutParams(0, -2, 1f))
        title = label("Getting ready…", 36, WHITE)
        intro.addView(title)
        detail = label("Preparing a secure connection for your Mac.", 19, MUTED).apply { setPadding(0, dp(12), 0, dp(22)); setLineSpacing(dp(3).toFloat(), 1f) }
        intro.addView(detail)
        val receiverCard = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(18), dp(14), dp(18), dp(14)); background = rounded(0xB3112541.toInt(), 16, 0xAA2E67AB.toInt()) }
        receiverCard.addView(label("▣", 30, ACCENT).apply { setPadding(0, 0, dp(14), 0) })
        val receiverText = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        friendlyName = label("This TV", 23, WHITE)
        namingHint = label("Choose a room name with Rename TV", 12, MUTED).apply { setPadding(0, dp(4), 0, 0) }
        receiverText.addView(friendlyName); receiverText.addView(namingHint)
        receiverCard.addView(receiverText, LinearLayout.LayoutParams(0, -2, 1f)); intro.addView(receiverCard)
        columns.addView(SignalArtView(this), LinearLayout.LayoutParams(0, dp(240), 1f))
        val pairing = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(0, 0, 0, dp(14)) }
        val pairingText = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        pairingText.addView(label("Enter this TV code on your Mac", 13, MUTED))
        pairingText.addView(label("First connection only. Then choose Allow on this TV.", 11, MUTED).apply { setPadding(0, dp(3), 0, 0) })
        pairing.addView(pairingText, LinearLayout.LayoutParams(0, -2, 1f))
        code = label("••••-••••-••••-••••", 19, WHITE, true).apply { typeface = Typeface.create("monospace", Typeface.BOLD); setTextIsSelectable(false); setPadding(dp(16), dp(10), dp(16), dp(10)); background = rounded(0xAA10243C.toInt(), 10, 0x663B82F6) }
        pairing.addView(code); home.addView(pairing)
        network = label("", 16, MUTED)
        val footer = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        refreshButton = button("Rename TV") { renameTV() }
        footer.addView(refreshButton)
        footer.addView(button("Connection details") { showConnectionDetails() }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(12) })
        footer.addView(button("Forget trusted Macs") {
            AlertDialog.Builder(this).setTitle("Forget all trusted Macs?")
                .setMessage("Each Mac will need this TV code and your approval before sharing again.")
                .setNegativeButton("Cancel", null).setPositiveButton("Forget all") { _, _ -> server?.revokeTrust(); detail.text = "Trusted Macs removed. Pair from your Mac using this TV code." }.show()
        }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(12) })
        home.addView(footer)
        home.addView(label("Make sure your Mac is on the same Wi-Fi or local network.  •  Private and encrypted", 12, MUTED).apply { setPadding(0, dp(13), 0, 0) })

        controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(24), dp(14), dp(24), dp(14)); background = rounded(0xEE162638.toInt(), 16); visibility = View.GONE
        }
        streamingName = label("Sharing from Mac", 18, Color.WHITE)
        controls.addView(streamingName, LinearLayout.LayoutParams(0, -2, 1f))
        stopButton = button("Stop sharing") { server?.stopSharing() }
        controls.addView(stopButton)
        root.addView(controls, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply { setMargins(dp(48), 0, dp(48), dp(28)) })
        setContentView(root); refreshButton.requestFocus()
    }
    private fun label(value: String, size: Int, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value; textSize = size.toFloat(); setTextColor(color); if (bold) setTypeface(typeface, Typeface.BOLD)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }
    private fun button(value: String, action: () -> Unit) = Button(this).apply {
        text = value; textSize = 15f; isAllCaps = false; setTextColor(Color.WHITE); minHeight = dp(48); minimumHeight = dp(48)
        setPadding(dp(20), dp(10), dp(20), dp(10)); background = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), rounded(0xFF164679.toInt(), 10, ACCENT))
            addState(intArrayOf(android.R.attr.state_pressed), rounded(0xFF164679.toInt(), 10, ACCENT))
            addState(intArrayOf(), rounded(PANEL, 10, 0xFF304868.toInt()))
        }
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused -> v.animate().scaleX(if (focused) 1.04f else 1f).scaleY(if (focused) 1.04f else 1f).setDuration(100).start() }
    }
    private fun rounded(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(radius).toFloat(); stroke?.let { setStroke(dp(2), it) }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun refreshAddress() { main.post { if (::network.isInitialized) network.text = "${ReceiverServer.localAddresses()}\nPort $port" } }
    private fun updateName() { friendlyName.text = identity?.name ?: "This TV"; namingHint.text = if (identity?.hasCustomName == true) "Miraya Receiver • Visible to nearby Macs" else "Choose a room name with Rename TV" }
    private fun showConnectionDetails() {
        AlertDialog.Builder(this).setTitle("Connection details")
            .setMessage("${identity?.name ?: "Miraya TV"}\n\nChoose this TV by name in Miraya on your Mac. Both devices must be on the same local network.\n\nIf automatic discovery is blocked, use:\n${ReceiverServer.localAddresses()}\nPort $port\n\nTV code: ${identity?.pairingCode ?: "Preparing…"}\n\nNothing is sent through the internet.")
            .setNegativeButton("Done", null).setNeutralButton("Refresh") { _, _ -> showConnectionDetails() }.show()
    }
    private fun renameTV() {
        AlertDialog.Builder(this).setTitle("Name this TV")
            .setItems(arrayOf("Living Room TV", "Bedroom TV", "Office TV", "Custom name…")) { _, which ->
                if (which < 3) saveTVName(arrayOf("Living Room TV", "Bedroom TV", "Office TV")[which]) else customTVName()
            }.setNegativeButton("Cancel", null).show()
    }
    private fun customTVName() {
        val input = EditText(this).apply { setText(identity?.name ?: ""); setSelectAllOnFocus(true); isSingleLine = true; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_WORDS; filters = arrayOf(InputFilter.LengthFilter(32)); hint = "For example, Living Room TV"; setPadding(dp(24), dp(16), dp(24), dp(16)) }
        val editor = AlertDialog.Builder(this).setTitle("TV name").setView(input).setNegativeButton("Cancel", null).setPositiveButton("Save", null).create()
        editor.setOnShowListener { editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val value = input.text.toString().trim()
            if (value.isBlank() || value.any { it.isISOControl() }) input.error = "Enter a name between 1 and 32 characters"
            else { saveTVName(value); editor.dismiss() }
        } }
        editor.show(); input.requestFocus()
    }
    private fun saveTVName(value: String) {
        try {
            val prepared = identity ?: return
            prepared.rename(value); updateName()
            // Settings are available only while idle; restarting also re-registers DNS-SD atomically with this stable identity.
            server?.close(); server = ReceiverServer(applicationContext, prepared, this)
        } catch (_: Exception) { detail.text = "Could not save this TV name. Check free storage and try again." }
    }

    override fun onListening(port: Int, addresses: String, discoveryAvailable: Boolean) { main.post {
        if (!active) return@post
        this.port = port; badge.text = if (discoveryAvailable) "●  Visible on your network" else "Discovery unavailable"
        network.text = "$addresses\nPort $port"
        if (!streaming) {
            title.text = "Ready to receive"
            detail.text = if (discoveryAvailable) "Open Miraya on your Mac and select this TV to start sharing your screen." else "Open Miraya on your Mac. If this TV isn't listed, check Connection details for help."
        }
    } }
    override fun onStatus(title: String, detail: String) { main.post { if (active) { this.title.text = title; this.detail.text = detail } } }
    override fun approve(name: String, respond: (Boolean) -> Unit) { main.post {
        if (!active) { respond(false); return@post }
        dialog?.dismiss()
        var answered = false
        val approvalDialog = AlertDialog.Builder(this).setTitle("Allow $name to share?")
            .setMessage("Only allow this if you are connecting from your Mac now. The Mac screen and optional system audio will appear on this TV.")
            .setNegativeButton("Decline") { _, _ -> answered = true; respond(false) }
            .setPositiveButton("Allow") { _, _ -> answered = true; respond(true) }
            .setOnCancelListener { answered = true; respond(false) }.create()
        approvalDialog.setOnDismissListener { if (!answered) respond(false); if (dialog === approvalDialog) dialog = null }
        dialog = approvalDialog; approvalDialog.show()
        approvalDialog.getButton(AlertDialog.BUTTON_POSITIVE).isAllCaps = false
        approvalDialog.getButton(AlertDialog.BUTTON_NEGATIVE).isAllCaps = false
        approvalDialog.getButton(AlertDialog.BUTTON_NEGATIVE).requestFocus()
    } }
    override fun dismissApproval() { main.post { dialog?.dismiss(); dialog = null } }
    override fun surface(): Surface? = currentSurface
    override fun onStreaming(name: String, streaming: Boolean) { main.post {
        if (active) {
            streamingName.text = "Sharing from $name  •  Back to stop"
            setStreaming(streaming)
        }
    } }
    private fun setStreaming(value: Boolean) {
        streaming = value; main.removeCallbacks(hideControls)
        homeFrame.visibility = if (value) View.GONE else View.VISIBLE
        if (value) { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); showControls() }
        else { window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); controls.visibility = View.GONE; refreshButton.requestFocus() }
    }
    private fun showControls() { controls.visibility = View.VISIBLE; stopButton.requestFocus(); main.removeCallbacks(hideControls); main.postDelayed(hideControls, 6000) }
    override fun onVideoSize(width: Int, height: Int) { main.post { videoWidth = width; videoHeight = height; layoutVideo() } }
    private fun layoutVideo() {
        if (root.width == 0 || root.height == 0) return
        val scale = minOf(root.width.toDouble() / videoWidth, root.height.toDouble() / videoHeight)
        val width = (videoWidth * scale).toInt(); val height = (videoHeight * scale).toInt()
        val current = surfaceView.layoutParams
        if (current.width != width || current.height != height) surfaceView.layoutParams = FrameLayout.LayoutParams(width, height, Gravity.CENTER)
    }
    override fun surfaceCreated(holder: SurfaceHolder) { currentSurface = holder.surface }
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { currentSurface = holder.surface }
    override fun surfaceDestroyed(holder: SurfaceHolder) { currentSurface = null; if (streaming) server?.stopSharing() }
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (streaming && keyCode == KeyEvent.KEYCODE_BACK) { server?.stopSharing(); return true }
        if (streaming && controls.visibility != View.VISIBLE && keyCode in intArrayOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_ENTER)) { showControls(); return true }
        if (streaming) { main.removeCallbacks(hideControls); main.postDelayed(hideControls, 6000) }
        return super.onKeyDown(keyCode, event)
    }
    companion object {
        private val WHITE = Color.rgb(244, 248, 255)
        private val PANEL = Color.rgb(17, 33, 57)
        private val ACCENT = Color.rgb(0, 229, 255)
        private val MUTED = Color.rgb(167, 199, 255)
    }
}
