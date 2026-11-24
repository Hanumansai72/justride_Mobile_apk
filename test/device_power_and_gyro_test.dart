import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:justride_ui/core/models/power_status.dart';
import 'package:justride_ui/core/models/sensor_status.dart';
import 'package:justride_ui/core/services/ble_navigation_service.dart';
import 'package:justride_ui/core/services/bluetooth_service.dart';
import 'package:justride_ui/core/services/ota_service.dart';
import 'package:justride_ui/features/device/widgets/power_status_card.dart';

// Golden packets also asserted by firmware tools/test_waveshare143.py.
const battery = [0x1d, 1, 3, 1, 255, 50, 0xa6, 0x0e, 0xa6, 0x0e];
const usb = [0x1d, 1, 1, 2, 255, 255, 0x5d, 0x12, 0, 0];
const unavailable = [0x1d, 1, 0, 0, 255, 255, 0, 0, 0, 0];

void main() {
  test('OTA refuses ESP32/S3 chip mismatches and missing device identity', () {
    final image = List<int>.filled(24, 0)..[0] = 0xe9;
    expect(JustRideOtaService.imageMatchesChip(image, 0), isTrue);
    expect(JustRideOtaService.imageMatchesChip(image, 9), isFalse);
    image[12] = 9;
    expect(JustRideOtaService.imageMatchesChip(image, 9), isTrue);
    expect(JustRideOtaService.imageMatchesChip(image, 0), isFalse);
    expect(JustRideOtaService.imageMatchesChip(image, null), isFalse);
    expect(JustRideOtaService.imageMatchesChip([], 9), isFalse);
  });
  test(
      'OTA accepts fresh USB or sufficient battery; rejects stale/unknown/low power',
      () {
    final now = DateTime.now();
    expect(
        JustRideOtaService.powerAllowsUpdate(
            PowerStatus.parse(usb, now: now), now),
        isTrue);
    expect(
        JustRideOtaService.powerAllowsUpdate(
            PowerStatus.parse(battery, now: now), now),
        isTrue);
    expect(
        JustRideOtaService.powerAllowsUpdate(
            PowerStatus.parse(unavailable, now: now), now),
        isFalse);
    expect(JustRideOtaService.powerAllowsUpdate(null, now), isFalse);
    expect(
        JustRideOtaService.powerAllowsUpdate(
            PowerStatus.parse(battery, now: now),
            now.add(const Duration(seconds: 16))),
        isFalse);
    expect(
        JustRideOtaService.powerAllowsUpdate(
            PowerStatus(
                source: 1, charging: 255, percentage: 29, receivedAt: now),
            now),
        isFalse);
  });
  test('battery voltage is an estimate; USB does not imply charging/full', () {
    final p = PowerStatus.parse(battery)!;
    expect(p.railMillivolts, 3750);
    expect(p.batteryMillivolts, 3750);
    expect(p.levelLabel, '~50%');
    expect(p.chargingLabel, 'Charging status unavailable');
    final u = PowerStatus.parse(usb)!;
    expect(u.railMillivolts, 4701);
    expect(u.batteryMillivolts, isNull);
    expect(u.percentage, isNull);
    expect(u.levelLabel, '—');
    expect(u.sourceLabel, 'USB power (inferred)');
    expect(u.chargingLabel, 'Charging status unavailable');
    expect(PowerStatus.parse(unavailable)!.railMillivolts, isNull);
  });

  test('reject malformed, unsupported and contradictory power packets', () {
    for (final p in <List<int>>[
      [],
      battery.sublist(1),
      [...battery, 0],
      [...battery]..[1] = 2,
      [...battery]..[2] = 7,
      [...battery]..[5] = 101,
      [...battery]..[3] = 2,
      [...battery]..[6] = -1,
      [...usb]..[8] = 1,
      [...unavailable]..[6] = 1,
    ]) {
      expect(PowerStatus.parse(p), isNull, reason: '$p');
    }
    final now = DateTime(2026, 11, 4);
    final p = PowerStatus.parse(battery, now: now)!;
    expect(p.freshAt(now.add(const Duration(seconds: 14))), isTrue);
    expect(p.freshAt(now.add(const Duration(seconds: 15))), isFalse);
  });

  test('legacy sensor telemetry and signed gyro v2 remain compatible', () {
    final legacy = SensorStatus.parse([0x1a, 1, 3, 0, 0, 0, 0, 0])!;
    expect(legacy.isReady, isTrue);
    expect(legacy.gyroAvailable, isFalse);
    final left = SensorStatus.parse(
        [0x1a, 2, 3, 3, 0, 0, 0, 0, 0x38, 0xff, 0x9c, 0xff, 3])!;
    expect(left.movement, 'Left');
    expect(left.yaw, -20);
    expect(left.turnRate, -10);
    expect(left.gyroFresh, isTrue);
    final right =
        SensorStatus.parse([0x1a, 2, 3, 4, 0, 0, 0, 0, 200, 0, 100, 0, 3])!;
    expect(right.movement, 'Right');
    expect(right.yaw, 20);
    expect(right.turnRate, 10);
    expect(SensorStatus.parse([]), isNull);
    expect(
        SensorStatus.parse([0x1a, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 4]), isNull);
  });

  testWidgets('power card updates live and clears after disconnect',
      (tester) async {
    final ble = BleNavigationService.instance;
    final connection = JustRideBleService.instance.connectionStateNotifier;
    ble.init();
    connection.value = BluetoothConnectionState.connected;
    ble.powerStatus.value = PowerStatus.parse(battery);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: PowerStatusCard())));
    expect(find.text('3.75 V supply'), findsOneWidget);
    expect(find.text('Battery estimate: ~50%'), findsOneWidget);
    ble.powerStatus.value = PowerStatus.parse(usb);
    await tester.pump();
    expect(find.text('4.70 V supply'), findsOneWidget);
    expect(find.text('Battery estimate: ~50%'), findsNothing);
    expect(find.text('Charging status unavailable'), findsOneWidget);
    connection.value = BluetoothConnectionState.disconnected;
    await tester.pump();
    expect(ble.powerStatus.value, isNull);
    expect(find.text('Waiting for device measurement'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
  });
}
