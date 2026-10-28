import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

/// Re-usable animated battery indicator widget.
///
/// Displays a compact rectangular battery icon with a percentage label and
/// an optional colour that transitions from [AppColors.primary] (high) to
/// [AppColors.warning] (mid) to [AppColors.errorText] (low).
class BatteryIndicator extends StatelessWidget {
  const BatteryIndicator({
    super.key,
    required this.percent,
    this.showLabel = true,
    this.width = 38,
    this.height = 18,
  });

  final int percent;
  final bool showLabel;
  final double width;
  final double height;

  Color get _barColor {
    if (percent >= 50) return AppColors.primary;
    if (percent >= 25) return AppColors.warning;
    return AppColors.errorText;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BatteryIcon(
          percent: percent,
          barColor: _barColor,
          width: width,
          height: height,
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text('$percent%', style: AppTextStyles.labelLarge),
        ],
      ],
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  const _BatteryIcon({
    required this.percent,
    required this.barColor,
    required this.width,
    required this.height,
  });

  final int percent;
  final Color barColor;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    const double terminalWidth = 3.0;
    const double borderWidth = 1.5;
    const double innerPad = 2.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Battery body
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textSecondary, width: borderWidth),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm / 2),
          ),
          padding: const EdgeInsets.all(innerPad),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final fillWidth =
                  constraints.maxWidth * (percent.clamp(0, 100) / 100);
              return Row(
                children: [
                  AnimatedContainer(
                    duration: AppConstants.animSlow,
                    width: fillWidth,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Terminal nub
        Container(
          width: terminalWidth,
          height: height * 0.4,
          decoration: BoxDecoration(
            color: AppColors.textSecondary,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}
