import 'app_update_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../app/app.dart';
import '../network/api_client.dart';
import 'bluetooth_service.dart';

/// Android receives and displays pushes natively, even without a Flutter screen.
class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();
  static final instance = PushNotificationService._();
  static const _channel = MethodChannel('com.justride.app/push');
  bool _syncing = false;
  String? _pendingType;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void init() {
    if (!_supported) return;
    WidgetsBinding.instance.addObserver(this);
    JustRideBleService.instance.connectionStateNotifier
        .addListener(_openPending);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'registrationChanged') unawaited(syncRegistration());
      if (call.method == 'notificationTapped') await _consumeTap();
    });
    if (ApiClient.instance.isAuthenticated) {
      unawaited(syncRegistration());
    } else {
      unawaited(disable());
    }
    unawaited(_consumeTap());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPending());
  }

  Future<void> syncRegistration() async {
    final api = ApiClient.instance;
    if (!_supported || _syncing || !api.isAuthenticated) return;
    _syncing = true;
    final session = api.token;
    try {
      final registration =
          await _channel.invokeMapMethod<String, dynamic>('register');
      if (registration?['configured'] == true && api.token == session) {
        await api.put('/notifications/push-registration', body: {
          'fid': registration!['fid'],
          'enabled': registration['enabled'] == true,
        });
      }
    } catch (_) {
      debugPrint('[Push] Registration unavailable; will retry on resume.');
    } finally {
      _syncing = false;
    }
  }

  Future<String?> disable() async {
    _pendingType = null;
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('disable');
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncRegistration());
      unawaited(_consumeTap());
      _openPending();
    }
  }

  Future<void> _consumeTap() async {
    try {
      final type = await _channel.invokeMethod<String>('consumeNotification');
      if (type == 'APP_UPDATE' || type == 'FIRMWARE_UPDATE') {
        _pendingType = type;
      }
      _openPending();
    } catch (_) {/* Native bridge is unavailable on other platforms. */}
  }

  void _openPending() {
    if (_pendingType == null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
      return;
    if (_pendingType == 'FIRMWARE_UPDATE' &&
        (!ApiClient.instance.isAuthenticated ||
            JustRideBleService.instance.connectionStateNotifier.value !=
                BluetoothConnectionState.connected)) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    final route =
        _pendingType == 'FIRMWARE_UPDATE' ? '/device-settings' : '/app-update';
    if (_pendingType == 'APP_UPDATE')
      unawaited(AppUpdateService.instance.check());
    _pendingType = null;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => navigator.pushNamed(route));
    WidgetsBinding.instance.scheduleFrame();
  }
}
