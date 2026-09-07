package com.example.justride_ui

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * JustRide Notification Listener Service.
 *
 * 1. Required by MediaSessionManager.getActiveSessions() for media controls.
 * 2. Captures latest incoming notifications to display on the motorcycle HUD.
 */
class JustRideNotificationListener : NotificationListenerService() {

    companion object {
        data class NotificationPayload(
            val title: String,
            val message: String,
            val packageName: String
        )

        @Volatile
        var latestNotification: NotificationPayload? = null

        @Volatile
        var onNotificationReceived: ((title: String, message: String, packageName: String) -> Unit)? = null

        fun publish(title: String, message: String, packageName: String) {
            val payload = NotificationPayload(title, message, packageName)
            latestNotification = payload
            onNotificationReceived?.invoke(payload.title, payload.message, payload.packageName)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkg = sbn.packageName ?: ""
        // Skip own app notifications to avoid echoing self-alerts
        if (pkg == "com.example.justride_ui" || pkg == "com.justride.app") {
            return
        }

        val notification = sbn.notification ?: return
        // Media notifications are ongoing on most Android versions.  Ignore them
        // specifically, but retain ongoing incoming-call and messaging alerts.
        if (notification.category == Notification.CATEGORY_TRANSPORT) {
            return
        }

        val extras = notification.extras ?: return
        val title = (extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString()?.trim() ?: ""
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim() ?: ""

        // Phone and VoIP apps expose the contact name in notification extras.
        // Use a stable heading so the ESP32 HUD shows the person, rather than
        // a generic phone-app label or an empty phone number from TelephonyCallback.
        if (notification.category == Notification.CATEGORY_CALL) {
            val caller = when {
                title.isNotEmpty() && !title.equals("incoming call", ignoreCase = true) -> title
                text.isNotEmpty() && !text.equals("incoming call", ignoreCase = true) -> text
                else -> "Unknown caller"
            }
            publish("Incoming call", caller, pkg)
            return
        }

        // Only send if there is readable content
        if (title.isNotEmpty() || text.isNotEmpty()) {
            val resolvedTitle = if (title.isNotEmpty()) title else "Alert"
            val resolvedText = if (text.isNotEmpty()) text else "New notification"
            publish(resolvedTitle, resolvedText, pkg)
        }
    }
}
