import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ble_navigation_service.dart';
import 'navigation_service.dart';
import 'telephony_service.dart';

enum RideNotificationMode { callsOnly, selectedApps, off }

/// Information model representing strictly the latest notification received.
class LatestNotificationInfo {
  final String title;
  final String message;
  final String packageName;
  final DateTime receivedAt;

  const LatestNotificationInfo({
    this.title = '',
    this.message = '',
    this.packageName = '',
    required this.receivedAt,
  });

  bool get hasContent => title.isNotEmpty || message.isNotEmpty;
}

/// Service managing native Android system notification access and dispatching
/// strictly the latest notification to the ESP32 motorcycle HUD display over BLE.
class NotificationListenerService {
  NotificationListenerService._();
  static final NotificationListenerService instance =
      NotificationListenerService._();

  static const MethodChannel _channel =
      MethodChannel('com.justride.app/system_notifications');

  final ValueNotifier<LatestNotificationInfo?> latestNotificationNotifier =
      ValueNotifier<LatestNotificationInfo?>(null);

  bool _isInitialized = false;
  final displayEnabled = ValueNotifier<bool>(false);
  final rideMode = ValueNotifier(RideNotificationMode.callsOnly);
  final allowedPackages = ValueNotifier<Set<String>>(const {});
  Future<Map<String, String>> installedApps() async =>
      await _channel.invokeMapMethod<String, String>(
          'getInstalledNotificationApps') ??
      const {};
  late final Future<void> _settingsReady = _loadSettings();
  Future<void> get settingsReady => _settingsReady;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    displayEnabled.value = prefs.getBool('hud_notifications_enabled') ?? false;
    final savedMode = prefs.getString('hud_ride_notification_mode');
    rideMode.value = RideNotificationMode.values.firstWhere(
      (mode) => mode.name == savedMode,
      orElse: () => RideNotificationMode.callsOnly,
    );
    allowedPackages.value = Set.unmodifiable(
        prefs.getStringList('hud_ride_allowed_packages') ?? const <String>[]);
  }

  Future<void> setRideMode(RideNotificationMode mode) async {
    await _settingsReady;
    rideMode.value = mode;
    await (await SharedPreferences.getInstance())
        .setString('hud_ride_notification_mode', mode.name);
    if (NavigationService.instance.isNavigating &&
        TelephonyService.instance.callInfoNotifier.value.hasActiveCall) {
      await TelephonyService.instance.syncDisplay();
    }
  }

  Future<void> setAllowedPackages(Set<String> packages) async {
    await _settingsReady;
    allowedPackages.value = Set.unmodifiable(packages);
    await (await SharedPreferences.getInstance())
        .setStringList('hud_ride_allowed_packages', packages.toList());
  }

  bool get allowCallOverlay =>
      !NavigationService.instance.isNavigating ||
      rideMode.value != RideNotificationMode.off;

  bool allowsAppNotification(String? packageName) {
    final nav = NavigationService.instance;
    if (!nav.isNavigating) return true;
    final state = nav.currentState;
    return displayEnabled.value &&
        rideMode.value == RideNotificationMode.selectedApps &&
        allowedPackages.value.contains(packageName) &&
        state.gpsAvailable &&
        !state.rerouting &&
        state.maneuverDistanceMeters > 120 &&
        state.maneuverState != 'TURN_ACTIVE' &&
        state.maneuverState != 'TURN_PREVIEW';
  }

  Future<void> setDisplayEnabled(bool value) async {
    await _settingsReady;
    await (await SharedPreferences.getInstance())
        .setBool('hud_notifications_enabled', value);
    displayEnabled.value = value;
    if (value && !await isAccessGranted()) await openNotificationSettings();
  }

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    unawaited(_settingsReady);
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  /// Checks if notification access is granted in Android system settings
  Future<bool> isAccessGranted() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      return granted ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Prompts user to open Android Settings → Notification Access
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {}
  }

  /// Sends custom/in-app notification directly to the ESP32 HUD display (strictly latest only)
  Future<bool> sendToDisplay(
      {required String title, required String message}) async {
    final info = LatestNotificationInfo(
      title: title,
      message: message,
      packageName: 'com.justride.app',
      receivedAt: DateTime.now(),
    );
    latestNotificationNotifier.value = info;
    return await BleNavigationService.instance
        .sendLatestNotification(title, message, appName: "JustRide");
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onLatestNotification') {
      await _settingsReady;
      if (!displayEnabled.value) return;
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args != null) {
        final title = args['title']?.toString() ?? '';
        final message = args['message']?.toString() ?? '';
        final pkg = args['package']?.toString() ?? '';
        final appName = args['appName']?.toString() ?? '';
        if (!allowsAppNotification(pkg)) return;

        final info = LatestNotificationInfo(
          title: title,
          message: message,
          packageName: pkg,
          receivedAt: DateTime.now(),
        );

        latestNotificationNotifier.value = info;

        // The BLE service waits for its initial characteristic discovery when a
        // display is connected, so an early notification is not discarded.
        await BleNavigationService.instance.sendLatestNotification(
            title, message,
            appName: appName.isEmpty ? 'Alert' : appName, packageName: pkg);
      }
    }
  }
}
