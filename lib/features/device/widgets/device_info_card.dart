import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/bluetooth_service.dart';

/// Original product image and live device status with connection controls.
class DeviceInfoCard extends StatelessWidget {
  final bool hasUpdate;
  final String firmwareVersion;
  final String newVersion;
  final String deviceName;
  final int batteryPercent;

  const DeviceInfoCard({
    super.key,
    this.hasUpdate = true,
    this.firmwareVersion = 'v2.1.0',
    this.newVersion = 'v2.2.0',
    this.deviceName = 'JustRide Pro HUD',
    this.batteryPercent = 98,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BluetoothConnectionState>(
      valueListenable: JustRideBleService.instance.connectionStateNotifier,
      builder: (context, connState, _) {
        final isConnected = connState == BluetoothConnectionState.connected ||
            JustRideBleService.instance.isDeviceConnected;

        return Container(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: isConnected
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DeviceProductImage(),
              const SizedBox(height: AppConstants.spacingLg),

              // Right: Device details
              SizedBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and navigation to settings
                    InkWell(
                      onTap: () =>
                          Navigator.of(context).pushNamed('/device-settings'),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isConnected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              deviceName,
                              style: AppTextStyles.headingMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textSecondary, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Connection Status & Disconnect/Reconnect Button
                    Row(
                      children: [
                        Icon(
                          isConnected
                              ? Icons.bluetooth_connected_rounded
                              : Icons.bluetooth_disabled_rounded,
                          color: isConnected
                              ? AppColors.primary
                              : AppColors.textMuted,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            isConnected ? 'Connected' : 'Disconnected',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: isConnected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Dedicated Disconnect / Reconnect Button (not unpairing)
                        GestureDetector(
                          onTap: () async {
                            if (isConnected) {
                              await JustRideBleService.instance
                                  .disconnectDevice();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Device disconnected (remains paired).'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: AppColors.surfaceElevated,
                                  ),
                                );
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Searching for your JustRide device…'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: AppColors.primaryContainer,
                                  ),
                                );
                              }
                              // Load the exact MAC address saved during pairing
                              final bleAddress = await JustRideBleService
                                  .instance
                                  .loadSavedBleAddress();
                              final ok = await JustRideBleService.instance
                                  .reconnect(targetBleAddress: bleAddress);
                              if (context.mounted) {
                                final err = JustRideBleService
                                    .instance.lastBleErrorNotifier.value;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Reconnected & synced to JustRide!'
                                        : (err ??
                                            (bleAddress != null
                                                ? 'Could not find device ($bleAddress). Ensure it is nearby.'
                                                : 'No paired device found. Please pair first.'))),
                                    duration: const Duration(seconds: 3),
                                    backgroundColor: ok
                                        ? AppColors.primary
                                        : AppColors.errorText,
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? AppColors.surfaceElevated
                                  : AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isConnected
                                    ? AppColors.border
                                    : AppColors.primary,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              isConnected ? 'Disconnect' : 'Connect',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isConnected
                                    ? AppColors.textSecondary
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Battery
                    _InfoRow(
                      icon: isConnected
                          ? Icons.battery_charging_full_rounded
                          : Icons.battery_std_rounded,
                      title: 'Battery',
                      value: isConnected ? '$batteryPercent%' : '--',
                      subtitle: isConnected ? 'Active' : 'Offline',
                      valueColor:
                          isConnected ? AppColors.primary : AppColors.textMuted,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppColors.border, height: 1),
                    ),

                    // Connection Signal
                    _InfoRow(
                      icon: Icons.bluetooth_rounded,
                      title: 'Connection',
                      value: isConnected ? 'Strong' : 'Disconnected',
                      subtitle:
                          isConnected ? 'BLE 5.2' : 'Auto-reconnecting...',
                      valueColor:
                          isConnected ? AppColors.primary : AppColors.textMuted,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppColors.border, height: 1),
                    ),

                    // Firmware / Update status
                    InkWell(
                      onTap: () =>
                          Navigator.of(context).pushNamed('/device-settings'),
                      child: _InfoRow(
                        icon: hasUpdate
                            ? Icons.system_update_rounded
                            : Icons.memory_rounded,
                        title: 'Firmware',
                        value: hasUpdate
                            ? '$firmwareVersion → $newVersion'
                            : firmwareVersion,
                        subtitle:
                            hasUpdate ? '⚡ Update Available' : 'Up to date',
                        valueColor: hasUpdate
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        isHighlight: hasUpdate,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
    this.isHighlight = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            color: isHighlight ? AppColors.primary : AppColors.primary,
            size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.labelSmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  color:
                      isHighlight ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isHighlight ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            color: AppColors.textSecondary, size: 20),
      ],
    );
  }
}

/// Original product asset; contain preserves the bezel and navigation display.
class _DeviceProductImage extends StatelessWidget {
  const _DeviceProductImage();

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Image.asset(
            'assets/justride-device.webp',
            fit: BoxFit.contain,
            semanticLabel:
                'JustRide circular navigation device with silver bezel and green route',
          ),
        ),
      );
}
