package com.example.justride_ui

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object JustRidePushBridge {
    private var channel: MethodChannel? = null
    private fun prefs(context: Context) = context.getSharedPreferences("justride_push", Context.MODE_PRIVATE)

    fun attach(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.justride.app/push").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "register" -> {
                        prefs(app).edit().putBoolean("signed_in", true).apply()
                        if (FirebaseApp.initializeApp(app) == null) {
                            result.success(mapOf("configured" to false))
                        } else {
                            FirebaseMessaging.getInstance().register().continueWithTask { task ->
                                if (!task.isSuccessful) throw task.exception ?: IllegalStateException("Push registration failed")
                                FirebaseInstallations.getInstance().id
                            }.addOnSuccessListener { fid ->
                                prefs(app).edit().putString("fid", fid).apply()
                                result.success(mapOf("configured" to true, "fid" to fid,
                                    "enabled" to NotificationManagerCompat.from(app).areNotificationsEnabled()))
                            }.addOnFailureListener { result.error("PUSH_REGISTRATION_FAILED", "Could not register notifications", null) }
                        }
                    }
                    "disable" -> {
                        val fid = prefs(app).getString("fid", null)
                        prefs(app).edit().putBoolean("signed_in", false).remove("pending_type").apply()
                        val manager = app.getSystemService(NotificationManager::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            manager.activeNotifications.filter { it.notification.channelId == "justride_updates" }
                                .forEach { manager.cancel(it.id) }
                        }
                        result.success(fid)
                    }
                    "consumeNotification" -> {
                        val type = prefs(app).getString("pending_type", null)
                        prefs(app).edit().remove("pending_type").apply()
                        result.success(type)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun handleIntent(context: Context, intent: Intent?) {
        val type = intent?.getStringExtra("justride_push_type") ?: return
        intent.removeExtra("justride_push_type")
        if (type !in listOf("APP_UPDATE", "FIRMWARE_UPDATE")) return
        prefs(context).edit().putString("pending_type", type).apply()
        channel?.invokeMethod("notificationTapped", null)
    }

    fun registered(context: Context, fid: String) {
        val previous = prefs(context).getString("fid", null)
        prefs(context).edit().putString("fid", fid).apply()
        if (previous != fid) Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("registrationChanged", null)
        }
    }

    fun isSignedIn(context: Context) = prefs(context).getBoolean("signed_in", false)
}

class JustRidePushService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        JustRidePushBridge.registered(this, installationId)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val type = data["type"] ?: return
        if (type !in listOf("APP_UPDATE", "FIRMWARE_UPDATE") || !JustRidePushBridge.isSignedIn(this)) return
        val manager = NotificationManagerCompat.from(this)
        if (!manager.areNotificationsEnabled()) return
        val channelId = "justride_updates"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "JustRide updates", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val id = (type + data["release_id"]).hashCode()
        val intent = Intent(this, MainActivity::class.java)
            .putExtra("justride_push_type", type)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // Keep lock-screen copy minimal, including messages queued by older backends.
        val title = if (type == "APP_UPDATE") "JustRide app update" else "JustRide firmware update"
        val body = if (type == "APP_UPDATE") "A new update is available. Please update the JustRide app."
            else "A new update is available. Please update your JustRide device."
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_justride)
            .setContentTitle(title)
            .setContentText(body)
            .setColor(0xFF6DE5A8.toInt()).setContentIntent(pending).setAutoCancel(true).build()
        try { manager.notify(id, notification) } catch (_: SecurityException) { /* Permission revoked during delivery. */ }
    }
}
