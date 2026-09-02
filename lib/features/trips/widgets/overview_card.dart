import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// 4-column overview stats card (Total Trips, Distance, Time, CO₂ Saved).
class OverviewCard extends StatelessWidget {
  const OverviewCard({super.key});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERVIEW',
            style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: const [
              const Expanded(
                child: _OverviewStat(
                  icon: Icons.route_rounded,
                  value: '256',
                  label: 'Total Trips',
                ),
              ),
              Expanded(
                child: _OverviewStat(
                  icon: Icons.straighten_rounded,
                  value: '1,842 km',
                  label: 'Total Distance',
                ),
              ),
              Expanded(
                child: _OverviewStat(
                  icon: Icons.timer_outlined,
                  value: '43h 28m',
                  label: 'Total Time',
                ),
              ),
              Expanded(
                child: _OverviewStat(
                  icon: Icons.eco_rounded,
                  value: '28.6 kg',
                  label: 'CO₂ Saved',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.headingSmall.copyWith(fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
