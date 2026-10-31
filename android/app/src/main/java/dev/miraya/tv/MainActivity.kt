package dev.miraya.tv

import androidx.media3.common.Player
import androidx.media3.common.C
import androidx.media3.common.TrackSelectionOverride
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

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class MainActivity : Activity(), ReceiverServer.Listener, SurfaceHolder.Callback {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var root: FrameLayout
    private lateinit var surfaceView: SurfaceView
    private lateinit var directView: androidx.media3.ui.PlayerView
    private var directPlayback = false
    private lateinit var videoArea: FrameLayout
    private lateinit var home: LinearLayout
    private lateinit var homeFrame: FrameLayout
    private lateinit var friendlyName: TextView
    private lateinit var namingHint: TextView
    private lateinit var title: TextView
    private lateinit var detail: TextView
    private lateinit var network: TextView
    private lateinit var badge: TextView
    private lateinit var code: TextView
    private lateinit var pairingHint: TextView
    private lateinit var controls: LinearLayout
    private lateinit var streamingName: TextView
    private lateinit var stopButton: View
    private lateinit var refreshButton: Button
    @Volatile private var server: ReceiverServer? = null
    @Volatile private var active = false
    @Volatile private var currentSurface: Surface? = null
    private var identity: Identity? = null
    private var dialog: AlertDialog? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var streaming = false
    private var paused = false
    private var videoWidth = 1920
    private var videoHeight = 1080
    private val picturePreferences by lazy { getSharedPreferences("presentation", MODE_PRIVATE) }
    private var presentation = PresentationSettings()
    @Volatile private var screen = TVDisplay(1920, 1080, 1920, 1080, 60.0, PresentationSettings())
    private var port = 7421
    private var generation = 0
    private val hideControls = Runnable { if (streaming) { controls.visibility = View.GONE; if (directPlayback) directView.requestFocus() else surfaceView.requestFocus() } }
    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { refreshAddress() }
        override fun onLost(network: Network) { refreshAddress() }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        presentation = PresentationSettings(PictureMode.parse(picturePreferences.getString("mode", "fit") ?: "fit") ?: PictureMode.FIT, picturePreferences.getInt("margin", 0).coerceIn(0, 10))
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
                        identity = prepared; code.text = "— — — — — —"; updateName()
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
        observedPlayer?.removeListener(playbackObserver); observedPlayer = null
        dismissApproval(); server?.close(); server = null
        try { connectivity.unregisterNetworkCallback(networkCallback) } catch (_: Exception) { }
        try { multicastLock?.release() } catch (_: Exception) { }; multicastLock = null
        setStreaming(false)
        super.onStop()
    }

    private lateinit var beam: BeamReceiverUI
    private var panel: View? = null
    private var lastComparisonCode: String? = null
    private var comparingCode = false
    private var waitingForPicture = false
    private var pendingApproval: ((Boolean) -> Unit)? = null
    private lateinit var idleButtons: LinearLayout
    private lateinit var pictureButton: View
    private lateinit var overlayActions: LinearLayout
    private lateinit var overlayCaption: TextView
    private var mediaToggle: View? = null
    private var observedPlayer: Player? = null
    private val playbackObserver = object : Player.Listener {
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) { updateMediaToggle() }
        override fun onPlaybackStateChanged(playbackState: Int) { updateMediaToggle() }
    }

    private fun buildUI() {
        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = SurfaceView(this).apply { holder.addCallback(this@MainActivity); isFocusable = true; isFocusableInTouchMode = true }
        videoArea = FrameLayout(this).apply { clipChildren = true; clipToPadding = true }
        videoArea.addView(surfaceView, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER)); root.addView(videoArea, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        directView = androidx.media3.ui.PlayerView(this).apply { visibility = View.GONE; setKeepContentOnPlayerReset(false) }
        root.addView(directView, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> layoutVideo() }
        beam = BeamReceiverUI(this); homeFrame = beam; root.addView(beam, FrameLayout.LayoutParams(-1, -1))
        title = beam.title; detail = beam.detail; friendlyName = beam.friendlyName; badge = beam.badge; code = beam.code; pairingHint = beam.pairingHint
        namingHint = beam.label("", 12); network = beam.label("", 16)
        idleButtons = beam.footerActions
        refreshButton = button("Connection details") { showConnectionDetails() }
        resetIdleActions()
        controls = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(14), dp(20), dp(14)); background = beam.glass(); elevation = dp(8).toFloat(); visibility = View.GONE }
        val overlayHeading = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        overlayHeading.addView(android.widget.ImageView(this).apply { setImageResource(R.drawable.beam_mark); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }, LinearLayout.LayoutParams(dp(28), dp(28)))
        streamingName = label("Sharing from your Mac", 17, WHITE, true).apply { maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }
        overlayHeading.addView(streamingName, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(10) })
        controls.addView(overlayHeading)
        overlayActions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
        controls.addView(overlayActions, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        overlayCaption = label("", 12, MUTED)
        controls.addView(overlayCaption, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        buildOverlayActions()
        root.addView(controls, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply { setMargins(dp(76), 0, dp(76), dp(32)) })
        setContentView(root); refreshButton.requestFocus()
    }
    private fun buildOverlayActions() {
        overlayActions.removeAllViews(); mediaToggle = null
        if (directPlayback) {
            mediaToggle = beam.remoteAction("Pause", R.drawable.beam_action_pause) { toggleMedia(); showControls() }
            overlayActions.addView(mediaToggle, LinearLayout.LayoutParams(0, -2, 1f))
        }
        pictureButton = beam.remoteAction("Fit / Fill", R.drawable.beam_action_display) { showPictureSettings() }
        overlayActions.addView(pictureButton, LinearLayout.LayoutParams(0, -2, 1f))
        overlayActions.addView(beam.remoteAction("TV volume", R.drawable.beam_action_speaker) { showVolumeHelp() }, LinearLayout.LayoutParams(0, -2, 1f))
        overlayActions.addView(beam.remoteAction(if (directPlayback) "Playback" else "Details", R.drawable.beam_action_info) { if (directPlayback) showPlaybackSettings() else showConnectionDetails() }, LinearLayout.LayoutParams(0, -2, 1f))
        stopButton = beam.remoteAction("Stop", R.drawable.beam_action_stop, true) { server?.stopSharing() }
        overlayActions.addView(stopButton, LinearLayout.LayoutParams(0, -2, 1f))
        overlayCaption.text = if (directPlayback) "Original media · Use Playback for seeking and tracks.    Back stops playback." else "Pause / resume mirroring on your Mac.                 Back stops sharing."
        updateMediaToggle()
    }
    private fun toggleMedia() { directView.player?.let { if (it.playWhenReady) it.pause() else { if (it.playbackState == Player.STATE_ENDED) it.seekToDefaultPosition(); it.play() } } }
    private fun updateMediaToggle() {
        val toggle = mediaToggle as? LinearLayout ?: return
        val playing = directView.player?.playWhenReady != false
        paused = !playing
        if (paused) { main.removeCallbacks(hideControls); if (streaming) controls.visibility = View.VISIBLE }
        val label = if (playing) "Pause" else "Resume"
        toggle.contentDescription = label
        (toggle.getChildAt(1) as TextView).text = label
        ((toggle.getChildAt(0) as FrameLayout).getChildAt(0) as android.widget.ImageView).setImageResource(if (playing) R.drawable.beam_action_pause else R.drawable.beam_action_play)
    }
    private fun attachPlaybackObserver(attempt: Int = 0) {
        if (!active || !directPlayback) return
        val player = directView.player
        if (player == null) { if (attempt < 20) main.postDelayed({ attachPlaybackObserver(attempt + 1) }, 50); return }
        if (observedPlayer !== player) { observedPlayer?.removeListener(playbackObserver); observedPlayer = player; player.addListener(playbackObserver) }
        updateMediaToggle()
    }
    private fun showPlaybackSettings() {
        val player = directView.player ?: return
        openPanel("Playback controls") { body ->
            paragraph(body, "Original media is decoded on this TV. Your Mac desktop is not shared.")
            panelButton(body, if (player.playWhenReady) "Pause playback" else "Resume playback") { toggleMedia(); showPlaybackSettings() }
            if (player.isCurrentMediaItemSeekable && player.duration > 0) {
                val position = label("${mediaTime(player.currentPosition)} / ${mediaTime(player.duration)}", 16, WHITE)
                body.addView(position)
                val seek = android.widget.SeekBar(this).apply {
                    max = 1000; progress = (player.currentPosition * 1000 / player.duration).toInt().coerceIn(0, 1000)
                    isFocusable = true; isFocusableInTouchMode = true; setKeyProgressIncrement(1); contentDescription = "Video playback position"
                }
                seek.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(bar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) { if (fromUser) position.text = "${mediaTime(player.duration * progress / 1000)} / ${mediaTime(player.duration)}" }
                    override fun onStartTrackingTouch(bar: android.widget.SeekBar?) = Unit
                    override fun onStopTrackingTouch(bar: android.widget.SeekBar?) { player.seekTo(player.duration * seek.progress / 1000) }
                })
                seek.setOnKeyListener { _, key, event -> if (event.action == KeyEvent.ACTION_UP && key in intArrayOf(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)) player.seekTo(player.duration * seek.progress / 1000); false }
                body.addView(seek, LinearLayout.LayoutParams(-1, dp(48)))
                panelButton(body, "Back 10 seconds") { player.seekTo((player.currentPosition - 10000).coerceAtLeast(0)); showPlaybackSettings() }
                panelButton(body, "Forward 10 seconds") { player.seekTo((player.currentPosition + 10000).coerceAtMost(player.duration)); showPlaybackSettings() }
            }
            for (type in listOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_TEXT)) {
                paragraph(body, if (type == C.TRACK_TYPE_AUDIO) "Audio tracks" else "Subtitles")
                panelButton(body, "Automatic") { player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type, false).build(); closePanel() }
                if (type == C.TRACK_TYPE_TEXT) panelButton(body, "Subtitles off") { player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type, true).build(); closePanel() }
                for (group in player.currentTracks.groups.filter { it.type == type }) for (index in 0 until group.length) if (group.isTrackSupported(index)) {
                    val format = group.getTrackFormat(index)
                    panelButton(body, format.label ?: format.language ?: "Track ${index + 1}") {
                        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type, false).addOverride(TrackSelectionOverride(group.mediaTrackGroup, index)).build()
                        closePanel()
                    }
                }
            }
            panelButton(body, "Connection details") { showConnectionDetails() }
        }
    }
    private fun mediaTime(ms: Long): String { val seconds = (ms.coerceAtLeast(0) / 1000); return "%d:%02d".format(seconds / 60, seconds % 60) }
    private fun resetIdleActions() {
        idleButtons.removeAllViews()
        idleButtons.addView(refreshButton)
        idleButtons.addView(button("Trusted Macs") { manageTrustedMacs() }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(14) })
        idleButtons.addView(button("Rename TV") { renameTV() }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(14) })
        beam.footerHint.text = "Keep Miraya open here. On your Mac, choose this TV and Share."
        refreshButton.post { if (homeFrame.visibility == View.VISIBLE && pendingApproval == null && panel == null) refreshButton.requestFocus() }
    }
    private fun label(value: String, size: Int, color: Int, bold: Boolean = false) = beam.label(value, size, color, bold)
    private fun button(value: String, action: () -> Unit) = beam.button(value, action = action)
    private fun rounded(color: Int, radius: Int, stroke: Int? = null) = beam.surface(color, radius, stroke)
    private fun dp(value: Int) = beam.unit(value)
    private fun openPanel(heading: String, build: (LinearLayout) -> Unit) {
        main.removeCallbacks(hideControls); closePanel(false)
        homeFrame.descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        controls.descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        directView.descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        surfaceView.isFocusable = false; directView.isFocusable = false
        val pane = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(32), dp(28), dp(48), dp(28)); setBackgroundColor(0xFC111C2F.toInt()); elevation = dp(12).toFloat() }
        pane.addView(label(heading, 27, WHITE, true), LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(16) })
        val scroll = android.widget.ScrollView(this).apply { isFillViewport = false }
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        build(body); scroll.addView(body); pane.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val done = button("Done") { closePanel() }; pane.addView(done, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
        panel = pane; root.addView(pane, FrameLayout.LayoutParams((resources.displayMetrics.widthPixels * .54).toInt(), -1, Gravity.END))
        (body.getFocusables(View.FOCUS_FORWARD).firstOrNull() ?: done).requestFocus()
    }
    private fun closePanel(restore: Boolean = true) {
        panel?.let { root.removeView(it) }; panel = null
        homeFrame.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        controls.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        directView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        surfaceView.isFocusable = true; directView.isFocusable = true
        if (restore) { if (streaming) showControls() else refreshButton.requestFocus() }
    }
    private fun paragraph(body: LinearLayout, value: String) { body.addView(label(value, 15, MUTED), LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(16) }) }
    private fun panelButton(body: LinearLayout, value: String, destructive: Boolean = false, action: () -> Unit) { body.addView(beam.button(value, destructive, action), LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(12) }) }
    private fun showVolumeHelp() { openPanel("TV volume") { body -> paragraph(body, "Use your TV remote’s volume and mute keys."); paragraph(body, "The Mac’s TV playback slider changes Miraya’s sound level, not your TV’s master volume."); paragraph(body, "System audio only. No microphone capture.") } }
    private fun refreshAddress() { main.post { if (::network.isInitialized) network.text = "${ReceiverServer.localAddresses()}\nPort $port" } }
    private fun updateName() { friendlyName.text = identity?.name ?: "This TV" }
    private fun showConnectionDetails() {
        openPanel("Connection details") { body ->
            paragraph(body, identity?.name ?: "Miraya Receiver")
            paragraph(body, "${screen.width} × ${screen.height} app viewport\n${screen.panelWidth} × ${screen.panelHeight} · ${screen.refreshRate.toInt()} Hz physical output")
            paragraph(body, "Mirroring ceiling: up to 1920 × 1080 · 60 fps. Actual picture and frame rate may adapt. A 4K output mode does not mean 4K Miraya streaming.")
            paragraph(body, "Manual connection\n${ReceiverServer.localAddresses()}\nPort $port")
            paragraph(body, "Keep Miraya open here. Both devices need a mutually reachable local network. First pairing compares six digits and requires explicit remote approval.")
            panelButton(body, "Refresh details") { showConnectionDetails() }
        }
    }
    private fun manageTrustedMacs() {
        openPanel("Trusted Macs") { body ->
            val macs = identity?.trustedMacs().orEmpty()
            paragraph(body, if (macs.isEmpty()) "No Macs paired yet. Choose this TV from Miraya on your Mac." else "Remove permission for one Mac at a time. It must pair again after removal.")
            macs.forEach { mac -> panelButton(body, mac.name + " · Forget…") {
                openPanel("Forget ${mac.name}?") { confirm ->
                    paragraph(confirm, "This Mac will need to pair again. If it is connected now, sharing will stop.")
                    panelButton(confirm, "Cancel") { manageTrustedMacs() }
                    panelButton(confirm, "Forget Mac", true) { try { server?.revokeMac(mac.id); manageTrustedMacs() } catch (_: Exception) { onStatus("Could not remove permission", "Try again.") } }
                }
            } }
        }
    }
    override fun onPairingCode(code: String?) { main.post {
        if (!active) return@post
        if (code == null && pendingApproval != null) return@post
        comparingCode = code != null
        if (code == null) waitingForPicture = false
        if (code != null) lastComparisonCode = code
        beam.pairing(code)
        if (code != null) {
            idleButtons.removeAllViews(); val cancel = button("Cancel pairing") { server?.stopSharing(); beam.ready(identity?.name ?: "this TV"); resetIdleActions(); refreshButton.requestFocus() }
            idleButtons.addView(cancel); beam.footerHint.text = "Compare all six digits. No typing needed."; cancel.requestFocus()
        } else if (pendingApproval == null && !streaming) { beam.ready(identity?.name ?: "this TV"); resetIdleActions() }
    } }
    override fun onPaused(paused: Boolean) { main.post {
        if (active && streaming) {
            this.paused = paused
            streamingName.text = if (paused) "Paused on your Mac" else "Sharing from your Mac"
            if (paused) { main.removeCallbacks(hideControls); controls.visibility = View.VISIBLE; stopButton.requestFocus() }
            else showControls()
        }
    } }
    private fun renameTV() {
        openPanel("Name this TV") { body ->
            paragraph(body, "The room name appears on nearby Macs. Saved trust uses this TV’s secure identity.")
            listOf("Living Room TV", "Bedroom TV", "Office TV").forEach { name -> panelButton(body, name) { saveTVName(name); closePanel() } }
            panelButton(body, "Custom name…") { customTVName() }
        }
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
        if (!streaming && !comparingCode && !waitingForPicture && pendingApproval == null) {
            beam.ready(identity?.name ?: "this TV", discoveryAvailable)
            if (!discoveryAvailable) detail.text = "If this TV is not listed on your Mac, open Connection details below."
        }
    } }
    override fun onStatus(title: String, detail: String) { main.post { if (active) { this.title.text = if (title == "Ready to share") "Ready for your Mac" else title; this.detail.text = detail } } }
    override fun approve(name: String, respond: (Boolean) -> Unit) { main.post {
        if (!active) { respond(false); return@post }
        pendingApproval?.invoke(false); pendingApproval = respond
        beam.approval(name, lastComparisonCode)
        idleButtons.removeAllViews()
        val decline = button("Decline") { answerApproval(false) }
        idleButtons.addView(decline)
        idleButtons.addView(button("Allow") { answerApproval(true) }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(14) })
        beam.footerHint.text = "Only approve the Mac you are connecting from now."
        decline.requestFocus()
    } }
    private fun answerApproval(allow: Boolean) {
        val response = pendingApproval ?: return; pendingApproval = null
        waitingForPicture = allow
        response(allow)
        if (allow) beam.waitingForPicture() else beam.ready(identity?.name ?: "this TV")
        resetIdleActions(); refreshButton.requestFocus()
    }
    override fun dismissApproval() { main.post {
        pendingApproval?.let { pendingApproval = null; it(false); beam.ready(identity?.name ?: "this TV"); resetIdleActions() }
        dialog?.dismiss(); dialog = null
    } }
    override fun surface(): Surface? = currentSurface
    override fun onStreaming(name: String, streaming: Boolean) { main.post {
        if (active) {
            streamingName.text = "Sharing from $name"
            setStreaming(streaming)
        }
    } }
    override fun directPlayerView(): androidx.media3.ui.PlayerView = directView
    override fun onDirectPlayback(enabled: Boolean) { main.post {
        observedPlayer?.removeListener(playbackObserver); observedPlayer = null
        directPlayback = enabled; directView.useController = false
        buildOverlayActions()
        directView.visibility = if (enabled) View.VISIBLE else View.GONE
        surfaceView.visibility = if (enabled) View.INVISIBLE else View.VISIBLE
        if (enabled) { main.post { attachPlaybackObserver() }; if (streaming) showControls() }
    } }
    private fun setStreaming(value: Boolean) {
        paused = false; waitingForPicture = false; comparingCode = false
        streaming = value; main.removeCallbacks(hideControls)
        homeFrame.visibility = if (value) View.GONE else View.VISIBLE
        if (value) { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); showControls() }
        else { window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); controls.visibility = View.GONE; closePanel(false); beam.ready(identity?.name ?: "this TV"); resetIdleActions(); refreshButton.requestFocus() }
    }
    private fun showControls() { controls.visibility = View.VISIBLE; (mediaToggle ?: pictureButton).requestFocus(); main.removeCallbacks(hideControls); if (!paused) main.postDelayed(hideControls, 6000) }
    override fun onVideoSize(width: Int, height: Int) { main.post { videoWidth = width; videoHeight = height; layoutVideo() } }
    override fun displayInfo(): TVDisplay = screen
    override fun setPresentation(settings: PresentationSettings, respond: (TVDisplay) -> Unit) { main.post {
        if (!active) return@post
        presentation = settings
        picturePreferences.edit().putString("mode", settings.mode.wire).putInt("margin", settings.edgeInsetPercent).apply()
        layoutVideo(); respond(screen)
    } }
    private fun showPictureSettings() {
        openPanel("TV picture") { body ->
            paragraph(body, "Presentation changes how the source fits. It does not change encoded quality.")
            listOf("Fit · Everything visible, bars may appear", "Fill · Fill the TV, deliberately crop edges", "Stretch · Fill the TV, change proportions").forEachIndexed { index, label ->
                panelButton(body, (if (presentation.mode.ordinal == index) "✓  " else "") + label) { setPresentation(presentation.copy(mode = PictureMode.entries[index])) { }; showPictureSettings() }
            }
            panelButton(body, "Edge Margin · ${presentation.edgeInsetPercent}%") { showEdgeMargin() }
        }
    }
    private fun showEdgeMargin() {
        openPanel("Edge Margin") { body ->
            paragraph(body, "One value adjusts every edge equally. Increase it if the TV cuts off corners. Range: 0–10%.")
            val value = label("${presentation.edgeInsetPercent}% on every edge", 18, WHITE, true)
            body.addView(value)
            body.addView(android.widget.SeekBar(this).apply {
                max = 10; progress = presentation.edgeInsetPercent; isFocusable = true; isFocusableInTouchMode = true; setKeyProgressIncrement(1); contentDescription = "Symmetric edge margin, zero to ten percent"
                setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(bar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) { if (fromUser) { value.text = "$progress% on every edge"; setPresentation(presentation.copy(edgeInsetPercent = progress)) { } } }
                    override fun onStartTrackingTouch(bar: android.widget.SeekBar?) = Unit
                    override fun onStopTrackingTouch(bar: android.widget.SeekBar?) = Unit
                })
            }, LinearLayout.LayoutParams(-1, dp(56)))
            paragraph(body, "Fit preserves the whole source within the margin. Screen Fit / Just Scan in your TV settings can also compensate for overscan.")
        }
    }
    private fun layoutVideo() {
        if (root.width == 0 || root.height == 0 || videoWidth <= 0 || videoHeight <= 0) return
        @Suppress("DEPRECATION") val mode = windowManager.defaultDisplay.mode
        screen = TVDisplay(root.width, root.height, mode.physicalWidth, mode.physicalHeight, mode.refreshRate.toDouble(), presentation)
        val layout = presentation.layout(root.width, root.height, videoWidth, videoHeight)
        directView.resizeMode = when (presentation.mode) {
            PictureMode.FIT -> androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
            PictureMode.FILL -> androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            PictureMode.STRETCH -> androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FILL
        }
        if (directView.layoutParams.width != layout.areaWidth || directView.layoutParams.height != layout.areaHeight)
            directView.layoutParams = FrameLayout.LayoutParams(layout.areaWidth, layout.areaHeight, Gravity.CENTER)
        if (videoArea.layoutParams.width != layout.areaWidth || videoArea.layoutParams.height != layout.areaHeight)
            videoArea.layoutParams = FrameLayout.LayoutParams(layout.areaWidth, layout.areaHeight, Gravity.CENTER)
        // Fill crops in the renderer, not through an oversized Surface buffer.
        // Portrait/ultrawide sources must not allocate a many-screen-sized layer.
        val width = if (presentation.mode == PictureMode.FIT) layout.width else layout.areaWidth
        val height = if (presentation.mode == PictureMode.FIT) layout.height else layout.areaHeight
        val current = surfaceView.layoutParams
        if (current.width != width || current.height != height) surfaceView.layoutParams = FrameLayout.LayoutParams(width, height, Gravity.CENTER)
        server?.updatePresentation(screen)
    }
    override fun surfaceCreated(holder: SurfaceHolder) { currentSurface = holder.surface }
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { currentSurface = holder.surface }
    override fun surfaceDestroyed(holder: SurfaceHolder) { currentSurface = null; if (streaming && !directPlayback) server?.stopSharing() }
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && panel != null) { closePanel(); return true }
        if (keyCode == KeyEvent.KEYCODE_BACK && pendingApproval != null) { answerApproval(false); return true }
        if (keyCode == KeyEvent.KEYCODE_BACK && code.visibility == View.VISIBLE && !streaming) { server?.stopSharing(); return true }
        if (streaming && keyCode == KeyEvent.KEYCODE_BACK) { server?.stopSharing(); return true }
        if (streaming && controls.visibility != View.VISIBLE && keyCode in intArrayOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_ENTER)) { showControls(); return true }
        if (streaming && panel == null && !paused) { main.removeCallbacks(hideControls); main.postDelayed(hideControls, 6000) }
        return super.onKeyDown(keyCode, event)
    }
    companion object {
        private val WHITE = BeamReceiverUI.WHITE
        private val PANEL = BeamReceiverUI.PANEL
        private val ACCENT = Color.rgb(52, 120, 246)
        private val MUTED = BeamReceiverUI.SECONDARY
    }
}
