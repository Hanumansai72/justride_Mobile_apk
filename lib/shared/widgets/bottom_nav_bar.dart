import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../core/network/api_client.dart';

class JustRideBottomNavBar extends StatelessWidget {
  const JustRideBottomNavBar(
      {super.key, required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;
  static const labels = ['Home', 'Places', 'Device', 'Profile'];
  static const icons = [
    Icons.home_outlined,
    Icons.explore_outlined,
    Icons.navigation_outlined
  ];

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: ApiClient.instance.savedUser,
        builder: (context, user, _) {
          final name =
              (user?['fullName'] ?? user?['name'] ?? user?['username'] ?? '')
                  .toString()
                  .trim();
          final initial =
              name.isEmpty ? '?' : name.characters.first.toUpperCase();
          return SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.surfaceElevated.withValues(alpha: 0.82),
                        AppColors.surface.withValues(alpha: 0.66),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.textPrimary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Material(
                    color: AppColors.transparent,
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        children: List.generate(
                            4,
                            (index) => Expanded(
                                    child: Semantics(
                                  label: labels[index],
                                  selected: currentIndex == index,
                                  button: true,
                                  child: Tooltip(
                                      message: labels[index],
                                      child: InkWell(
                                        onTap: () => onTap(index),
                                        child: SizedBox(
                                            height: 64,
                                            child: Center(
                                                child: index == 3
                                                    ? Container(
                                                        width: 30,
                                                        height: 30,
                                                        alignment:
                                                            Alignment.center,
                                                        decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color: currentIndex == index
                                                                ? AppColors
                                                                    .primary
                                                                : AppColors
                                                                    .surfaceElevated),
                                                        child: Text(initial,
                                                            style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: currentIndex == index
                                                                    ? AppColors
                                                                        .onPrimary
                                                                    : AppColors
                                                                        .textPrimary)))
                                                    : Icon(icons[index],
                                                        size: 25,
                                                        color: currentIndex == index
                                                            ? AppColors.primary
                                                            : AppColors.textMuted))),
                                      )),
                                ))),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
