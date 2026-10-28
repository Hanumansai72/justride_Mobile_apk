import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/navigation_state.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/utils/maneuver_mapper.dart';

/// Live active navigation route card displayed prominently at top of Dashboard.
/// Shows live maneuver direction, remaining distance, ETA, and quick resume/cancel actions.
class ActiveNavigationDashboardCard extends StatelessWidget {
  const ActiveNavigationDashboardCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NavigationState>(
      valueListenable: NavigationService.instance.navigationStateNotifier,
      builder: (context, state, _) {
        final isNavigating = NavigationService.instance.isNavigating;
        if (!isNavigating) return const SizedBox.shrink();

        final isRerouting = state.rerouting;

        return Container(
          margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryContainer, AppColors.surface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: isRerouting
                  ? AppColors.warning
                  : AppColors.primary.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  Navigator.of(context).pushNamed('/active-navigation'),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header tag row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRerouting
                                    ? AppColors.warning
                                    : AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isRerouting
                                  ? 'REROUTING...'
                                  : 'LIVE NAVIGATION ACTIVE',
                              style: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isRerouting
                                    ? AppColors.warning
                                    : AppColors.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        // Quick cancel button
                        GestureDetector(
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.backgroundInset,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side:
                                      const BorderSide(color: AppColors.border),
                                ),
                                title: Text(
                                  'Cancel Navigation?',
                                  style: TextStyle(
                                    fontFamily: 'Stack Sans Text',
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                content: Text(
                                  'Stop active route guidance on both phone and JustRide display?',
                                  style: TextStyle(
                                      fontFamily: 'Stack Sans Text',
                                      color: AppColors.textSecondary),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text('KEEP RIDING',
                                        style: TextStyle(
                                            fontFamily: 'Stack Sans Text',
                                            color: AppColors.primary)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.error,
                                        foregroundColor: AppColors.textPrimary),
                                    child: Text('CANCEL ROUTE',
                                        style: TextStyle(
                                            fontFamily: 'Stack Sans Text',
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await NavigationService.instance.stopNavigation();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.errorText.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppColors.errorText
                                      .withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.close_rounded,
                                    size: 13, color: AppColors.errorText),
                                const SizedBox(width: 4),
                                Text(
                                  'CANCEL',
                                  style: TextStyle(
                                    fontFamily: 'Stack Sans Text',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.errorText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Maneuver icon + distance + street name
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.15),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.4)),
                          ),
                          child: Icon(
                            ManeuverMapper.toIcon(state.maneuver),
                            color: AppColors.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    state.maneuverDistanceFormatted,
                                    style: TextStyle(
                                      fontFamily: 'Stack Sans Text',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${ManeuverMapper.toArrowSymbol(state.maneuver)} ${ManeuverMapper.toRiderActionText(state.maneuver)}',
                                    style: TextStyle(
                                      fontFamily: 'Stack Sans Text',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                state.maneuverText.isNotEmpty
                                    ? state.maneuverText
                                    : 'Follow route ahead',
                                style: TextStyle(
                                  fontFamily: 'Stack Sans Text',
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: AppColors.textMuted),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 10),

                    // Bottom info: Speed, Total Remaining, ETA
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SPEED: ${state.speedDisplay} KM/H',
                          style: TextStyle(
                            fontFamily: 'Stack Sans Text',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'REMAINING: ${state.remainingDistanceFormatted}',
                          style: TextStyle(
                            fontFamily: 'Stack Sans Text',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'ETA: ${state.arrivalTimeFormatted}',
                          style: TextStyle(
                            fontFamily: 'Stack Sans Text',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
