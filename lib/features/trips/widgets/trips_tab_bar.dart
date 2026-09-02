import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Filter icon tab bar: All Trips / This Week / This Month / This Year.
class TripsTabBar extends StatefulWidget {
  const TripsTabBar({super.key});

  @override
  State<TripsTabBar> createState() => _TripsTabBarState();
}

class _TripsTabBarState extends State<TripsTabBar> {
  int _selected = 0;

  static const List<String> _tabs = [
    'All Trips',
    'This Week',
    'This Month',
    'This Year',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = _selected == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selected = i),
              child: AnimatedContainer(
                duration: AppConstants.animNormal,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryContainer : AppColors.transparent,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: AppConstants.animNormal,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.primary : AppColors.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 11,
                  ),
                  child: Text(_tabs[i]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
