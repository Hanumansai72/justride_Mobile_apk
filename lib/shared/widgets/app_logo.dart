import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// The shared company artwork is used on every screen, without a substitute icon.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.iconSize = 16,
    this.fontSize = 20,
    this.showTagline = false,
    this.isCentered = false,
    this.isStacked = false,
    this.tagline = 'Made for Bikers',
  });

  final double iconSize;
  final double fontSize;
  final bool showTagline;
  final bool isCentered;
  final bool isStacked;
  final String tagline;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/justride-logo-horizontal.png',
            width: fontSize * 8,
            height: fontSize * 2,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            semanticLabel: 'JustRide',
          ),
          if (showTagline) ...[
            const SizedBox(height: 4),
            Text(tagline,
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
          ],
        ],
      );
}
