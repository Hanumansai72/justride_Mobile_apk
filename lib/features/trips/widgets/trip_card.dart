import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../models/trip_model.dart';

/// Single trip list item card with a custom-painted map thumbnail.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip});

  final TripModel trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          child: Row(
            children: [
              // Map thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: CustomPaint(painter: _TripMapPainter()),
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),

              // Trip details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Origin
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            trip.origin,
                            style: AppTextStyles.labelLarge.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Destination
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.errorText.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            trip.destination,
                            style: AppTextStyles.bodyMedium.copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Stats row
                    Row(
                      children: [
                        Expanded(
                          child: _StatChip(
                            icon: Icons.straighten_rounded,
                            value: '${trip.distanceKm} km',
                            label: 'Distance',
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingMd),
                        Expanded(
                          child: _StatChip(
                            icon: Icons.timer_outlined,
                            value: '${trip.durationMin} min',
                            label: 'Duration',
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingMd),
                        Expanded(
                          child: _StatChip(
                            icon: Icons.eco_rounded,
                            value: '${trip.co2SavedKg} kg',
                            label: 'CO₂ Saved',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Date + chevron column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trip.dateLabel,
                    style: AppTextStyles.labelSmall.copyWith(fontSize: 9),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 24),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inline stat chip ──────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: AppColors.primary),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                value,
                style: AppTextStyles.labelLarge.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(fontSize: 9),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}

// ── Trip map thumbnail painter ────────────────────────────────────────────────

class _TripMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dark background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.surface,
    );

    // Faint grid roads
    final roadPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }
    for (double y = 0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }

    // Route line
    final routePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.8)
      ..lineTo(size.width * 0.2, size.height * 0.5)
      ..lineTo(size.width * 0.55, size.height * 0.5)
      ..lineTo(size.width * 0.55, size.height * 0.25)
      ..lineTo(size.width * 0.8, size.height * 0.15);

    canvas.drawPath(path, routePaint);

    // Origin dot
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.8),
      4,
      Paint()
        ..color = AppColors.background
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.8),
      4,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Destination pin (red)
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.15),
      5,
      Paint()..color = AppColors.errorText,
    );
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.15),
      2.5,
      Paint()..color = AppColors.background,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
