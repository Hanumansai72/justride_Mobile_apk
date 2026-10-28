package com.example.justride_ui

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.SystemClock
import android.view.KeyEvent
import android.util.Log
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Media commands also work when Android wakes the engine without an Activity.
class JustRideMediaBridge(context: Context) : ContextWrapper(context.applicationContext) {
    private val MEDIA_CHANNEL = "com.justride.app/system_media"
    fun attach(flutterEngine: FlutterEngine) {
        val messenger=flutterEngine.dartExecutor.binaryMessenger
        // A slow media app must not block the Flutter/BLE platform thread.
        MethodChannel(messenger, MEDIA_CHANNEL, StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager == null) {
                    result.error("AUDIO_SERVICE_UNAVAILABLE", "AudioManager is null", null)
                    return@setMethodCallHandler
                }

                try { when (call.method) {
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
                        adjustMediaVolume(audioManager, AudioManager.ADJUST_RAISE)
                        result.success(true)
                    }
                    "volumeDown" -> {
                        adjustMediaVolume(audioManager, AudioManager.ADJUST_LOWER)
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
                    "getMediaSnapshot" -> result.success(mediaSnapshot(audioManager))
                    else -> result.notImplemented()
                } } catch(e: Exception) {
                    Log.w("JustRideMedia", "${call.method} failed: ${e.javaClass.simpleName}")
                    result.error("MEDIA_${call.method}", e.javaClass.simpleName, null)
                }
            }
    }

    private fun mediaSnapshot(audioManager: AudioManager): Map<String, Any> {
        if(!hasNotificationListenerAccess()) return mapOf("state" to 1, "actions" to 0)
        val controller=getActiveMediaController() ?: return mapOf("state" to 2, "actions" to 0)
        val playback=controller.playbackState
        // Metadata is optional; a malformed title must not disable playback controls.
        val metadata=runCatching {controller.metadata}.getOrNull()
        val actions=playback?.actions ?: 0L
        var mask=16
        if(actions and android.media.session.PlaybackState.ACTION_PLAY_PAUSE != 0L) mask=mask or 3
        if(actions and android.media.session.PlaybackState.ACTION_PLAY != 0L) mask=mask or 1
        if(actions and android.media.session.PlaybackState.ACTION_PAUSE != 0L) mask=mask or 2
        if(actions and android.media.session.PlaybackState.ACTION_SKIP_TO_NEXT != 0L) mask=mask or 4
        if(actions and android.media.session.PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L) mask=mask or 8
        val remote=controller.playbackInfo?.takeIf {it.playbackType==MediaController.PlaybackInfo.PLAYBACK_TYPE_REMOTE}
        val maxVolume=remote?.maxVolume ?: audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val volume=remote?.currentVolume ?: audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val state=when(playback?.state) {
            android.media.session.PlaybackState.STATE_PLAYING -> 4
            android.media.session.PlaybackState.STATE_PAUSED -> 3
            else -> 5
        }
        return mapOf("state" to state, "actions" to mask,
            "volume" to if(maxVolume>0) volume*100/maxVolume else 0,
            "title" to (runCatching {metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)}.getOrNull() ?: ""),
            "artist" to (runCatching {metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)}.getOrNull() ?: ""))
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
            ComponentName.unflattenFromString(entry) == component
        }
    }

    /**
     * A MediaController is the most reliable path for Spotify and YouTube Music.
     * Honor the active session's advertised actions, including PLAY_PAUSE.
     * Dispatch once; no duplicate key event is sent.
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
        val available = controller?.playbackState?.actions ?: 0L
        val hasDirectAction = available and action != 0L
        val hasToggle = command in listOf("play", "pause") &&
            available and android.media.session.PlaybackState.ACTION_PLAY_PAUSE != 0L
        val hasAction = hasDirectAction || hasToggle
        if (controller != null && hasAction) {
            return try {
                if (!hasDirectAction && hasToggle) {
                    val playing = controller.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
                    if ((command == "play" && playing) || (command == "pause" && !playing)) return true
                    val eventTime = SystemClock.uptimeMillis()
                    val down = controller.dispatchMediaButtonEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0))
                    val up = controller.dispatchMediaButtonEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0))
                    if (down || up) return true
                    // A session can advertise the toggle action but reject key
                    // events. Send the explicit requested state in that case.
                    if (command == "play") controller.transportControls.play()
                    else controller.transportControls.pause()
                    return true
                }
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

    private fun adjustMediaVolume(audioManager: AudioManager, direction: Int) {
        val controller = getActiveMediaController()
        if (controller?.playbackInfo?.playbackType == MediaController.PlaybackInfo.PLAYBACK_TYPE_REMOTE) {
            controller.adjustVolume(direction, AudioManager.FLAG_SHOW_UI)
        } else {
            audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        }
    }
}
