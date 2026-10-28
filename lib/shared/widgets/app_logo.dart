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
          SizedBox(
            width: fontSize * 8,
            height: fontSize * 2,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: isCentered ? Alignment.center : Alignment.centerLeft,
              // Exclude the source artwork's uneven transparent margins.
              child: SizedBox(
                width: 1187,
                height: 232,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: -76,
                      top: -84,
                      width: 1680,
                      height: 400,
                      child: Image.asset(
                        'assets/justride-logo-horizontal.png',
                        semanticLabel: 'JustRide',
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
