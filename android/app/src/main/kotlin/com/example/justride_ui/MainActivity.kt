package com.example.justride_ui

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.SystemClock
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.view.KeyEvent
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val MEDIA_CHANNEL = "com.justride.app/system_media"
    private val CALL_CHANNEL = "com.justride.app/telephony"
    private val NOTIFICATION_CHANNEL = "com.justride.app/system_notifications"
    private val MAPS_CONFIG_CHANNEL = "com.justride.app/maps_config"
    private val SHARE_INTENT_CHANNEL = "com.justride.app/share_intent"
    private val CALL_PERMISSION_REQUEST = 4101
    private val NOTIFICATION_PERMISSION_REQUEST = 4102

    private var callChannel: MethodChannel? = null
    private var notifChannel: MethodChannel? = null
    private var shareMethodChannel: MethodChannel? = null
    private var pendingSharedPayload: String? = null
    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: Any? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingShareIntent(intent)
    }

    private fun handleIncomingShareIntent(intent: Intent?) {
        if (intent == null) return
        var textPayload: String? = null

        when (intent.action) {
            Intent.ACTION_SEND -> {
                val extraText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                val extraSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                    ?: intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()

                textPayload = when {
                    extraSubject != null && extraText != null -> {
                        if (extraText.contains(extraSubject)) extraText else "$extraSubject\n$extraText"
                    }
                    extraText != null -> extraText
                    extraSubject != null -> extraSubject
                    else -> null
                }
            }
            Intent.ACTION_VIEW -> {
                textPayload = intent.dataString
            }
        }

        if (!textPayload.isNullOrBlank()) {
            pendingSharedPayload = textPayload
            shareMethodChannel?.invokeMethod("onSharedTextReceived", textPayload)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.justride.app/diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceInfo") {
                    result.success(mapOf(
                        "phone_model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                        "os_version" to Build.VERSION.RELEASE
                    ))
                } else result.notImplemented()
            }
        requestPostNotificationsPermission()

        val shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_INTENT_CHANNEL)
        shareMethodChannel = shareChannel
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> {
                    val payload = pendingSharedPayload
                    pendingSharedPayload = null
                    result.success(payload)
                }
                "reset" -> {
                    pendingSharedPayload = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAPS_CONFIG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApiKey" -> result.success(BuildConfig.GOOGLE_MAPS_API_KEY)
                    "openLocationIq" -> {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://locationiq.com")))
                            result.success(null)
                        } catch (_: android.content.ActivityNotFoundException) {
                            result.error("NO_BROWSER", "No browser is available", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager == null) {
                    result.error("AUDIO_SERVICE_UNAVAILABLE", "AudioManager is null", null)
                    return@setMethodCallHandler
                }

                when (call.method) {
                    "playPause" -> {
                        val controller = getActiveMediaController()
                        val isPlaying = controller?.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING || audioManager.isMusicActive
                        result.success(dispatchMediaCommand(audioManager, if (isPlaying) "pause" else "play", controller))
                    }
                    "play" -> {
                        result.success(dispatchMediaCommand(audioManager, "play"))
                    }
                    "pause" -> {
                        result.success(dispatchMediaCommand(audioManager, "pause"))
                    }
                    "next" -> {
                        result.success(dispatchMediaCommand(audioManager, "next"))
                    }
                    "previous" -> {
                        result.success(dispatchMediaCommand(audioManager, "previous"))
                    }
                    "volumeUp" -> {
                        audioManager.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_RAISE,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(true)
                    }
                    "volumeDown" -> {
                        audioManager.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(true)
                    }
                    "isMusicActive" -> {
                        result.success(audioManager.isMusicActive)
                    }
                    "hasNotificationAccess" -> result.success(hasNotificationListenerAccess())
                    "getPlaybackState" -> {
                        // Returns: 0=unknown, 1=playing, 2=paused, 3=stopped
                        val controller = getActiveMediaController()
                        val state = controller?.playbackState?.state ?: 0
                        val mappedState = when (state) {
                            android.media.session.PlaybackState.STATE_PLAYING -> 1
                            android.media.session.PlaybackState.STATE_PAUSED  -> 2
                            android.media.session.PlaybackState.STATE_STOPPED -> 3
                            else -> if (audioManager.isMusicActive) 1 else 0
                        }
                        result.success(mappedState)
                    }
                    "getMediaTitle" -> {
                        val controller = getActiveMediaController()
                        val title = controller?.metadata
                            ?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""
                        result.success(title)
                    }
                    "getMediaArtist" -> {
                        val controller = getActiveMediaController()
                        val artist = controller?.metadata
                            ?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
                            ?: controller?.metadata
                                ?.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                            ?: ""
                        result.success(artist)
                    }
                    "getMediaSnapshot" -> {
                        // Snapshot of active session for atomic Dart & ESP32 synchronization
                        val controller = getActiveMediaController()
                        val rawState = controller?.playbackState?.state ?: 0
                        val isAudioActive = audioManager.isMusicActive
                        val mappedState = when (rawState) {
                            android.media.session.PlaybackState.STATE_PLAYING -> 1
                            android.media.session.PlaybackState.STATE_PAUSED  -> 2
                            android.media.session.PlaybackState.STATE_STOPPED -> 3
                            else -> if (isAudioActive) 1 else 0
                        }
                        val title = controller?.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""
                        val artist = controller?.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
                            ?: controller?.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
                        val pos = controller?.playbackState?.position?.div(1000)?.toInt() ?: 0
                        val dur = (controller?.metadata?.getLong(android.media.MediaMetadata.METADATA_KEY_DURATION) ?: 0L).div(1000).toInt()
                        val permission = hasNotificationListenerAccess()
                        val actions = controller?.playbackState?.actions ?: 0L
                        var mask = 0
                        if (actions and android.media.session.PlaybackState.ACTION_PLAY != 0L) mask = mask or 1
                        if (actions and android.media.session.PlaybackState.ACTION_PAUSE != 0L) mask = mask or 2
                        if (actions and android.media.session.PlaybackState.ACTION_SKIP_TO_NEXT != 0L) mask = mask or 4
                        if (actions and android.media.session.PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L) mask = mask or 8
                        if (permission && controller != null) mask = mask or 16
                        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val volume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(mapOf(
                            "state" to (if (!permission) 1 else if (controller == null) 2 else if (rawState == android.media.session.PlaybackState.STATE_PLAYING) 4 else if (rawState == android.media.session.PlaybackState.STATE_PAUSED) 3 else 5),
                            "actions" to (if (permission && controller != null) mask else 0),
                            "volume" to (if (maxVolume > 0) volume * 100 / maxVolume else 0),
                            "playbackState" to mappedState,
                            "title" to title,
                            "artist" to artist,
                            "positionSeconds" to pos,
                            "durationSeconds" to dur,
                            "hasSession" to (controller != null || isAudioActive)
                        ))
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Telephony Call Channel ───────────────────────────────────────────
        callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> {
                        startCallMonitoring()
                        result.success(true)
                    }
                    "stopListening" -> {
                        stopCallMonitoring()
                        result.success(true)
                    }
                    "answerCall" -> {
                        val answered = answerIncomingCall()
                        result.success(answered)
                    }
                    "rejectCall" -> {
                        val rejected = rejectIncomingCall()
                        result.success(rejected)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // ── System Notification Listener Channel ──────────────────────────────
        notifChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationAccessGranted" -> {
                        val cn = ComponentName(this@MainActivity, JustRideNotificationListener::class.java)
                        val flat = android.provider.Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                        val granted = flat != null && flat.contains(cn.flattenToString())
                        result.success(granted)
                    }
                    "openNotificationSettings" -> {
                        val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "requestNotificationPermission" -> {
                        requestPostNotificationsPermission()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Connect listener callback to Flutter MethodChannel
        JustRideNotificationListener.onNotificationReceived = { title, message, pkg ->
            runOnUiThread {
                notifChannel?.invokeMethod("onLatestNotification", mapOf(
                    "title" to title,
                    "message" to message,
                    "package" to pkg
                ))
            }
        }
        JustRideNotificationListener.latestNotification?.let { payload ->
            runOnUiThread {
                notifChannel?.invokeMethod("onLatestNotification", mapOf(
                    "title" to payload.title,
                    "message" to payload.message,
                    "package" to payload.packageName
                ))
            }
        }
    }

    private fun requestPostNotificationsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST
            )
        }
    }

    private fun startCallMonitoring() {
        if (telephonyManager != null) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.ANSWER_PHONE_CALLS),
                CALL_PERMISSION_REQUEST
            )
            return
        }
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        val tm = telephonyManager ?: return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        handleCallState(state, null)
                    }
                }
                telephonyCallback = cb
                tm.registerTelephonyCallback(mainExecutor, cb)
            } else {
                @Suppress("DEPRECATION")
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        handleCallState(state, phoneNumber)
                    }
                }
                phoneStateListener = listener
                @Suppress("DEPRECATION")
                tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (e: Exception) {
            telephonyManager = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CALL_PERMISSION_REQUEST) {
            val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
            if (granted) startCallMonitoring()
            callChannel?.invokeMethod("onCallPermissionChanged", mapOf("granted" to granted))
        }
    }

    private fun stopCallMonitoring() {
        val tm = telephonyManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (telephonyCallback as? TelephonyCallback)?.let { tm.unregisterTelephonyCallback(it) }
                telephonyCallback = null
            } else {
                phoneStateListener?.let {
                    @Suppress("DEPRECATION")
                    tm.listen(it, PhoneStateListener.LISTEN_NONE)
                }
                phoneStateListener = null
            }
        } catch (e: Exception) {
            // ignore
        }
        telephonyManager = null
    }

    private fun handleCallState(state: Int, number: String?) {
        val mappedState = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            else -> "UNKNOWN"
        }
        runOnUiThread {
            callChannel?.invokeMethod("onCallStateChanged", mapOf(
                "state" to mappedState,
                "number" to (number ?: "")
            ))
        }
    }

    private fun answerIncomingCall(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                if (telecomManager != null) {
                    @Suppress("DEPRECATION")
                    telecomManager.acceptRingingCall()
                    return true
                }
            }
            // Fallback: media key HEADSETHOOK click to answer
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                sendMediaKeyEvent(audioManager, KeyEvent.KEYCODE_HEADSETHOOK)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            try {
                // Secondary fallback
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    sendMediaKeyEvent(audioManager, KeyEvent.KEYCODE_HEADSETHOOK)
                    true
                } else {
                    false
                }
            } catch (ex: Exception) {
                false
            }
        }
    }

    private fun rejectIncomingCall(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                if (telecomManager != null) {
                    return telecomManager.endCall()
                }
            }
            // Fallback: end call key
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                sendMediaKeyEvent(audioManager, KeyEvent.KEYCODE_ENDCALL)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    sendMediaKeyEvent(audioManager, KeyEvent.KEYCODE_ENDCALL)
                    true
                } else {
                    false
                }
            } catch (ex: Exception) {
                false
            }
        }
    }

    /**
     * Get the highest-priority active MediaController.
     * Priority: actively PLAYING session > any session with metadata > first session.
     * Requires NotificationListenerService permission to be granted by the user.
     */
    private fun getActiveMediaController(): MediaController? {
        return try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return null
            val cn = ComponentName(this, JustRideNotificationListener::class.java)
            val controllers = msm.getActiveSessions(cn)
            controllers.firstOrNull { ctrl ->
                ctrl.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
            } ?: controllers.firstOrNull { ctrl ->
                val title = ctrl.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
                !title.isNullOrEmpty()
            } ?: controllers.firstOrNull()
        } catch (e: SecurityException) {
            // Notification listener permission not granted — fall back to key events
            null
        } catch (e: Exception) {
            null
        }
    }

    private fun hasNotificationListenerAccess(): Boolean {
        val component = ComponentName(this, JustRideNotificationListener::class.java)
        val enabled = android.provider.Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(":").any { entry ->
            ComponentName.unflattenFromString(entry)?.packageName == component.packageName
        }
    }

    /**
     * A MediaController is the most reliable path for Spotify and YouTube Music.
     * Key events are retained only when Android exposes no usable session/action;
     * sending both causes duplicate skips in several players.
     */
    private fun dispatchMediaCommand(audioManager: AudioManager, command: String, existingController: MediaController? = null): Boolean {
        val controller = existingController ?: getActiveMediaController()
        val action = when (command) {
            "play" -> android.media.session.PlaybackState.ACTION_PLAY
            "pause" -> android.media.session.PlaybackState.ACTION_PAUSE
            "next" -> android.media.session.PlaybackState.ACTION_SKIP_TO_NEXT
            "previous" -> android.media.session.PlaybackState.ACTION_SKIP_TO_PREVIOUS
            else -> 0L
        }
        val hasAction = (controller?.playbackState?.actions?.and(action) ?: 0L) != 0L
        if (controller != null && hasAction) {
            return try {
                when (command) {
                    "play" -> controller.transportControls.play()
                    "pause" -> controller.transportControls.pause()
                    "next" -> controller.transportControls.skipToNext()
                    "previous" -> controller.transportControls.skipToPrevious()
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        return false

    }

    private fun sendMediaKeyEvent(audioManager: AudioManager, keyCode: Int) {
        val eventTime = SystemClock.uptimeMillis()
        val downEvent = KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, keyCode, 0)
        val upEvent   = KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP,   keyCode, 0)
        audioManager.dispatchMediaKeyEvent(downEvent)
        audioManager.dispatchMediaKeyEvent(upEvent)
    }
}
