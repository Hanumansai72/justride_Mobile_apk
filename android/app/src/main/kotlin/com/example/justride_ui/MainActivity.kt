package com.example.justride_ui

import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothLeDeviceFilter
import android.companion.CompanionDeviceManager
import android.bluetooth.le.ScanFilter
import android.content.IntentSender
import android.os.Handler
import android.os.Looper
import android.app.Activity
import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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

    private var companionResult: MethodChannel.Result? = null
    private var companionAddress: String? = null
    private val companionRequestCode=4103

    override fun provideFlutterEngine(context: Context): FlutterEngine = JustRideCompanionRuntime.getEngine(context)
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun onStart() {
        super.onStart()
        JustRideCompanionRuntime.show(this)
        JustRideCompanionRuntime.restore(this)
    }
    override fun onStop() {
        JustRideCompanionRuntime.hide(this)
        super.onStop()
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        failCompanion("Device approval interrupted; retry from Device settings")
        stopCallMonitoring()
        JustRideNotificationListener.onNotificationReceived=null
        for (name in listOf("com.justride.app/companion_setup", "com.justride.app/diagnostics",
                CALL_CHANNEL, NOTIFICATION_CHANNEL, MAPS_CONFIG_CHANNEL, SHARE_INTENT_CHANNEL)) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger,name).setMethodCallHandler(null)
        }
        callChannel=null;notifChannel=null;shareMethodChannel=null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun finishCompanion(address: String) {
        val expected=companionAddress ?: return
        if(!address.equals(expected,true)) {failCompanion("Wrong device selected");return}
        try {
            JustRideCompanionRuntime.preferences(this).edit().putString("address",address)
                .putBoolean("enabled",true).putBoolean("paused",false).apply()
            JustRideCompanionRuntime.observe(this,address)
            companionResult?.success(JustRideCompanionRuntime.state(this))
            companionResult=null;companionAddress=null
            JustRideCompanionRuntime.publish(this)
        } catch(e: Exception) {
            JustRideCompanionRuntime.preferences(this).edit().putBoolean("enabled",false).apply()
            failCompanion("Unable to observe device presence: ${e.javaClass.simpleName}")
            JustRideCompanionRuntime.publish(this)
        }
    }
    private fun failCompanion(message: String) {
        companionResult?.error("COMPANION_SETUP",message,null)
        companionResult=null;companionAddress=null
    }
    private fun enableCompanion(address: String,prompt: Boolean,result: MethodChannel.Result) {
        if(Build.VERSION.SDK_INT<31 || !packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)) {
            result.error("UNSUPPORTED","Automatic background connection requires Android 12 or later",null);return
        }
        if(!android.bluetooth.BluetoothAdapter.checkBluetoothAddress(address) || !JustRideCompanionRuntime.permitted(this)) {
            result.error("PERMISSION","Pair the device and grant Nearby devices permission first",null);return
        }
        if(companionResult!=null){result.error("BUSY","Device approval is already open",null);return}
        val prefs=JustRideCompanionRuntime.preferences(this)
        val cdm=JustRideCompanionRuntime.manager(this)
        if(cdm.associations.any {it.equals(address,true)}) {
            companionAddress=address;companionResult=result;finishCompanion(address);return
        }
        if(!prompt && prefs.getString("requested_address",null).equals(address,true)) {
            result.success(JustRideCompanionRuntime.state(this));return
        }
        prefs.edit().putString("requested_address",address).apply()
        companionAddress=address;companionResult=result
        val filter=BluetoothLeDeviceFilter.Builder().setScanFilter(ScanFilter.Builder().setDeviceAddress(address).build()).build()
        val request=AssociationRequest.Builder().addDeviceFilter(filter).setSingleDevice(true).build()
        try {
            cdm.associate(request,object: CompanionDeviceManager.Callback() {
                override fun onDeviceFound(chooserLauncher: IntentSender) {launch(chooserLauncher)}
                override fun onAssociationPending(intentSender: IntentSender) {launch(intentSender)}
                private fun launch(sender: IntentSender) {
                    try {startIntentSenderForResult(sender,companionRequestCode,null,0,0,0)}
                    catch(e: Exception){failCompanion("Unable to open Android device approval")}
                }
                override fun onAssociationCreated(associationInfo: AssociationInfo) {
                    associationInfo.deviceMacAddress?.toString()?.let {finishCompanion(it)}
                }
                override fun onFailure(error: CharSequence?) {failCompanion(error?.toString() ?: "Device approval cancelled")}
            },Handler(Looper.getMainLooper()))
        } catch(e: Exception) {failCompanion("Device approval unavailable: ${e.javaClass.simpleName}")}
    }
    override fun onActivityResult(requestCode: Int,resultCode: Int,data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode!=companionRequestCode || companionResult==null)return
        if(resultCode!=Activity.RESULT_OK){failCompanion("Device approval cancelled");return}
        val address=companionAddress ?: return
        // Both callback styles converge here after Android has persisted association.
        if(JustRideCompanionRuntime.manager(this).associations.any {it.equals(address,true)}) finishCompanion(address)
        else failCompanion("Android did not associate the selected device")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingShareIntent(intent)
        JustRidePushBridge.handleIntent(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingShareIntent(intent)
        JustRidePushBridge.handleIntent(this, intent)
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
        JustRideMediaBridge(applicationContext).attach(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"com.justride.app/companion_setup")
            .setMethodCallHandler { call,result ->
                if(call.method=="enable") {
                    try {enableCompanion(call.argument<String>("address") ?: "",call.argument<Boolean>("prompt") ?: false,result)}
                    catch(e: Exception){result.error("COMPANION_SETUP",e.message,null)}
                } else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.justride.app/diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceInfo") {
                    result.success(mapOf(
                        "phone_model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                        "os_version" to Build.VERSION.RELEASE
                    ))
                } else if (call.method == "appInfo") {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val build = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success(mapOf("version" to info.versionName, "build" to build))
                } else if (call.method == "openApkDownload") {
                    val uri = android.net.Uri.parse(call.argument<String>("url") ?: "")
                    if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) {
                        result.error("INVALID_URL", "The update download link is invalid", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(true)
                        } catch (_: android.content.ActivityNotFoundException) {
                            result.error("NO_BROWSER", "No browser is available to download the update", null)
                        }
                    }
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
                    "getCallCapabilities" -> result.success(callCapabilities())
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
                    "package" to pkg,
                    "appName" to notificationAppName(pkg)
                ))
            }
        }
        JustRideNotificationListener.latestNotification?.let { payload ->
            runOnUiThread {
                notifChannel?.invokeMethod("onLatestNotification", mapOf(
                    "title" to payload.title,
                    "message" to payload.message,
                    "package" to payload.packageName,
                    "appName" to notificationAppName(payload.packageName)
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

    private fun notificationAppName(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { "Alert" }

    private fun callCapabilities(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ANSWER_PHONE_CALLS) != PackageManager.PERMISSION_GRANTED) return 0
        val telecom = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return 0
        val canReject = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P || telecom.defaultDialerPackage == packageName)
        return 1 or (if (canReject) 2 else 0)
    }
    private fun answerIncomingCall(): Boolean {
        if ((callCapabilities() and 1) == 0) return false
        return try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return false
            @Suppress("DEPRECATION")
            telecom.acceptRingingCall()
            true
        } catch (_: Exception) { false }
    }
    private fun rejectIncomingCall(): Boolean {
        if ((callCapabilities() and 2) == 0) return false
        return try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return false
            @Suppress("DEPRECATION")
            telecom.endCall()
        } catch (_: Exception) { false }
    }

}
