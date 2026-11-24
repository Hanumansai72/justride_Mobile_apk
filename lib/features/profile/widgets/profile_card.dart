import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/app_models.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, this.user, this.onEdit});
  final UserModel? user;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final name = user?.fullName.trim();
    final title = name?.isNotEmpty == true ? name! : 'Your account';
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.primary,
              child: Text(title.characters.first.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w500))),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: AppTextStyles.headingMedium),
                if (user?.email.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(user!.email, style: AppTextStyles.bodyMedium)
                ],
                if (user?.phone?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(user!.phone!, style: AppTextStyles.bodySmall)
                ],
              ])),
          if (onEdit != null)
            IconButton(
                tooltip: 'Edit profile',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20)),
        ]));
  }
}
