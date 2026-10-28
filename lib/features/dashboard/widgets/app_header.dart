import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../shared/widgets/app_logo.dart';

/// Top app-bar area containing the JustRide logo and notification bell.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 10);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: const AppLogo(
        iconSize: 18,
        fontSize: 20,
        showTagline: false,
        isCentered: false,
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed('/notifications'),
          icon: const Icon(Icons.notifications_outlined,
              color: AppColors.textPrimary, size: 24),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed('/profile-settings'),
          icon: const Icon(Icons.settings_outlined,
              color: AppColors.textPrimary, size: 24),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
