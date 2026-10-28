import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/services/bluetooth_service.dart';
import '../../features/device/screens/device_pairing_screen.dart';

/// Every signed-in page requires a verified, usable BLE connection.
class DeviceConnectionGate extends StatelessWidget {
  const DeviceConnectionGate({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<BluetoothConnectionState>(
        valueListenable: JustRideBleService.instance.connectionStateNotifier,
        builder: (context, state, _) {
          if (state == BluetoothConnectionState.connected) {
            return builder(context);
          }
          return const PopScope(
            canPop: false,
            child: DevicePairingScreen(showBottomNav: false),
          );
        },
      );
}

/// The same guard for pages opened with arguments instead of named routes.
class DevicePageRoute<T> extends MaterialPageRoute<T> {
  DevicePageRoute({required WidgetBuilder builder})
      : super(builder: (context) => DeviceConnectionGate(builder: builder));
}
