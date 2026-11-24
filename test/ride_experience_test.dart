import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:justride_ui/core/models/navigation_state.dart';
import 'package:justride_ui/core/models/ride_state.dart';
import 'package:justride_ui/core/services/navigation_service.dart';
import 'package:justride_ui/core/services/phone_turn_alerts.dart';
import 'package:justride_ui/core/services/location_service.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';

Position fix(DateTime timestamp, {double accuracy = 5}) => Position(
    longitude: 77,
    latitude: 12,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('old or inaccurate GPS cannot be refreshed merely by a BLE heartbeat',
      () {
    final now = DateTime(2026, 11, 4, 14);
    expect(LocationService.navigationFixFresh(null, now), isFalse);
    expect(LocationService.navigationFixFresh(fix(now), now), isTrue);
    expect(
        LocationService.navigationFixFresh(
            fix(now.subtract(const Duration(seconds: 10))), now),
        isTrue);
    expect(
        LocationService.navigationFixFresh(
            fix(now.subtract(const Duration(seconds: 11))), now),
        isFalse);
    expect(LocationService.navigationFixFresh(fix(now, accuracy: 51), now),
        isFalse);
    expect(
        LocationService.navigationFixFresh(fix(now, accuracy: double.nan), now),
        isFalse);
  });
  const approaching = NavigationState(
      rideState: RideState.navigating,
      maneuver: 'LEFT',
      maneuverState: 'TURN_PREVIEW',
      maneuverId: 7,
      maneuverDistanceMeters: 80,
      remainingDistanceMeters: 12800,
      remainingDurationSeconds: 900);

  test('phone turn alerts require live nearby left/right guidance', () {
    expect(PhoneTurnAlerts.eligible(approaching), isTrue);
    for (final state in [
      approaching.copyWith(maneuverDistanceMeters: 101),
      approaching.copyWith(maneuverDistanceMeters: -1),
      approaching.copyWith(maneuverDistanceMeters: double.nan),
      approaching.copyWith(maneuver: 'STRAIGHT'),
      approaching.copyWith(gpsAvailable: false),
      approaching.copyWith(rerouting: true),
      approaching.copyWith(rideState: RideState.paused),
      approaching.copyWith(rideState: RideState.arrived),
      approaching.copyWith(maneuverState: 'TURN_COMPLETED'),
    ]) {
      expect(PhoneTurnAlerts.eligible(state), isFalse);
    }
    expect(PhoneTurnAlerts.eligible(approaching.copyWith(maneuver: 'RIGHT')),
        isTrue);
  });
  test('pause flag survives normal updates and sync packets', () {
    final paused = approaching.copyWith(rideState: RideState.paused);
    for (final opcode in [BleNavOpCode.navUpdate, BleNavOpCode.syncState]) {
      final bytes =
          BleNavigationPacket.fromState(paused, opCode: opcode).toBinary();
      expect(bytes[16] & 16, 16);
    }
    expect(BleNavigationPacket.fromState(approaching).toBinary()[16] & 16, 0);
  });

  test('native haptics fire once per maneuver and obey the saved opt-in',
      () async {
    SharedPreferences.setMockInitialValues({'phone_turn_vibration': true});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    });
    await PhoneTurnAlerts.init();
    LocationService.instance.positionNotifier.value = fix(DateTime.now());
    final updates = NavigationService.instance.navigationStateNotifier;
    updates.value = approaching;
    updates.value = approaching.copyWith(maneuverDistanceMeters: 70);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);
    expect(calls.single.arguments, 'HapticFeedbackType.heavyImpact');
    updates.value = approaching.copyWith(maneuverId: 8, gpsAvailable: false);
    expect(calls.length, 1);
    updates.value = approaching.copyWith(maneuverId: 8, maneuver: 'RIGHT');
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 2);
    LocationService.instance.positionNotifier.value =
        fix(DateTime.now().subtract(const Duration(seconds: 20)));
    updates.value = approaching.copyWith(maneuverId: 10);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 2);
    LocationService.instance.positionNotifier.value = fix(DateTime.now());
    await PhoneTurnAlerts.setEnabled(false);
    updates.value = approaching.copyWith(maneuverId: 9);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 2);
    expect(
        (await SharedPreferences.getInstance()).getBool('phone_turn_vibration'),
        isFalse);
    updates.value = NavigationState.idle();
    LocationService.instance.positionNotifier.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  test('home distance uses real totals; invalid input remains unknown', () {
    expect(encodeHomeDistance(12800), [0x21, 1, 0, 50, 0, 0]);
    expect(encodeHomeDistance(0), [0x21, 1, 0, 0, 0, 0]);
    expect(encodeHomeDistance(double.nan), [0x21, 0, 0, 0, 0, 0]);
    expect(encodeHomeDistance(-1), [0x21, 0, 0, 0, 0, 0]);
  });
}
