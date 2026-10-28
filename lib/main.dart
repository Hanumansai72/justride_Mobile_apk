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
  await ApiClient.instance.init();
  PushNotificationService.instance.init();
  JustRideBleService.instance.init();
  BleNavigationService.instance.init();
  DeviceMapService.instance.init();
  await JustRideBleService.instance.initializeCompanion(
      onShowApp: _showApp,
      authenticated: () => ApiClient.instance.isAuthenticated);
  if (!background) await _showApp();
}

Future<void> _showApp() async {
  if (_showingApp) return;
  _showingApp = true;
  // A companion wake has no Activity channel; load the phone key on UI attach.
  await GoogleMapsConfig.loadPlatformApiKey();
  if (!kIsWeb) {
    ShareService.instance.init();
    TelephonyService.instance.init();
    NotificationListenerService.instance.init();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const JustRideApp());
}
