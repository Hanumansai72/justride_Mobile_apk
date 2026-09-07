import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ble_navigation_service.dart';

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

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    _channel.setMethodCallHandler(_handleNativeMethodCall);
    debugPrint('[NotificationListenerService] Initialized.');
  }

  /// Checks if notification access is granted in Android system settings
  Future<bool> isAccessGranted() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      return granted ?? false;
    } catch (e) {
      debugPrint('[NotificationListenerService] Error checking access: $e');
      return false;
    }
  }

  /// Prompts user to open Android Settings → Notification Access
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint(
          '[NotificationListenerService] Error opening notification settings: $e');
    }
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
        .sendLatestNotification(title, message);
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onLatestNotification') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args != null) {
        final title = args['title']?.toString() ?? '';
        final message = args['message']?.toString() ?? '';
        final pkg = args['package']?.toString() ?? '';

        final info = LatestNotificationInfo(
          title: title,
          message: message,
          packageName: pkg,
          receivedAt: DateTime.now(),
        );

        latestNotificationNotifier.value = info;
        debugPrint(
            '[NotificationListenerService] Latest notification: "$title" - "$message" ($pkg)');

        // The BLE service waits for its initial characteristic discovery when a
        // display is connected, so an early notification is not discarded.
        await BleNavigationService.instance
            .sendLatestNotification(title, message);
      }
    }
  }
}
