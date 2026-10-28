package com.example.justride_ui

import android.Manifest
import android.companion.AssociationInfo
import android.companion.CompanionDeviceManager
import android.companion.CompanionDeviceService
import android.companion.DevicePresenceEvent
import android.companion.ObservingDevicePresenceRequest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

// One engine owns the BLE connection whether or not an Activity is attached.
// No second native GATT client or second Flutter isolate is created on wakeup.
object JustRideCompanionRuntime {
    const val CHANNEL = "com.justride.app/companion"
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    var visible = false
    private var blePresent = false
    private var connected = false

    fun preferences(context: Context) = context.getSharedPreferences("justride_companion", Context.MODE_PRIVATE)
    fun manager(context: Context) = context.getSystemService(Context.COMPANION_DEVICE_SERVICE) as CompanionDeviceManager
    fun permitted(context: Context): Boolean = Build.VERSION.SDK_INT < 31 ||
        (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
         ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED)

    fun state(context: Context): Map<String, Any> {
        val prefs=preferences(context)
        val address=prefs.getString("address", "") ?: ""
        val associated=if(Build.VERSION.SDK_INT>=31 && permitted(context)) try {
            manager(context).associations.any { it.equals(address, true) }
        } catch (_: Exception) { false } else false
        return mapOf("supported" to (Build.VERSION.SDK_INT>=31 && context.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)),
            "enabled" to (prefs.getBoolean("enabled",false) && associated),
            "address" to address, "visible" to visible, "present" to (blePresent || connected),
            "paused" to prefs.getBoolean("paused",false))
    }

    fun getEngine(context: Context): FlutterEngine {
        engine?.let { return it }
        val app=context.applicationContext
        val loader=FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app,null)
        val created=FlutterEngine(app)
        engine=created
        JustRidePushBridge.attach(app, created)
        JustRideMediaBridge(app).attach(created)
        channel=MethodChannel(created.dartExecutor.binaryMessenger,CHANNEL).apply {
            setMethodCallHandler { call,result ->
                try {
                    when(call.method) {
                        "ready", "status" -> result.success(state(app))
                        "repairMediaBridge" -> {
                            JustRideMediaBridge(app).attach(created)
                            val listener=android.content.ComponentName(app,JustRideNotificationListener::class.java)
                            if(Build.VERSION.SDK_INT>=24 && android.provider.Settings.Secure.getString(app.contentResolver,"enabled_notification_listeners")
                                    ?.split(":")?.any {android.content.ComponentName.unflattenFromString(it)==listener}==true) {
                                android.service.notification.NotificationListenerService.requestRebind(listener)
                            }
                            result.success(true)
                        }
                        "disable" -> { disable(app);result.success(state(app)) }
                        "pause" -> { preferences(app).edit().putBoolean("paused",true).apply();result.success(null) }
                        "resume" -> { preferences(app).edit().putBoolean("paused",false).apply();result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch(e: Exception) {result.error("COMPANION",e.message,null)}
            }
        }
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"companionMain"))
        return created
    }

    fun publish(context: Context) {channel?.invokeMethod("state",state(context))}
    fun show(context: Context) {visible=true;getEngine(context);publish(context)}
    fun hide(context: Context) {visible=false;publish(context)}

    fun observe(context: Context,address: String) {
        if(Build.VERSION.SDK_INT<31 || !permitted(context))return
        val cdm=manager(context)
        if(Build.VERSION.SDK_INT>=36) {
            val association=cdm.myAssociations.firstOrNull {it.deviceMacAddress?.toString().equals(address,true)} ?: return
            cdm.startObservingDevicePresence(ObservingDevicePresenceRequest.Builder().setAssociationId(association.id).build())
        } else cdm.startObservingDevicePresence(address)
    }

    fun restore(context: Context) {
        if(Build.VERSION.SDK_INT<31 || !permitted(context))return
        val prefs=preferences(context)
        if(!prefs.getBoolean("enabled",false))return
        val address=prefs.getString("address",null) ?: return
        try {observe(context,address)} catch(e: Exception) {Log.w("JustRideCompanion","Presence observation unavailable: ${e.javaClass.simpleName}")}
    }

    fun disable(context: Context) {
        val prefs=preferences(context)
        val address=prefs.getString("address",null)
        // Clear first so a queued appearance event cannot reconnect after unlink/logout.
        prefs.edit().putBoolean("enabled",false).putBoolean("paused",true).remove("address").apply()
        blePresent=false;connected=false
        if(Build.VERSION.SDK_INT>=31 && address!=null && permitted(context)) {
            try {
                val cdm=manager(context)
                if(Build.VERSION.SDK_INT>=33)cdm.myAssociations.filter {it.deviceMacAddress?.toString().equals(address,true)}.forEach {cdm.disassociate(it.id)}
                else cdm.disassociate(address)
            } catch(e: Exception) {Log.w("JustRideCompanion","Association cleanup: ${e.javaClass.simpleName}")}
        }
        publish(context)
    }

    fun presence(context: Context,address: String,appeared: Boolean,bluetooth: Boolean=false) {
        val prefs=preferences(context)
        if(!prefs.getBoolean("enabled",false) || !address.equals(prefs.getString("address",null),true))return
        if(bluetooth)connected=appeared else blePresent=appeared
        if(appeared && !prefs.getBoolean("paused",false) && permitted(context))getEngine(context)
        publish(context)
    }

}

class JustRideCompanionService : CompanionDeviceService() {
    override fun onDeviceAppeared(address: String) {JustRideCompanionRuntime.presence(this,address,true)}
    override fun onDeviceDisappeared(address: String) {JustRideCompanionRuntime.presence(this,address,false)}
    override fun onDeviceAppeared(associationInfo: AssociationInfo) {
        associationInfo.deviceMacAddress?.toString()?.let {JustRideCompanionRuntime.presence(this,it,true)}
    }
    override fun onDeviceDisappeared(associationInfo: AssociationInfo) {
        associationInfo.deviceMacAddress?.toString()?.let {JustRideCompanionRuntime.presence(this,it,false)}
    }
    override fun onDevicePresenceEvent(event: DevicePresenceEvent) {
        if(Build.VERSION.SDK_INT<36 || !JustRideCompanionRuntime.permitted(this))return
        val association=try {JustRideCompanionRuntime.manager(this).myAssociations.firstOrNull {it.id==event.associationId}}
            catch (_: SecurityException) {null} ?: return
        val address=association.deviceMacAddress?.toString() ?: return
        when(event.event) {
            DevicePresenceEvent.EVENT_BLE_APPEARED -> JustRideCompanionRuntime.presence(this,address,true)
            DevicePresenceEvent.EVENT_BLE_DISAPPEARED -> JustRideCompanionRuntime.presence(this,address,false)
            DevicePresenceEvent.EVENT_BT_CONNECTED -> JustRideCompanionRuntime.presence(this,address,true,true)
            DevicePresenceEvent.EVENT_BT_DISCONNECTED -> JustRideCompanionRuntime.presence(this,address,false,true)
        }
    }
}

class JustRideCompanionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context,intent: Intent) {
        if(intent.action==Intent.ACTION_BOOT_COMPLETED || intent.action==Intent.ACTION_MY_PACKAGE_REPLACED ||
            (intent.action==android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED &&
             intent.getIntExtra(android.bluetooth.BluetoothAdapter.EXTRA_STATE,-1)==android.bluetooth.BluetoothAdapter.STATE_ON)) {
            JustRideCompanionRuntime.restore(context)
        }
    }
}
