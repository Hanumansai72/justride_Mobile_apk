import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/sensor_status.dart';
import '../../../core/services/ble_navigation_service.dart';

class SensorStatusCard extends StatefulWidget {
  const SensorStatusCard({super.key});
  @override
  State<SensorStatusCard> createState() => _SensorStatusCardState();
}

class _SensorStatusCardState extends State<SensorStatusCard> {
  Timer? _freshness;
  @override
  void initState() {
    super.initState();
    _freshness = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(BleNavigationService.instance.requestSensorStatus());
  }

  @override
  void dispose() {
    _freshness?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = BleNavigationService.instance;
    return ValueListenableBuilder<bool>(
        valueListenable: ble.sensorSupported,
        builder: (context, supported, _) =>
            ValueListenableBuilder<SensorStatus?>(
                valueListenable: ble.sensorStatus,
                builder: (context, status, _) {
                  final fresh = status != null &&
                      DateTime.now().difference(status.receivedAt) <
                          const Duration(seconds: 3);
                  final ready = fresh && status.isReady;
                  final text = !supported
                      ? 'Connect a compatible JustRide device'
                      : !fresh
                          ? 'Waiting for sensor data'
                          : status.label;
                  return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.screen_rotation_alt,
                                  color: AppColors.primary),
                              SizedBox(width: 10),
                              Expanded(
                                  child: Text('Motion / Calibrate',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 17)))
                            ]),
                            const SizedBox(height: 12),
                            Text(text,
                                style: const TextStyle(
                                    color: AppColors.primary)),
                            const SizedBox(height: 8),
                            Text(ready
                                ? 'Roll ${status.roll.toStringAsFixed(1)}°   Pitch ${status.pitch.toStringAsFixed(1)}°'
                                : 'Roll —   Pitch —'),
                            if (ready) Text(status.movement),
                            const SizedBox(height: 8),
                            const Text(
                                'Calibrates automatically when a ride starts. Keep the device still briefly.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            OutlinedButton(
                                onPressed: supported &&
                                        fresh &&
                                        status.state != 0 &&
                                        status.state != 2 &&
                                        status.state != 5
                                    ? () async {
                                        final sent =
                                            await ble.requestSensorStatus(
                                                calibrate: true);
                                        if (!context.mounted || sent) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Calibration request failed. Reconnect the device and retry.')));
                                      }
                                    : null,
                                child: const Text('Calibrate again')),
                          ]));
                }));
  }
}
