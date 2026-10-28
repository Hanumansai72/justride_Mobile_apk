import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/bluetooth_service.dart';

/// Two side-by-side stat cards: Device Battery and live Device Status.
class StatsRow extends StatelessWidget {
  final DeviceModel? device;

  const StatsRow({super.key, this.device});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BatteryStatCard(batteryLevel: device?.batteryLevel)),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(child: _DeviceStatusCard(device: device)),
        ],
      ),
    );
  }
}

// ── Shared card shell ─────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: child,
    );
  }
}

// ── Battery stat ──────────────────────────────────────────────────────────────

class _BatteryStatCard extends StatelessWidget {
  final int? batteryLevel;

  const _BatteryStatCard({this.batteryLevel});

  @override
  Widget build(BuildContext context) {
    final percent = batteryLevel ?? AppConstants.batteryPercent;
    return _StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('DEVICE BATTERY', style: AppTextStyles.labelSmall),
              const Spacer(),
              const Icon(Icons.battery_charging_full_rounded,
                  size: 14, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$percent%',
            style: AppTextStyles.displayMedium.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 4),
          Text('${(percent * 0.1).toStringAsFixed(1)}h remaining',
              style: AppTextStyles.labelSmall),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusCircle),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live Device status ────────────────────────────────────────────────────────

class _DeviceStatusCard extends StatelessWidget {
  final DeviceModel? device;

  const _DeviceStatusCard({this.device});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BluetoothConnectionState>(
      valueListenable: JustRideBleService.instance.connectionStateNotifier,
      builder: (context, connState, _) {
        final isConnected = connState == BluetoothConnectionState.connected ||
            JustRideBleService.instance.isDeviceConnected;
        final fw = device?.firmwareVersion ?? AppConstants.firmwareVersion;

        return _StatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('DEVICE STATUS', style: AppTextStyles.labelSmall),
                  const Spacer(),
                  Icon(
                    isConnected
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    size: 14,
                    color:
                        isConnected ? AppColors.primary : AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Connected badge
              Row(
                children: [
                  Icon(
                    isConnected
                        ? Icons.check_circle_rounded
                        : Icons.cancel_outlined,
                    size: 14,
                    color:
                        isConnected ? AppColors.connected : AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isConnected ? 'Connected' : 'Disconnected',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isConnected
                          ? AppColors.connected
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _StatusRow(
                label: 'Signal',
                child: _SignalBars(strength: isConnected ? 3 : 0),
              ),
              const SizedBox(height: 3),
              _StatusRow(
                label: 'Firmware',
                child: Text(fw, style: AppTextStyles.labelSmall),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.labelSmall),
        child,
      ],
    );
  }
}

/// Minimal signal bars icon.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.strength});
  final int strength; // 0–4

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < strength;
        return Container(
          width: 3,
          height: 4.0 + i * 3,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
