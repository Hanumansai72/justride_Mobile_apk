import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const surfCont = Color(0xFF142226);
  static const surfContHigh = Color(0xFF1E2C30);
  static const surfContLow = Color(0xFF101E22);
  static const surfBright = Color(0xFF2D3B40);
  static const surfVariant = Color(0xFF29373B);
  static const primary = Color(0xFF4BE277);
  static const onPrimary = Color(0xFF003915);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
  static const outlineVariant = Color(0xFF3D4A3D);
  static const errorContainer = Color(0xFF93000A);
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
}


class DisplayCustomizationScreen extends StatefulWidget {
  const DisplayCustomizationScreen({super.key});

  @override
  State<DisplayCustomizationScreen> createState() =>
      _DisplayCustomizationScreenState();
}

class _DisplayCustomizationScreenState
    extends State<DisplayCustomizationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: _C.bg,
            border: Border(
              bottom: BorderSide(color: _C.outlineVariant, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.textSec, size: 24),
              ),
              Text(
                'Display Customization',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _C.primary,
                ),
              ),
              const SizedBox(width: 48), // Spacer for balance
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppConstants.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Preview Container
                _buildLivePreviewCard(),
                const SizedBox(height: AppConstants.spacingLg),

                // Upload Card
                _buildUploadCard(),
                const SizedBox(height: AppConstants.spacingMd),

                // Replace / Remove buttons
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.swap_horiz_rounded,
                        label: 'Replace',
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.delete_outline_rounded,
                        label: 'Remove',
                        isDestructive: true,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Apply to Device Button pinned at bottom
        Container(
          padding: EdgeInsets.fromLTRB(
            AppConstants.pagePadding,
            AppConstants.spacingMd,
            AppConstants.pagePadding,
            MediaQuery.of(context).padding.bottom + AppConstants.spacingMd,
          ),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: _C.outlineVariant, width: 1),
            ),
          ),
          child: _ApplyButton(onTap: () {}),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard() {
    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: _C.surfCont,
        border: Border.all(color: _C.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background subtle gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _C.surfContHigh.withValues(alpha: 0.5),
                    _C.surfContLow.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
          // LIVE PREVIEW label
          Positioned(
            top: 16,
            left: 16,
            child: Text(
              'LIVE PREVIEW',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: _C.textSec,
              ),
            ),
          ),
          // Hardware Device Circular Mockup
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _C.surfBright, width: 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipOval(
                  child: Container(
                    color: Colors.black,
                    child: _buildSpeedometerGraphic(),
                  ),
                ),
                // Glass glare overlay
                ClipOval(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedometerGraphic() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Speed ring arc
        SizedBox(
          width: 180,
          height: 180,
          child: CircularProgressIndicator(
            value: 0.65,
            strokeWidth: 10,
            backgroundColor: _C.outlineVariant.withValues(alpha: 0.3),
            valueColor: const AlwaysStoppedAnimation<Color>(_C.primary),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '9.8',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _C.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '124',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 42,
                fontWeight: FontWeight.w700,
                color: _C.onSurface,
                letterSpacing: -1,
              ),
            ),
            Text(
              'KM/H',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _C.textSec,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _C.primary, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '5',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _C.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadCard() {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: _C.outlineVariant,
        strokeWidth: 1.5,
        gap: 6,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: _C.surfCont,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _C.surfVariant,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                color: _C.textSec,
                size: 28,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              'Upload Image',
              style: AppTextStyles.headingSmall.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _C.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'PNG or JPG, ideal size 400×400px',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 14,
                color: _C.textSec,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        height: 84,
        decoration: BoxDecoration(
          color: _pressed
              ? (widget.isDestructive ? _C.errorContainer : _C.surfVariant)
              : _C.surfCont,
          border: Border.all(
            color: widget.isDestructive && _pressed
                ? _C.error
                : _C.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              color: _pressed
                  ? (widget.isDestructive ? _C.onError : _C.onSurface)
                  : _C.textSec,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _pressed
                    ? (widget.isDestructive ? _C.onError : _C.onSurface)
                    : _C.textSec,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyButton extends StatefulWidget {
  const _ApplyButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ApplyButton> createState() => _ApplyButtonState();
}

class _ApplyButtonState extends State<_ApplyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: AppConstants.animFast,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: _C.primary,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withValues(alpha: 0.25),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.send_to_mobile_rounded,
                color: _C.onPrimary,
                size: 22,
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Text(
                'Apply to Device',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _C.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Custom Painter for Dashed Outline ─────────────────────────────────────────
class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.gap = 5.0,
  });

  final Color color;
  final double strokeWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dashedPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(AppConstants.radiusLg),
    );

    final Path path = Path()..addRRect(rrect);
    final Path dashPath = Path();

    double distance = 0.0;
    for (final PathMetric metric in path.computeMetrics()) {
      while (distance < metric.length) {
        final double len = gap;
        if (distance + len > metric.length) {
          dashPath.addPath(
            metric.extractPath(distance, metric.length),
            Offset.zero,
          );
          break;
        }
        dashPath.addPath(
          metric.extractPath(distance, distance + len),
          Offset.zero,
        );
        distance += len * 2;
      }
      distance = 0.0;
    }

    canvas.drawPath(dashPath, dashedPaint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap;
  }
}
