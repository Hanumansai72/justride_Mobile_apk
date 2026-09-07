import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';

class AppLogo extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final bool showTagline;
  final bool isCentered;
  final bool isStacked;

  const AppLogo({
    super.key,
    this.iconSize = 16,
    this.fontSize = 20,
    this.showTagline = false,
    this.isCentered = false,
    this.isStacked = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isStacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          // Glowing logo icon
          _buildIcon(),
          SizedBox(height: iconSize * 0.4),
          // App Name
          Text(
            'JustRide',
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (showTagline) ...[
            const SizedBox(height: 4),
            Text(
              'Made for Bikes',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      );
    }

    // Inline layout (Icon horizontally before text, aligned)
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildIcon(),
        const SizedBox(width: 8),
        Text(
          'JustRide',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildIcon() {
    final boxDimension = iconSize * 1.8;
    return Container(
      width: boxDimension,
      height: boxDimension,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryContainer,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.route_rounded,
          color: AppColors.primary,
          size: iconSize,
        ),
      ),
    );
  }
}

