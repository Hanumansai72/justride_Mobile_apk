import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
              colors: [Color(0xFF0D251C), Color(0xFF132025)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: isRerouting ? Colors.amber : AppColors.primary.withValues(alpha: 0.6),
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
              onTap: () => Navigator.of(context).pushNamed('/active-navigation'),
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
                                color: isRerouting ? Colors.amber : AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isRerouting ? 'REROUTING...' : 'LIVE NAVIGATION ACTIVE',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isRerouting ? Colors.amber : AppColors.primary,
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
                                backgroundColor: const Color(0xFF101E22),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: Color(0xFF22353A)),
                                ),
                                title: Text(
                                  'Cancel Navigation?',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                content: Text(
                                  'Stop active route guidance on both phone and JustRide display?',
                                  style: GoogleFonts.inter(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: Text('KEEP RIDING', style: GoogleFonts.jetBrainsMono(color: AppColors.primary)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                    child: Text('CANCEL ROUTE', style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await NavigationService.instance.stopNavigation();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.close_rounded, size: 13, color: Colors.redAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'CANCEL',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.redAccent,
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
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
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
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${ManeuverMapper.toArrowSymbol(state.maneuver)} ${ManeuverMapper.toRiderActionText(state.maneuver)}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                state.maneuverText.isNotEmpty ? state.maneuverText : 'Follow route ahead',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white54),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF22353A), height: 1),
                    const SizedBox(height: 10),

                    // Bottom info: Speed, Total Remaining, ETA
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SPEED: ${state.speedDisplay} KM/H',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'REMAINING: ${state.remainingDistanceFormatted}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'ETA: ${state.arrivalTimeFormatted}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF38BDF8),
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
