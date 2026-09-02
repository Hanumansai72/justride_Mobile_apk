import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const surfCont = Color(0xFF142226);
  static const primary = Color(0xFF4BE277);
  static const onPrimary = Color(0xFF003915);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
  static const outlineVariant = Color(0xFF3D4A3D);
  static const tertiary = Color(0xFF7CD0FF);
  static const error = Color(0xFFFF5252);
}

class DevicePairingScreen extends StatefulWidget {
  final bool showBottomNav;

  const DevicePairingScreen({super.key, this.showBottomNav = true});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen>
    with TickerProviderStateMixin {
  final JustRideBleService _bleService = JustRideBleService.instance;
  String? _connectingDeviceId;

  // Rotating scanner line
  late final AnimationController _rotateCtrl;

  // 3 radar pulse rings with staggered delays
  late final AnimationController _ring1Ctrl;
  late final AnimationController _ring2Ctrl;
  late final AnimationController _ring3Ctrl;

  @override
  void initState() {
    super.initState();

    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _ring1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _ring2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _ring2Ctrl.repeat(reverse: true);
    });

    _ring3Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _ring3Ctrl.repeat(reverse: true);
    });

    // Initialize BLE and start real-time scan for JustRide devices
    _bleService.init();
    _startScanning();
  }

  void _startScanning() {
    _bleService.startJustRideScan();
  }

  @override
  void dispose() {
    _rotateCtrl.dispose();
    _ring1Ctrl.dispose();
    _ring2Ctrl.dispose();
    _ring3Ctrl.dispose();
    _bleService.dispose();
    super.dispose();
  }

  Future<void> _connectToDiscoveredDevice(ScanResult result) async {
    final devId = result.device.remoteId.str;
    final devName = JustRideBleService.getDeviceName(result);

    setState(() => _connectingDeviceId = devId);

    // ── Step 1: Backend pre-check ──────────────────────────────────────────
    // Verify this device is registered in JustRide backend & claimable.
    final checkRes = await BackendService.instance.checkDeviceAccess(
      bleAddress: devId,
      deviceId: devId,
    );

    if (!mounted) return;

    // If check fails or device is not available, show error and abort
    if (!checkRes.success) {
      final reason = checkRes.errors?['reason'] as String? ?? '';
      String errorMsg;
      switch (reason) {
        case 'DEVICE_NOT_REGISTERED':
          errorMsg = 'This JustRide device is not registered in the system.';
        case 'DEVICE_BLOCKED':
          errorMsg = 'This device is blocked and cannot be paired.';
        case 'DEVICE_PAIRED_TO_ANOTHER_USER':
          errorMsg = 'This device is already paired to another account.';
        case 'USER_ALREADY_HAS_PAIRED_DEVICE':
          errorMsg = 'You already have a paired device. Unlink it first.';
        default:
          errorMsg = checkRes.message.isNotEmpty
              ? checkRes.message
              : 'Device is not available for pairing.';
      }
      setState(() => _connectingDeviceId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _C.error,
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    errorMsg,
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    // ── Step 2: Backend official pairing (only if not already paired) ──
    final accessReason = checkRes.data?['reason']?.toString() ?? '';
    if (accessReason != 'ALREADY_PAIRED_TO_YOU') {
      final pairRes = await BackendService.instance.pairDevice(
        bleAddress: devId,
        deviceName: devName.isNotEmpty ? devName : 'JustRide Module',
        deviceId: devId,
      );

      if (!mounted) return;

      if (!pairRes.success) {
        setState(() => _connectingDeviceId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _C.error,
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Backend pairing failed: ',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        return;
      }
    }

    // ── Step 3: BLE connect + real-time clock sync ─────────────────────────
    // Only proceed with BLE after backend confirms the pairing.
    final connected = await _bleService.connectDevice(result.device);

    if (!mounted) return;

    setState(() => _connectingDeviceId = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _C.primary,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _C.onPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                connected
                    ? 'Paired & synced! $devName is connected.'
                    : 'Paired on server. BLE connect failed — try again.',
                style: GoogleFonts.inter(
                  color: _C.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Navigator.of(context).pushReplacementNamed('/device');
  }

  void _openManualPairingDialog() {
    final idCtrl = TextEditingController(text: 'JR-');
    final pinCtrl = TextEditingController(text: '1234');
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _C.surfCont,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _C.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Enter JustRide Device ID',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _C.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find the serial number on your JustRide HUD hardware or packaging.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _C.textSec,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: idCtrl,
                  style: GoogleFonts.jetBrainsMono(color: _C.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Device ID',
                    labelStyle: GoogleFonts.inter(color: _C.textSec),
                    prefixIcon: const Icon(Icons.qr_code_rounded, color: _C.primary),
                    filled: true,
                    fillColor: _C.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _C.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _C.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  style: GoogleFonts.jetBrainsMono(color: _C.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Pairing PIN (Default: 1234)',
                    labelStyle: GoogleFonts.inter(color: _C.textSec),
                    prefixIcon: const Icon(Icons.pin_rounded, color: _C.primary),
                    filled: true,
                    fillColor: _C.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _C.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _C.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final code = idCtrl.text.trim();
                            if (code.isEmpty) return;
                            setSheetState(() => isSubmitting = true);

                            // Step 1: backend check
                            final checkRes = await BackendService.instance.checkDeviceAccess(
                              bleAddress: code,
                              deviceId: code,
                            );

                            if (!checkRes.success) {
                              setSheetState(() => isSubmitting = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    backgroundColor: _C.error,
                                    content: Text(
                                      checkRes.message.isNotEmpty
                                          ? checkRes.message
                                          : 'Device not available for pairing.',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            // Step 2: backend official pair
                            final pairRes = await BackendService.instance.pairDevice(
                              bleAddress: code,
                              deviceName: 'JustRide HUD',
                              deviceId: code,
                            );

                            if (!pairRes.success) {
                              setSheetState(() => isSubmitting = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    backgroundColor: _C.error,
                                    content: Text(
                                      'Pairing failed: ${pairRes.message}',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: _C.primary,
                                  content: Text(
                                    'JustRide device paired successfully!',
                                    style: TextStyle(color: _C.onPrimary),
                                  ),
                                ),
                              );
                              Navigator.of(context).pushReplacementNamed('/device');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primary,
                      foregroundColor: _C.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _C.onPrimary,
                            ),
                          )
                        : Text(
                            'Pair Device',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _buildBody(),
      bottomNavigationBar: widget.showBottomNav
          ? JustRideBottomNavBar(
              currentIndex: 0,
              onTap: (i) {
                if (i == 0) return;
                if (i == 1) {
                  Navigator.of(context).pushReplacementNamed('/places');
                } else if (i == 2) {
                  Navigator.of(context).pushReplacementNamed('/device');
                } else if (i == 3) {
                  Navigator.of(context).pushReplacementNamed('/profile');
                }
              },
            )
          : null,
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (canPop)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      color: _C.textSec, size: 24),
                )
              else
                IconButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/notifications'),
                  icon: const Icon(Icons.notifications_outlined,
                      color: _C.textSec, size: 24),
                ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
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

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pagePadding,
        vertical: AppConstants.spacingLg,
      ),
      child: Column(
        children: [
          // ── Bluetooth Disabled Warning Banner ──────────────────────────
          ValueListenableBuilder<BluetoothAdapterState>(
            valueListenable: _bleService.adapterStateNotifier,
            builder: (context, adapterState, _) {
              if (adapterState == BluetoothAdapterState.off) {
                return Container(
                  margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  decoration: BoxDecoration(
                    color: _C.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(color: _C.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_disabled_rounded,
                          color: _C.error, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bluetooth is Turned Off',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Enable Bluetooth to discover JustRide devices.',
                              style: GoogleFonts.inter(
                                color: _C.textSec,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _bleService.turnOnBluetooth(),
                        style: TextButton.styleFrom(
                          backgroundColor: _C.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Turn On',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // ── Header ──────────────────────────────────────────────────────
          Text(
            'Connect Your JustRide',
            style: AppTextStyles.headingLarge.copyWith(
              fontSize: 24,
              color: _C.onSurface,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingSm),

          // ── Live Scanning Indicator Subtitle ────────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: _bleService.isScanningNotifier,
            builder: (context, isScanning, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isScanning ? _C.primary : _C.textSec,
                      boxShadow: isScanning
                          ? [
                              BoxShadow(
                                color: _C.primary.withValues(alpha: 0.8),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isScanning
                        ? 'Scanning for JustRide devices in real time...'
                        : 'Scan paused. Tap radar to rescan.',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: isScanning ? _C.primary : _C.textSec,
                      fontSize: 14,
                      fontWeight:
                          isScanning ? FontWeight.w600 : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // ── Radar Scanner ──────────────────────────────────────────────
          GestureDetector(
            onTap: _startScanning,
            child: _buildRadar(),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // ── Filter Notice Badge ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _C.surfCont,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_alt_outlined,
                    color: _C.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Filtering ONLY "JustRide" Bluetooth devices',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: _C.textSec,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // ── Real-Time Detected JustRide Device(s) List ───────────────────
          ValueListenableBuilder<List<ScanResult>>(
            valueListenable: _bleService.justRideDevicesNotifier,
            builder: (context, discoveredDevices, _) {
              if (discoveredDevices.isEmpty) {
                return _buildEmptyState();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 4, bottom: AppConstants.spacingSm),
                    child: Text(
                      'Discovered Devices (${discoveredDevices.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _C.primary,
                      ),
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: discoveredDevices.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppConstants.spacingMd),
                    itemBuilder: (context, index) {
                      return _buildDeviceCard(discoveredDevices[index]);
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // ── Manual Entry Option ─────────────────────────────────────────
          GestureDetector(
            onTap: _openManualPairingDialog,
            child: Text(
              'Enter Device ID Manually',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: _C.tertiary,
                decoration: TextDecoration.underline,
                decorationColor: _C.tertiary,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSection),
        ],
      ),
    );
  }

  // ── Empty State when no JustRide device has appeared yet ────────────────────
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _C.surfCont,
        border: Border.all(color: _C.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      padding: const EdgeInsets.all(AppConstants.spacingLg),
      child: Column(
        children: [
          Icon(Icons.radar_rounded,
              color: _C.primary.withValues(alpha: 0.6), size: 40),
          const SizedBox(height: 12),
          Text(
            'Searching for JustRide Devices...',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _C.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ensure your JustRide HUD or module is turned on and within 10 meters. Other nearby Bluetooth devices are automatically filtered out.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _C.textSec,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: _bleService.isScanningNotifier,
            builder: (context, isScanning, _) {
              return OutlinedButton.icon(
                onPressed: _startScanning,
                icon: Icon(
                  isScanning ? Icons.sync : Icons.refresh_rounded,
                  size: 16,
                  color: _C.primary,
                ),
                label: Text(
                  isScanning ? 'Scanning...' : 'Rescan Now',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _C.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Radar ──────────────────────────────────────────────────────────────────
  Widget _buildRadar() {
    const size = 230.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring 1 (20% opacity base, pulses)
          _RadarRing(controller: _ring1Ctrl, baseOpacity: 0.20),
          // Ring 2 (40% opacity base, staggered)
          _RadarRing(controller: _ring2Ctrl, baseOpacity: 0.40),
          // Ring 3 (60% opacity base, staggered)
          _RadarRing(controller: _ring3Ctrl, baseOpacity: 0.60),

          // Rotating scanner arc
          AnimatedBuilder(
            animation: _rotateCtrl,
            builder: (_, __) => Transform.rotate(
              angle: _rotateCtrl.value * 2 * math.pi,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _C.primary.withValues(alpha: 0.0),
                  ),
                ),
                child: CustomPaint(
                  painter: _ScannerLinePainter(),
                ),
              ),
            ),
          ),

          // Central Bluetooth core
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.surfCont,
              border: Border.all(color: _C.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: _C.primary.withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.bluetooth_searching_rounded,
                color: _C.primary, size: 36),
          ),
        ],
      ),
    );
  }

  // ── Detected JustRide Device Card ──────────────────────────────────────────
  Widget _buildDeviceCard(ScanResult result) {
    final devName = JustRideBleService.getDeviceName(result);
    final devId = result.device.remoteId.str;
    final signalInfo = JustRideBleService.getSignalInfo(result.rssi);
    final isConnecting = _connectingDeviceId == devId;

    return Container(
      decoration: BoxDecoration(
        color: _C.surfCont,
        border: Border.all(color: _C.primary.withValues(alpha: 0.6), width: 1.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        boxShadow: [
          BoxShadow(
            color: _C.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        children: [
          // Title + signal
          Container(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _C.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _C.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.two_wheeler_rounded,
                            color: _C.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          devName.isNotEmpty ? devName : 'JustRide Module',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _C.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      signalInfo.$2 == 3
                          ? Icons.signal_cellular_alt_rounded
                          : signalInfo.$2 == 2
                              ? Icons.signal_cellular_alt_2_bar_rounded
                              : Icons.signal_cellular_alt_1_bar_rounded,
                      color: _C.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${signalInfo.$1} (${result.rssi} dBm)',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _C.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // ID + Status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DEVICE MAC / ID',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _C.textSec,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    devId,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.onSurface,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'STATUS',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _C.textSec,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConnecting ? 'Connecting...' : 'Ready to Pair',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isConnecting ? _C.tertiary : _C.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Connect button
          _ConnectButton(
            isLoading: isConnecting,
            onTap: () => _connectToDiscoveredDevice(result),
          ),
        ],
      ),
    );
  }
}

// ── Radar Ring ─────────────────────────────────────────────────────────────────
class _RadarRing extends StatelessWidget {
  const _RadarRing({
    required this.controller,
    required this.baseOpacity,
  });
  final AnimationController controller;
  final double baseOpacity;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        final scale = 1.0 + 0.5 * t;
        final opacity = baseOpacity * (1.0 - t) + 0.2 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _C.primary.withValues(alpha: opacity),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Scanner Line Painter ───────────────────────────────────────────────────────
class _ScannerLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF4BE277).withValues(alpha: 0.0),
          const Color(0xFF4BE277).withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 1),
      -math.pi / 2,
      0.01,
      false,
      paint,
    );

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF4BE277).withValues(alpha: 0.4),
        ],
      ).createShader(Rect.fromPoints(center, Offset(size.width / 2, 0)))
      ..strokeWidth = 1.5;
    canvas.drawLine(center, Offset(size.width / 2, 0), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Connect Button ─────────────────────────────────────────────────────────────
class _ConnectButton extends StatefulWidget {
  const _ConnectButton({
    required this.onTap,
    this.isLoading = false,
  });
  final VoidCallback onTap;
  final bool isLoading;

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isLoading ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.isLoading
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppConstants.animFast,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _C.primary,
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _C.onPrimary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bluetooth_connected_rounded,
                        color: _C.onPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Connect JustRide',
                      style: GoogleFonts.inter(
                        fontSize: 16,
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
