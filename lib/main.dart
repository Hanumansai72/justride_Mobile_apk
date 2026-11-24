import 'core/services/push_notification_service.dart';
import 'core/services/device_map_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'app/app.dart';
import 'app/theme/app_colors.dart';
import 'core/network/api_client.dart';
import 'core/constants/google_maps_config.dart';
import 'core/services/bluetooth_service.dart';
import 'core/services/ble_navigation_service.dart';
import 'core/services/phone_turn_alerts.dart';
import 'core/services/share_service.dart';
import 'core/services/telephony_service.dart';
import 'core/services/notification_listener_service.dart';

bool _showingApp = false;

Future<void> main() => _initializeApp(background: false);

// Android companion presence can start the same engine without an Activity.
@pragma('vm:entry-point')
Future<void> companionMain() => _initializeApp(background: true);

Future<void> _initializeApp({required bool background}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => Material(
        color: AppColors.background,
        child: Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.refresh_rounded,
                      color: AppColors.primary, size: 32),
                  const SizedBox(height: 16),
                  const Text('This screen couldn’t load.',
                      style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () => appNavigatorKey.currentState
                          ?.pushNamedAndRemoveUntil(
                              ApiClient.instance.isAuthenticated
                                  ? '/dashboard'
                                  : '/login',
                              (_) => false),
                      child: const Text('Return home')),
                ]))));
  }
  await ApiClient.instance.init();
  PushNotificationService.instance.init();
  JustRideBleService.instance.init();
  BleNavigationService.instance.init();
  await PhoneTurnAlerts.init();
  DeviceMapService.instance.init();
  await JustRideBleService.instance.initializeCompanion(
      onShowApp: _showApp,
      authenticated: () => ApiClient.instance.isAuthenticated);
  if (!background) await _showApp();
}

Future<void> _showApp() async {
  if (_showingApp) return;
  _showingApp = true;
  try {
    // A companion wake has no Activity channel; load the phone key on UI attach.
    await GoogleMapsConfig.loadPlatformApiKey();
    if (!kIsWeb) {
      ShareService.instance.init();
      TelephonyService.instance.init();
      NotificationListenerService.instance.init();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]).timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
    ));
  } catch (_) {
    // Optional Android integrations must never prevent the first Flutter frame.
  }
  try {
    runApp(const JustRideApp());
  } catch (_) {
    _showingApp = false;
    rethrow;
  }
}
