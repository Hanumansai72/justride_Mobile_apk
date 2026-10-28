import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pagePadding,
        vertical: AppConstants.spacingMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile',
                style: AppTextStyles.displayMedium,
              ),
              Text(
                'Manage your account and preferences',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          Row(
            children: [
              Stack(
                children: [
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/notifications'),
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: AppColors.textPrimary),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
