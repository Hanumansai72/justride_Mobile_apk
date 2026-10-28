import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Promotional banner encouraging users to explore charging stations and rentals.
class ExploreBanner extends StatelessWidget {
  const ExploreBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          children: [
            // Animated icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
              child: const Icon(Icons.explore_rounded,
                  color: AppColors.background, size: 28),
            ),
            const SizedBox(width: AppConstants.spacingLg),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Explore JustRide', style: AppTextStyles.headingSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Find charging stations, rentals,\nand more nearby',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right_rounded,
                color: AppColors.primaryDark, size: 22),
          ],
        ),
      ),
    );
  }
}
