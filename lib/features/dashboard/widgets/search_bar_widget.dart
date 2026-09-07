import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Search bar row with mic icon, used in the "Where to?" section.
class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({
    super.key,
    required this.onTap,
    this.onMicTap,
  });

  final VoidCallback onTap;
  final VoidCallback? onMicTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingLg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded,
                color: AppColors.textMuted, size: 22),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Text(
                'Enter Start & Destination',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
            GestureDetector(
              onTap: onMicTap ?? onTap,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: const Icon(Icons.mic_rounded,
                    color: AppColors.primary, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
