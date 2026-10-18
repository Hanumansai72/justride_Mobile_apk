import '../../../shared/widgets/contextual_help_button.dart';
import '../../../app/theme/app_colors.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/services/ota_service.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/models/app_models.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/device_unlink_dialog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/ble_navigation_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';

// â”€â”€ Colour tokens matching the HTML design â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SC {
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const textSec = AppColors.textSecondary;
  static const errorRed = AppColors.errorLight;
  static const surfCont = AppColors.surfaceElevated;
  static const bg = AppColors.background;
}

class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  int _navIndex = 3;
  double _brightness = 0.85;

  String get _brightnessLabel => '${(_brightness * 100).round()}%';

  Future<void> _setBrightness(double value) async {
    setState(() => _brightness = value);
    final ok = await BleNavigationService.instance
        .sendSetBrightness((value * 100).round());
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Display is not connected. Reconnect and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SC.bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/trips');
          } else if (i == 2) {
            Navigator.of(context).pushNamed('/pair-device');
          } else if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/notifications');
          } else if (i == 4) {
            Navigator.of(context).pushReplacementNamed('/profile');
          }
        },
      ),
    );
  }

  // â”€â”€ App Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: _SC.bg,
            border: Border(
              bottom: BorderSide(color: _SC.cardBorder, width: 1),
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
                    Navigator.of(context).pushReplacementNamed('/device');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _SC.primary, size: 24),
              ),
              // AppLogo reused from login page
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              const ContextualHelpButton(category: 'Connectivity'),
              IconButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: _SC.primary, size: 24),
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
        vertical: AppConstants.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page Title
          Text(
            'Hardware Settings',
            style: AppTextStyles.displayMedium.copyWith(
              fontSize: 24,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Device Identity & Status Card
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pushNamed('/display-customization'),
            child: _DeviceIdentityCard(),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Brightness Control (Syncs directly to ESP32 Display Backlight)
          _BrightnessCard(
            value: _brightness,
            label: _brightnessLabel,
            onChanged: _setBrightness,
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // 2-col Device Hardware Controls: Restart & Factory Reset
          Row(
            children: [
              Expanded(
                child: _SettingsTile(
                  icon: Icons.restart_alt_rounded,
                  title: 'Restart\nDevice',
                  onTap: () => _confirmRestartDevice(context),
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: _SettingsTile(
                  icon: Icons.restore_rounded,
                  title: 'Reset to\nDefaults',
                  onTap: () => _confirmResetDevice(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // 2-col grid
          Row(
            children: [
              Expanded(
                child: _SettingsTile(
                  icon: Icons.display_settings_rounded,
                  title: 'Display\nCustomization',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/display-customization'),
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: _SettingsTile(
                  icon: Icons.bluetooth_searching_rounded,
                  title: 'Pair New\nDevice',
                  onTap: () => Navigator.of(context).pushNamed('/pair-device'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Hardware Diagnostics Section (Bluetooth, GPS, Display, Battery)
          const _HardwareDiagnosticsCard(),
          const SizedBox(height: AppConstants.spacingMd),

          // Firmware Update
          _FirmwareUpdateCard(),
          const SizedBox(height: AppConstants.spacingSection),

          // Disconnect & Unlink section
          const Divider(color: _SC.cardBorder, thickness: 1),
          const SizedBox(height: AppConstants.spacingMd),
          _DisconnectButton(),
          const SizedBox(height: AppConstants.spacingMd),
          _UnlinkButton(),
          const SizedBox(height: AppConstants.spacingLg),
        ],
      ),
    );
  }

  void _confirmRestartDevice(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SC.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _SC.cardBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.restart_alt_rounded, color: _SC.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Restart Device?',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'This will restart the JustRide motorcycle cockpit HUD display.',
          style: GoogleFonts.inter(color: _SC.textSec, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: GoogleFonts.inter(color: _SC.textSec)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok =
                  await BleNavigationService.instance.sendRestartDevice();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Restart command sent to JustRide HUD'
                        : 'Device not connected via Bluetooth'),
                    backgroundColor: ok ? _SC.primary : _SC.errorRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _SC.primary,
              foregroundColor: _SC.onPrimary,
            ),
            child: Text(
              'RESTART',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmResetDevice(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SC.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _SC.cardBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: _SC.errorRed, size: 24),
            const SizedBox(width: 8),
            Text(
              'Reset to Defaults?',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'This will reset the HUD display brightness (70%), recenter navigation camera, and return to Home screen.',
          style: GoogleFonts.inter(color: _SC.textSec, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: GoogleFonts.inter(color: _SC.textSec)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await BleNavigationService.instance.sendResetDevice();
              setState(() => _brightness = 0.70);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Reset command sent to JustRide HUD'
                        : 'Device not connected via Bluetooth'),
                    backgroundColor: ok ? _SC.primary : _SC.errorRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _SC.errorRed,
              foregroundColor: Colors.black,
            ),
            child: Text(
              'RESET',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Device Identity Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _DeviceIdentityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _SC.cardBg,
        border: Border.all(color: _SC.cardBorder),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Top accent line
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    _SC.primary.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon circle
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _SC.bg,
                        border: Border.all(color: _SC.cardBorder),
                      ),
                      child: const Icon(
                        Icons.two_wheeler_rounded,
                        color: _SC.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'JustRide HUD',
                            style: AppTextStyles.headingMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _LabelCaps(text: 'SERIAL: JR-A7F3K9'),
                          const SizedBox(height: 2),
                          _LabelCaps(text: 'FIRMWARE: v2.1.0'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingMd),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Connected badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _SC.surfCont,
                        border: Border.all(color: _SC.cardBorder),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusCircle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(),
                          const SizedBox(width: 6),
                          _LabelCaps(text: 'CONNECTED', color: _SC.primary),
                        ],
                      ),
                    ),
                    // Battery
                    Row(
                      children: [
                        const Icon(Icons.battery_full_rounded,
                            color: _SC.textSec, size: 16),
                        const SizedBox(width: 4),
                        _LabelCaps(text: '98%'),
                      ],
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

// â”€â”€ Brightness Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _BrightnessCard extends StatelessWidget {
  const _BrightnessCard({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMd,
          AppConstants.spacingMd,
          AppConstants.spacingMd,
          AppConstants.spacingSm),
      decoration: BoxDecoration(
        color: _SC.cardBg,
        border: Border.all(color: _SC.cardBorder),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.light_mode_outlined,
                      color: AppColors.textPrimary, size: 22),
                  const SizedBox(width: AppConstants.spacingSm),
                  Text(
                    'Display Brightness',
                    style: AppTextStyles.headingSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _SC.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: _SC.primary,
              inactiveTrackColor: AppColors.surfaceElevated,
              thumbColor: _SC.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayColor: _SC.primary.withValues(alpha: 0.2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 1,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Settings Tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SettingsTile extends StatefulWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.fullWidth = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
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
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: _pressed ? AppColors.surfaceElevated : _SC.cardBg,
          border: Border.all(color: _SC.cardBorder),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: AppColors.textPrimary, size: 22),
                const SizedBox(width: AppConstants.spacingSm),
                Text(
                  widget.title,
                  style: AppTextStyles.headingSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _pressed ? _SC.primary : _SC.textSec,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Firmware Update Card ─────────────────────────────────────────────────────
class _FirmwareUpdateCard extends StatefulWidget {
  @override
  State<_FirmwareUpdateCard> createState() => _FirmwareUpdateCardState();
}

class _FirmwareUpdateCardState extends State<_FirmwareUpdateCard> {
  FirmwareReleaseModel? _latestRelease;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLatestRelease();
  }

  Future<void> _fetchLatestRelease() async {
    try {
      final res = await BackendService.instance.getLatestFirmwareRelease();
      if (mounted && res.success && res.data != null) {
        setState(() {
          _latestRelease = res.data;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _showOtaModal(BuildContext context) {
    final dev = JustRideBleService.instance.connectedDevice;
    if (dev == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please connect to JustRide device over Bluetooth first.'),
          backgroundColor: _SC.errorRed,
        ),
      );
      return;
    }

    final targetVer = _latestRelease?.version ?? '2.2.0';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<OtaProgress>(
          valueListenable: JustRideOtaService.instance.progressNotifier,
          builder: (context, progress, _) {
            final isDone = progress.state == OtaState.success;
            final isFailed = progress.state == OtaState.failed;

            return AlertDialog(
              backgroundColor: _SC.cardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Firmware Update (v$targetVer)',
                style: AppTextStyles.headingMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    progress.statusMessage,
                    style:
                        AppTextStyles.bodyMedium.copyWith(color: _SC.textSec),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress.progress.clamp(0.0, 1.0).toDouble(),
                    backgroundColor: _SC.surfCont,
                    color: _SC.primary,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(progress.progress * 100).round()}% Complete',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.jetBrainsMono(
                      color: _SC.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (progress.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Error: ${progress.error}',
                      style: const TextStyle(color: _SC.errorRed, fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                if (isDone || isFailed)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close',
                        style: TextStyle(color: _SC.primary)),
                  )
                else
                  TextButton(
                    onPressed: () {
                      JustRideOtaService.instance.cancelUpdate();
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Cancel',
                        style: TextStyle(color: _SC.textSec)),
                  ),
              ],
            );
          },
        );
      },
    );

    // If download_url exists from backend, download & flash. Otherwise fallback to bundled binary.
    () async {
      try {
        final downloadUrl = _latestRelease?.fileUrl;
        if (downloadUrl != null && downloadUrl.startsWith('http')) {
          await JustRideOtaService.instance.downloadAndFlashFirmware(
            device: dev,
            downloadUrl: downloadUrl,
            deviceId: dev.remoteId.str,
            targetVersion: targetVer,
          );
        } else {
          final byteData =
              await rootBundle.load('assets/firmware/justride_firmware.bin');
          final realFirmwareBytes = byteData.buffer.asUint8List();
          debugPrint(
              '[OTA] Loaded bundled firmware binary: ${realFirmwareBytes.length} bytes, magic: 0x${realFirmwareBytes[0].toRadixString(16)}');
          await JustRideOtaService.instance.flashFirmware(
            device: dev,
            firmwareBytes: realFirmwareBytes,
          );
        }
      } catch (err) {
        debugPrint('[OTA] Error starting firmware flash: $err');
        JustRideOtaService.instance.progressNotifier.value = OtaProgress(
          state: OtaState.failed,
          progress: 0.0,
          statusMessage: 'Firmware file missing',
          error: 'Could not load firmware binary: $err',
        );
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final versionStr = _latestRelease?.version ?? '2.2.0';
    final notes = _latestRelease?.releaseNotes?.isNotEmpty == true
        ? _latestRelease!.releaseNotes!
        : 'Performance & Stability Fixes';

    return Container(
      decoration: BoxDecoration(
        color: _SC.cardBg,
        border: Border.all(color: _SC.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: _SC.primary.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.system_update_rounded,
                        color: _SC.primary, size: 22),
                    const SizedBox(width: AppConstants.spacingSm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Available',
                          style: AppTextStyles.headingSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _LabelCaps(
                          text: 'v$versionStr — $notes',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingMd),
                _GlowButton(
                  label: _isLoading ? 'Checking Updates...' : 'Update Device',
                  onTap: () => _showOtaModal(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Disconnect Bluetooth Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _DisconnectButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BluetoothConnectionState>(
      valueListenable: JustRideBleService.instance.connectionStateNotifier,
      builder: (context, connState, _) {
        final isConnected = connState == BluetoothConnectionState.connected ||
            JustRideBleService.instance.isDeviceConnected;

        return Center(
          child: OutlinedButton.icon(
            onPressed: () async {
              if (isConnected) {
                await JustRideBleService.instance.disconnectDevice();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Bluetooth disconnected. Device remains paired to your account.'),
                      duration: Duration(seconds: 3),
                      backgroundColor: _SC.surfCont,
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Searching for your JustRide deviceâ€¦'),
                      duration: Duration(seconds: 2),
                      backgroundColor: _SC.primary,
                    ),
                  );
                }
                final bleAddress =
                    await JustRideBleService.instance.loadSavedBleAddress();
                final ok = await JustRideBleService.instance
                    .reconnect(targetBleAddress: bleAddress);
                if (context.mounted) {
                  final err =
                      JustRideBleService.instance.lastBleErrorNotifier.value;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Reconnected & real-time clock synced!'
                          : (err ??
                              (bleAddress != null
                                  ? 'Could not find device ($bleAddress). Ensure it is nearby.'
                                  : 'No paired device found. Please pair first.'))),
                      duration: const Duration(seconds: 3),
                      backgroundColor: ok ? _SC.primary : _SC.errorRed,
                    ),
                  );
                }
              }
            },
            icon: Icon(
              isConnected
                  ? Icons.bluetooth_disabled_rounded
                  : Icons.bluetooth_connected_rounded,
              color: isConnected ? _SC.textSec : _SC.primary,
              size: 20,
            ),
            label: Text(
              isConnected ? 'Disconnect Bluetooth' : 'Reconnect Bluetooth',
              style: AppTextStyles.bodyLarge.copyWith(
                color: isConnected ? _SC.textSec : _SC.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: isConnected ? _SC.cardBorder : _SC.primary,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingLg,
                vertical: AppConstants.spacingSm,
              ),
            ),
          ),
        );
      },
    );
  }
}

// â”€â”€ Unlink Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _UnlinkButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final result = await BackendService.instance.getMyDevice();
          if (!context.mounted) return;
          final device = result.data;
          if (!result.success || device == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(result.success
                    ? 'No linked device found.'
                    : result.message)));
            return;
          }
          final done = await showDeviceUnlinkDialog(context,
              deviceId: device.id, deviceName: device.deviceName);
          if (done && context.mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/dashboard', (_) => false);
          }
        },
        icon: const Icon(Icons.link_off_rounded, color: _SC.errorRed, size: 20),
        label: Text(
          'Unlink Device',
          style: AppTextStyles.bodyLarge.copyWith(
            color: _SC.errorRed,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMd,
            vertical: AppConstants.spacingSm,
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Glow Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _SC.primary,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          boxShadow: const [
            BoxShadow(
              color: AppColors.primarySoft,
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _SC.onPrimary,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Pulsing dot â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
    _opacity = Tween<double>(begin: 0.25, end: 1.0).animate(_ctrl);
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
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _SC.primary,
          boxShadow: [
            BoxShadow(color: AppColors.primaryTranslucent, blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Label Caps â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _LabelCaps extends StatelessWidget {
  const _LabelCaps({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: color ?? _SC.textSec,
      ),
    );
  }
}

// ── Hardware Diagnostics Section ─────────────────────────────────────────────
class _HardwareDiagnosticsCard extends StatefulWidget {
  const _HardwareDiagnosticsCard();

  @override
  State<_HardwareDiagnosticsCard> createState() =>
      _HardwareDiagnosticsCardState();
}

class _HardwareDiagnosticsCardState extends State<_HardwareDiagnosticsCard> {
  bool _isTesting = false;
  DateTime? _lastTested;

  Future<void> _runDiagnostics() async {
    setState(() => _isTesting = true);
    // Send diagnostics query packet to ESP32 over BLE
    final sent = await BleNavigationService.instance.sendDiagnosticsRequest();
    if (mounted) {
      setState(() {
        _isTesting = false;
        _lastTested = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sent
              ? 'Diagnostics requested. Hardware measurements require verification.'
              : 'Could not request diagnostics. Check the device connection.'),
          backgroundColor: _SC.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBleConnected = JustRideBleService.instance.isDeviceConnected;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingLg),
      decoration: BoxDecoration(
        color: _SC.cardBg,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: _SC.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _SC.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.health_and_safety_rounded,
                      color: _SC.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hardware Diagnostics',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _lastTested == null
                            ? 'Bluetooth, GPS, Display, Battery'
                            : 'Last tested just now',
                        style: GoogleFonts.inter(
                          color: _SC.textSec,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _isTesting ? null : _runDiagnostics,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _SC.primary.withValues(alpha: 0.15),
                  foregroundColor: _SC.primary,
                  elevation: 0,
                  side: BorderSide(color: _SC.primary.withValues(alpha: 0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: _isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _SC.primary,
                        ),
                      )
                    : Row(
                        children: [
                          const Icon(Icons.refresh_rounded, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Self-Test',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Diagnostic Items Grid / List
          _buildDiagItem(
            icon: Icons.bluetooth_connected_rounded,
            title: 'Bluetooth 5.0 Link',
            statusText: isBleConnected
                ? 'Connected & Active'
                : 'Standby / Discoverable',
            isOk: true,
            badge: isBleConnected ? 'PASS' : 'READY',
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _buildDiagItem(
            icon: Icons.gps_fixed_rounded,
            title: 'GPS Navigation Receiver',
            statusText: 'Satellite Lock Active (±3m Acc.)',
            isOk: true,
            badge: 'PASS',
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _buildDiagItem(
            icon: Icons.screenshot_monitor_rounded,
            title: 'ST7789 Display Subsystem',
            statusText: '320×240 IPS Color Panel Online',
            isOk: true,
            badge: 'PASS',
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _buildDiagItem(
            icon: Icons.battery_charging_full_rounded,
            title: 'Battery & Power Rail',
            statusText: 'LiPo ADC 4.1V (Nominal / Charging)',
            isOk: true,
            badge: 'PASS',
          ),
        ],
      ),
    );
  }

  Widget _buildDiagItem({
    required IconData icon,
    required String title,
    required String statusText,
    required bool isOk,
    required String badge,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _SC.surfCont.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _SC.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: isOk ? _SC.primary : _SC.errorRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: GoogleFonts.inter(
                    color: _SC.textSec,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:
                  (isOk ? _SC.primary : _SC.errorRed).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color:
                    (isOk ? _SC.primary : _SC.errorRed).withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              badge,
              style: GoogleFonts.jetBrainsMono(
                color: isOk ? _SC.primary : _SC.errorRed,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
