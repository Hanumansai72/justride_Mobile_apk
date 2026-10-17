import 'package:flutter/material.dart';
import '../../core/services/bluetooth_service.dart';

Future<bool> requireDeviceConnection(BuildContext context) async {
  final ble = JustRideBleService.instance;
  if (ble.isDeviceConnected) return true;

  // A share or route-preview flow can arrive while auto-reconnect is already
  // running. reconnect() waits for that attempt, or starts one if needed.
  final connected = await ble.reconnect();
  if (connected && ble.isDeviceConnected) return true;
  if (!context.mounted) return false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Connect your JustRide device'),
      content: const Text('Connect your device before starting a ride.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).pushNamed('/pair-device');
          },
          child: const Text('Connect device'),
        ),
      ],
    ),
  );
  return false;
}
