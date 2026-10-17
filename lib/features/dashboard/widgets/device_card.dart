import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/battery_indicator.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/bluetooth_service.dart';

/// Card showing the connected Bluetooth device name, status dot and battery.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    this.device,
    this.deviceName = AppConstants.deviceName,
    this.batteryPercent = AppConstants.batteryPercent,
    this.isConnected = true,
  });

  final DeviceModel? device;
  final String deviceName;
  final int batteryPercent;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final name = device?.deviceName ?? deviceName;
    final battery = device?.batteryLevel ?? batteryPercent;

    return ValueListenableBuilder<BluetoothConnectionState>(
      valueListenable: JustRideBleService.instance.connectionStateNotifier,
      builder: (context, connState, _) {
        final connected = (connState == BluetoothConnectionState.connected ||
                JustRideBleService.instance.isDeviceConnected) &&
            (device == null || (!device!.isBlocked && device!.isActive));

        return InkWell(
          onTap: () => Navigator.of(context).pushNamed('/device'),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingLg,
              vertical: AppConstants.spacingMd,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              children: [
                // Approved circular JustRide device image
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    color: AppColors.surfaceElevated,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/justride-device.webp',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),

                // Device info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTextStyles.headingSmall),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: connected
                                  ? AppColors.connected
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            connected ? 'Connected' : 'Disconnected',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: connected
                                  ? AppColors.connected
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Battery section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Battery', style: AppTextStyles.labelSmall),
                    const SizedBox(height: 3),
                    BatteryIndicator(percent: battery),
                  ],
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
