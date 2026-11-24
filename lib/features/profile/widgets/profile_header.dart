import 'package:flutter/material.dart';
import '../../../app/theme/app_text_styles.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Profile', style: AppTextStyles.headingLarge),
        ),
      );
}
