import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import 'support_ticket_screen.dart';


// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const surfCont = Color(0xFF142226);
  static const surfContHigh = Color(0xFF1E2C30);
  static const primary = Color(0xFF4BE277);
  static const onPrimary = Color(0xFF003915);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
  static const outlineVariant = Color(0xFF3D4A3D);
  static const tertiary = Color(0xFF7CD0FF);
  static const secondary = Color(0xFF4DE082);
}

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final int _navIndex = 3; // Profile tab active

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 3) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/places');
          } else if (i == 2) {
            Navigator.of(context).pushReplacementNamed('/device');
          }
        },
      ),
    );
  }


  // ── App Bar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
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
                    color: _C.primary, size: 24),
              ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: _C.primary, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppConstants.spacingLg),

          // Title & subtitle
          Text(
            'Help & Support',
            style: AppTextStyles.headingLarge.copyWith(
              fontSize: 24,
              color: _C.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Select a category below or submit a new ticket for assistance.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: _C.textSec,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // Bento grid (2-col with last spanning full width)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _CategoryCard(
                        icon: Icons.devices_rounded,
                        label: 'Device Problem',
                        iconColor: _C.primary,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SupportTicketScreen(
                              initialCategory: 'device_problem',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: _CategoryCard(
                        icon: Icons.wifi_off_rounded,
                        label: 'Connection Issue',
                        iconColor: _C.tertiary,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SupportTicketScreen(
                              initialCategory: 'connection_issue',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingMd),
                Row(
                  children: [
                    Expanded(
                      child: _CategoryCard(
                        icon: Icons.system_update_alt_rounded,
                        label: 'Firmware Problem',
                        iconColor: _C.secondary,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SupportTicketScreen(
                              initialCategory: 'firmware_problem',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: _CategoryCard(
                        icon: Icons.manage_accounts_rounded,
                        label: 'Account Problem',
                        iconColor: _C.textSec,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SupportTicketScreen(
                              initialCategory: 'account_problem',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingMd),
                // Full-width "Other" card
                _CategoryCard(
                  icon: Icons.help_outline_rounded,
                  label: 'Other',
                  iconColor: _C.textSec,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SupportTicketScreen(
                        initialCategory: 'general',
                      ),
                    ),
                  ),
                  fullWidth: true,
                ),

                const Spacer(),
              ],
            ),
          ),

          // Action buttons
          _ActionButton(
            icon: Icons.report_rounded,
            label: 'REPORT A PROBLEM',
            filled: true,
            onTap: () => Navigator.of(context).pushNamed('/support-ticket'),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _ActionButton(
            icon: Icons.confirmation_number_outlined,
            label: 'MY TICKETS',
            filled: false,
            onTap: () => Navigator.of(context).pushNamed('/my-tickets'),
          ),

          const SizedBox(height: AppConstants.spacingLg),
        ],
      ),
    );
  }
}

// ── Category Card ─────────────────────────────────────────────────────────────
class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
    this.fullWidth = false,
  });
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppConstants.animNormal,
        height: widget.fullWidth ? 100 : 120,
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: _C.surfCont,
          border: Border.all(
            color: _hovered ? _C.primary : _C.outlineVariant,
            width: _hovered ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Hover gradient overlay
            AnimatedOpacity(
              opacity: _hovered ? 1.0 : 0.0,
              duration: AppConstants.animNormal,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _C.surfContHigh,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Content
            widget.fullWidth
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: _hovered ? 1.1 : 1.0,
                          duration: AppConstants.animNormal,
                          child: Icon(widget.icon,
                              color: widget.iconColor, size: 32),
                        ),
                        const SizedBox(height: AppConstants.spacingSm),
                        Text(
                          widget.label,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: _hovered ? _C.primary : _C.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        scale: _hovered ? 1.1 : 1.0,
                        duration: AppConstants.animNormal,
                        child: Icon(widget.icon,
                            color: widget.iconColor, size: 32),
                      ),
                      const SizedBox(height: AppConstants.spacingSm),
                      Text(
                        widget.label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _hovered ? _C.primary : _C.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────
class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
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
        scale: _pressed ? 0.97 : 1.0,
        duration: AppConstants.animFast,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: widget.filled ? _C.primary : Colors.transparent,
            border: Border.all(
              color: widget.filled ? _C.primary : _C.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: widget.filled ? _C.onPrimary : _C.primary,
                size: 20,
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Text(
                widget.label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: widget.filled ? _C.onPrimary : _C.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
