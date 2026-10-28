import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// "Trip Insights" promotional banner at the bottom of the Trips screen.
class InsightsBanner extends StatelessWidget {
  const InsightsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Icon with gradient bg
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
              child: const Icon(Icons.bar_chart_rounded,
                  color: AppColors.background, size: 26),
            ),
            const SizedBox(width: AppConstants.spacingMd),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trip Insights', style: AppTextStyles.headingSmall),
                  const SizedBox(height: 3),
                  Text(
                    'Your ride patterns and analytics',
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
