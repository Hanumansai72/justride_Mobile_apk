import '../../../core/services/backend_service.dart';
import '../../../core/models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/app_logo.dart';

// â”€â”€ Color tokens (consistent with all JustRide screens) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _C {
  static const bg = Color(0xFF071519);
  static const cardBg = Color(0xFF151A17);
  static const cardBorder = Color(0xFF27312B);
  static const surfContHigh = Color(0xFF1E2C30);
  static const primary = Color(0xFF4BE277);
  static const textSec = Color(0xFFBCCBB9);
  static const onSurface = Color(0xFFD6E5EA);
  static const outlineVariant = Color(0xFF3D4A3D);
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  AppReleaseModel? _latestApkRelease;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkAppUpdate();
  }

  Future<void> _checkAppUpdate() async {
    setState(() => _isChecking = true);
    try {
      final res = await BackendService.instance.getLatestAppRelease(currentBuild: 2);
      if (res.success && res.data != null && res.data!.buildNumber > 2) {
        if (mounted) {
          setState(() {
            _latestApkRelease = res.data;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  // â”€â”€ App Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacementNamed('/dashboard');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.textSec, size: 24),
              ),
              // AppLogo identical to all other screens
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: _C.textSec, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pagePadding,
        vertical: AppConstants.spacingXl,
      ),
      child: Column(
        children: [
          // â”€â”€ Header: icon + title + version badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SizedBox(height: AppConstants.spacingLg),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.cardBg,
              border: Border.all(color: _C.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: _C.primary.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.two_wheeler_rounded,
                color: _C.primary, size: 48),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'About JustRide',
            style: AppTextStyles.headingLarge.copyWith(
              fontSize: 24,
              color: _C.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          // Version badge
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm),
            decoration: BoxDecoration(
              color: _C.surfContHigh,
              border: Border.all(color: _C.outlineVariant),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusCircle),
            ),
            child: Text(
              'v1.1.0 (Build 2)',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _C.textSec,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // â”€â”€ Links List â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_latestApkRelease != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: _C.primary.withValues(alpha: 0.12),
                border: Border.all(color: _C.primary.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: _C.primary, size: 28),
                  const SizedBox(width: AppConstants.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Available: v${_latestApkRelease!.version} (b${_latestApkRelease!.buildNumber})',
                          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _latestApkRelease!.releaseNotes?.isNotEmpty == true
                              ? _latestApkRelease!.releaseNotes!
                              : 'New features and stability updates are available.',
                          style: AppTextStyles.bodySmall.copyWith(color: _C.textSec),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          _LinkTile(
            icon: Icons.system_update_alt_rounded,
            label: _isChecking
                ? 'Checking for Updates...'
                : (_latestApkRelease != null
                    ? 'Download Latest APK'
                    : 'Check for App Updates'),
            onTap: () {
              if (_latestApkRelease != null && _latestApkRelease!.downloadUrl != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Downloading APK: ${_latestApkRelease!.downloadUrl}'),
                    backgroundColor: _C.primary,
                  ),
                );
              } else {
                _checkAppUpdate();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You are already running the latest version!'),
                    backgroundColor: _C.primary,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: AppConstants.spacingSm),
          _LinkTile(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: () {},
          ),
          const SizedBox(height: AppConstants.spacingSm),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () {},
          ),
          const SizedBox(height: AppConstants.spacingSm),
          _LinkTile(
            icon: Icons.code_rounded,
            label: 'Open Source Licenses',
            onTap: () {},
          ),
          const SizedBox(height: AppConstants.spacingSection),
        ],
      ),
    );
  }

  // â”€â”€ Footer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _C.outlineVariant, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppConstants.spacingLg,
        horizontal: AppConstants.pagePadding,
      ),
      child: Column(
        children: [
          Text(
            'Â© 2024 JustRide Technologies',
            style: AppTextStyles.bodyMedium.copyWith(color: _C.textSec),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulsingDot(),
              const SizedBox(width: AppConstants.spacingSm),
              Text(
                'ALL SYSTEMS OPERATIONAL',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: _C.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Link Tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _LinkTile extends StatefulWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
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
        duration: AppConstants.animFast,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: _C.cardBg,
          border: Border.all(
            color: _hovered
                ? _C.primary.withValues(alpha: 0.5)
                : _C.cardBorder,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            Icon(widget.icon,
                color: _hovered ? _C.primary : _C.textSec, size: 22),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Text(
                widget.label,
                style: AppTextStyles.bodyLarge.copyWith(color: _C.onSurface),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _C.textSec, size: 22),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Pulsing Dot â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _C.primary,
          boxShadow: [
            BoxShadow(color: Color(0x994BE277), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
