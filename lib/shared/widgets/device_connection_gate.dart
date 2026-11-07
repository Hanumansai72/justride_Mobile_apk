import 'package:flutter/material.dart';
import '../../core/services/backend_service.dart';
import '../../features/device/screens/device_pairing_screen.dart';

/// Require an account link, not a continuous Bluetooth connection.
class DeviceConnectionGate extends StatefulWidget {
  const DeviceConnectionGate({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<DeviceConnectionGate> createState() => _DeviceConnectionGateState();
}

class _DeviceConnectionGateState extends State<DeviceConnectionGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    BackendService.instance.getMyDevice().whenComplete(() {
      if (mounted) setState(() => _checking = false);
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
        valueListenable: BackendService.instance.accountPaired,
        builder: (context, paired, _) {
          if (paired == false) {
            return const PopScope(
              canPop: false,
              child: DevicePairingScreen(showBottomNav: false),
            );
          }
          if (paired == null && _checking) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return widget.builder(context);
        },
      );
}

/// The same guard for pages opened with arguments instead of named routes.
class DevicePageRoute<T> extends MaterialPageRoute<T> {
  DevicePageRoute({required WidgetBuilder builder})
      : super(builder: (context) => DeviceConnectionGate(builder: builder));
}
