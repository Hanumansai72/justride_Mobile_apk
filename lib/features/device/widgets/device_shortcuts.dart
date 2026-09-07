import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

import '../../navigation/widgets/voice_assistant_sheet.dart';

class DeviceShortcuts extends StatelessWidget {
  const DeviceShortcuts({super.key});

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Device Shortcuts', style: AppTextStyles.headingSmall),
              GestureDetector(
                onTap: () {},
                child: Text('Edit', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _ShortcutItem(
                  icon: Icons.mic_rounded,
                  title: 'Voice Assistant',
                  subtitle: 'Speak Place',
                  isHighlighted: true,
                  onTap: () => VoiceAssistantSheet.show(context),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                const _ShortcutItem(icon: Icons.light_mode_outlined, title: 'Brightness', subtitle: '80%'),
                const SizedBox(width: AppConstants.spacingMd),
                const _ShortcutItem(icon: Icons.volume_up_outlined, title: 'Volume', subtitle: 'Medium'),
                const SizedBox(width: AppConstants.spacingMd),
                const _ShortcutItem(icon: Icons.screenshot_monitor_rounded, title: 'Auto Screen', subtitle: '30 sec'),
                const SizedBox(width: AppConstants.spacingMd),
                const _ShortcutItem(icon: Icons.translate_rounded, title: 'Language', subtitle: 'English'),
                const SizedBox(width: AppConstants.spacingMd),
                const _ShortcutItem(icon: Icons.info_outline_rounded, title: 'About', subtitle: 'Device'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutItem extends StatelessWidget {
  const _ShortcutItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMd, horizontal: 4),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: isHighlighted
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border,
            width: isHighlighted ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: AppTextStyles.labelMedium.copyWith(
                fontSize: 10,
                color: isHighlighted ? AppColors.primary : null,
                fontWeight: isHighlighted ? FontWeight.bold : null,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTextStyles.labelSmall.copyWith(fontSize: 9),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
