import '../../../app/theme/app_colors.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/models/app_models.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routes/app_routes.dart';

// â”€â”€ Color tokens (consistent with all JustRide screens) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const surfContHigh = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const textSec = AppColors.textSecondary;
  static const onSurface = AppColors.textPrimary;
  static const outlineVariant = AppColors.border;
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  AppReleaseModel? _latestApkRelease;
  bool _isChecking = false;
  String? _updateStatus;
  String? _installedVersion;
  int? _installedBuild;

  @override
  void initState() {
    super.initState();
    _checkAppUpdate();
  }

  Future<void> _checkAppUpdate() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    final updates = AppUpdateService.instance;
    await updates.check();
    if (!mounted) return;
    setState(() {
      _installedBuild = updates.installedBuild;
      _installedVersion = updates.installedVersion;
      _latestApkRelease = updates.hasUpdate ? updates.release : null;
      _updateStatus = updates.error ??
          (updates.hasUpdate
              ? 'A new update is available.'
              : 'Your app is up to date.');
      _isChecking = false;
    });
  }

  void _openDownload() => Navigator.of(context).pushNamed(AppRoutes.appUpdate);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: SafeArea(top: false, child: _buildBody()),
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
              Image.asset(
                'assets/justride-logo-horizontal.png',
                width: 140,
                fit: BoxFit.contain,
                semanticLabel: 'JustRide',
              ),
              IconButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/profile-settings'),
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
          Image.asset(
            'assets/justride-logo-horizontal.png',
            width: 280,
            fit: BoxFit.contain,
            semanticLabel: 'JustRide official company logo',
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
              borderRadius: BorderRadius.circular(AppConstants.radiusCircle),
            ),
            child: Text(
              '${_installedVersion ?? AppConstants.appVersion} (Build ${_installedBuild ?? '…'})',
              style: TextStyle(
                fontFamily: 'Stack Sans Text',
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
                  const Icon(Icons.system_update_rounded,
                      color: _C.primary, size: 28),
                  const SizedBox(width: AppConstants.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Available: v${_latestApkRelease!.version} (b${_latestApkRelease!.buildNumber})',
                          style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'A new update is available. Please update the JustRide app.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: _C.textSec),
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
            onTap: _isChecking
                ? null
                : (_latestApkRelease != null ? _openDownload : _checkAppUpdate),
          ),
          if (_updateStatus != null) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Text(_updateStatus!,
                style: AppTextStyles.bodyMedium.copyWith(color: _C.textSec)),
          ],
          const SizedBox(height: AppConstants.spacingSm),
          _LinkTile(
            icon: Icons.description_outlined,
            label: 'Terms & Conditions',
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.terms),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.privacy),
          ),
          const SizedBox(height: AppConstants.spacingSection),
        ],
      ),
    );
  }
}

class _LinkTile extends StatefulWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _hovered = true),
        onTapUp: (_) {
          setState(() => _hovered = false);
        },
        onTapCancel: () => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: AppConstants.animFast,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            color: _C.cardBg,
            border: Border.all(
              color:
                  _hovered ? _C.primary.withValues(alpha: 0.5) : _C.cardBorder,
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
              const Icon(Icons.chevron_right_rounded,
                  color: _C.textSec, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
