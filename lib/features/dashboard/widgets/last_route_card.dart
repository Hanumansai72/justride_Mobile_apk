import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Card showing the last route with a stylised map placeholder,
/// route stats, and a "Start Ride" CTA button.
class LastRouteCard extends StatelessWidget {
  const LastRouteCard({super.key, required this.onStartRide});

  final VoidCallback onStartRide;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── Map background (custom painted) ────────────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _MapPainter()),
          ),

          // ── Content overlay ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label
                Text(
                  'LAST ROUTE',
                  style: AppTextStyles.labelSmall.copyWith(
                    letterSpacing: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),

                // Route name
                Text(AppConstants.lastRouteName,
                    style: AppTextStyles.displayMedium),
                const SizedBox(height: 3),

                // Via row
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(AppConstants.lastRouteVia,
                        style: AppTextStyles.bodyMedium),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingXl),

                // Stats row
                const Row(
                  children: [
                    _RouteStat(
                      icon: Icons.straighten_rounded,
                      value: AppConstants.lastRouteDistance,
                      label: 'Distance',
                    ),
                    SizedBox(width: AppConstants.spacingXxl),
                    _RouteStat(
                      icon: Icons.timer_outlined,
                      value: AppConstants.lastRouteEta,
                      label: 'ETA',
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingXl),

                // CTA row
                Row(
                  children: [
                    // Start Ride button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onStartRide,
                        icon: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.background, size: 22),
                        label: Text('START RIDE', style: AppTextStyles.button),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusMd),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),

                    // Route overview button
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.map_outlined,
                          color: AppColors.textSecondary, size: 16),
                      label: Text(
                        'Route Overview',
                        style: AppTextStyles.labelMedium,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat item ────────────────────────────────────────────────────────────────

class _RouteStat extends StatelessWidget {
  const _RouteStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppTextStyles.headingSmall),
            Text(label, style: AppTextStyles.labelSmall),
          ],
        ),
      ],
    );
  }
}

// ── Custom map painter ────────────────────────────────────────────────────────

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final routePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw faint road grid
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }

    // Draw route path (right side)
    final path = Path()
      ..moveTo(size.width * 0.55, size.height * 0.85)
      ..lineTo(size.width * 0.55, size.height * 0.6)
      ..lineTo(size.width * 0.7, size.height * 0.6)
      ..lineTo(size.width * 0.7, size.height * 0.35)
      ..lineTo(size.width * 0.85, size.height * 0.15);

    canvas.drawPath(path, routePaint);

    // Origin dot
    canvas.drawCircle(
      Offset(size.width * 0.55, size.height * 0.85),
      6,
      Paint()
        ..color = AppColors.background
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(size.width * 0.55, size.height * 0.85),
      6,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Destination pin
    final pinPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      8,
      pinPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      5,
      Paint()
        ..color = AppColors.background
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
