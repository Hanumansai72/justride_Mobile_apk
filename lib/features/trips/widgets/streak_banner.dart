import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Ride streak motivational banner with circular streak counter.
class StreakBanner extends StatelessWidget {
  const StreakBanner({
    super.key,
    this.streakDays = 7,
  });

  final int streakDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingLg,
        vertical: AppConstants.spacingMd,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Streak circle
          _StreakCircle(days: streakDays),
          const SizedBox(width: AppConstants.spacingMd),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Great going! ', style: AppTextStyles.headingSmall),
                    const Text('🔥', style: TextStyle(fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  "You're on a $streakDays-day ride streak.",
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),

          // View Streaks CTA
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View Streaks', style: AppTextStyles.accentMedium.copyWith(fontSize: 11)),
                  const SizedBox(width: 3),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCircle extends StatelessWidget {
  const _StreakCircle({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 2),
        gradient: const RadialGradient(
          colors: [AppColors.primaryContainer, AppColors.surface],
          radius: 0.8,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$days',
            style: AppTextStyles.headingSmall.copyWith(
              color: AppColors.primary,
              fontSize: 18,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
