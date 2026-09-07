import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/constants/google_maps_config.dart';
import 'core/services/bluetooth_service.dart';
import 'core/services/ble_navigation_service.dart';
import 'core/services/share_service.dart';
import 'core/services/telephony_service.dart';
import 'core/services/notification_listener_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GoogleMapsConfig.loadPlatformApiKey();
  await ApiClient.instance.init();

  // Initialize Bluetooth, Navigation, Telephony, and Notification Services
  JustRideBleService.instance.init();
  BleNavigationService.instance.init();
  ShareService.instance.init();
  TelephonyService.instance.init();
  NotificationListenerService.instance.init();

  // Lock orientation to portrait for the mobile-first design.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar so our background bleeds through.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const JustRideApp());
}
