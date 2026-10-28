import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

class DeviceHealthCard extends StatelessWidget {
  const DeviceHealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined,
                  color: AppColors.primary, size: 24),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Device Health', style: AppTextStyles.headingSmall),
                    const SizedBox(height: 2),
                    Text('All systems are working well',
                        style: AppTextStyles.labelSmall),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_up_rounded,
                  color: AppColors.textSecondary, size: 24),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _HealthItem(icon: Icons.monitor_outlined, label: 'Display'),
              _HealthItem(icon: Icons.battery_full_rounded, label: 'Battery'),
              _HealthItem(
                  icon: Icons.radio_button_checked_rounded, label: 'Buttons'),
              _HealthItem(icon: Icons.sensors_rounded, label: 'Sensors'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthItem extends StatelessWidget {
  const _HealthItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 8),
        Text(label, style: AppTextStyles.labelMedium),
        const SizedBox(height: 2),
        Text('Good',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.primary)),
      ],
    );
  }
}
