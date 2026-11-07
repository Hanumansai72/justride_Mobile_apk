import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/battery_indicator.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/ble_navigation_service.dart';

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

    return ListenableBuilder(
      listenable: Listenable.merge([
        JustRideBleService.instance.connectionStateNotifier,
        BleNavigationService.instance.powerStatus
      ]),
      builder: (context, _) {
        final connState =
            JustRideBleService.instance.connectionStateNotifier.value;
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
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    color: AppColors.transparent,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/justride-device.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),

                // Device info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: AppTextStyles.headingMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
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
                          Flexible(
                            child: Text(
                              connected ? 'Connected' : 'Disconnected',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: connected
                                    ? AppColors.connected
                                    : AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
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
                    BatteryIndicator(
                        percent: connected
                            ? BleNavigationService
                                .instance.powerStatus.value?.percentage
                            : null),
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
