import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/power_status.dart';
import '../../../core/services/ble_navigation_service.dart';

class PowerStatusCard extends StatelessWidget {
  const PowerStatusCard({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PowerStatus?>(
        valueListenable: BleNavigationService.instance.powerStatus,
        builder: (context, power, child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.battery_std, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Device power',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))
            ]),
            const SizedBox(height: 12),
            Text(power?.voltageLabel ?? 'Waiting for device measurement'),
            if (power != null) ...[
              Text(power.sourceLabel),
              if (power.source == 1 &&
                  power.percentage != null &&
                  power.percentage! <= 15)
                const Text('Low battery — charge soon',
                    style: TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w700)),
              if (power.percentage != null)
                Text('Battery estimate: ${power.levelLabel}'),
              Text(power.chargingLabel),
            ],
            const SizedBox(height: 8),
            const Text(
                'Voltage is measured at the supply rail. Battery estimates are available on battery power; charging status needs a hardware status signal.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
      );
}
