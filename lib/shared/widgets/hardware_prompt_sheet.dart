import '../../app/theme/app_colors.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/bluetooth_service.dart';

/// Modal bottom sheet / dialog prompting user to turn on Bluetooth and/or Location (GPS)
/// when disabled, with one-tap action buttons and auto-dismissal as soon as hardware is enabled.
class HardwarePromptSheet extends StatefulWidget {
  final bool initialBtOff;
  final bool initialGpsOff;

  const HardwarePromptSheet({
    super.key,
    required this.initialBtOff,
    required this.initialGpsOff,
  });

  /// Shows the dialog if Bluetooth or GPS is disabled. Returns true when user continues or auto-resolved.
  static Future<bool?> show(
    BuildContext context, {
    required bool btOff,
    required bool gpsOff,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => HardwarePromptSheet(
        initialBtOff: btOff,
        initialGpsOff: gpsOff,
      ),
    );
  }

  @override
  State<HardwarePromptSheet> createState() => _HardwarePromptSheetState();
}

class _HardwarePromptSheetState extends State<HardwarePromptSheet>
    with WidgetsBindingObserver {
  late bool _btOff;
  late bool _gpsOff;
  bool _isEnablingBt = false;
  bool _isCheckingGps = false;

  StreamSubscription<BluetoothAdapterState>? _btSub;
  StreamSubscription<ServiceStatus>? _locStatusSub;
  Timer? _periodicCheckTimer;

  // Obsidian & Emerald theme colors
  static const Color _bg = AppColors.backgroundInset;
  static const Color _card = AppColors.surface;
  static const Color _border = AppColors.border;
  static const Color _primary = AppColors.primary;
  static const Color _onPrimary = AppColors.onPrimary;
  static const Color _warning = AppColors.warning;
  static const Color _textPrimary = AppColors.textPrimary;
  static const Color _textSecondary = AppColors.textSecondary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _btOff = widget.initialBtOff;
    _gpsOff = widget.initialGpsOff;

    // Listen to real-time Bluetooth adapter state changes
    _btSub = JustRideBleService.instance.adapterStateNotifier.addListener(() {
      final state = JustRideBleService.instance.adapterStateNotifier.value;
      final isOff = state != BluetoothAdapterState.on;
      if (mounted && _btOff != isOff) {
        setState(() {
          _btOff = isOff;
          if (!isOff) _isEnablingBt = false;
        });
        _checkAllResolved();
      }
    }) as StreamSubscription<BluetoothAdapterState>?;

    // Listen to Location Service status stream from geolocator
    _locStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      final isGpsOff = status == ServiceStatus.disabled;
      if (mounted && _gpsOff != isGpsOff) {
        setState(() {
          _gpsOff = isGpsOff;
          if (!isGpsOff) _isCheckingGps = false;
        });
        _checkAllResolved();
      }
    });

    // Check immediately upon opening
    _refreshHardwareStates();

    // Periodic safety poll every 1.5s while sheet is open (e.g. when user toggles quick-settings)
    _periodicCheckTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _refreshHardwareStates();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHardwareStates();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _btSub?.cancel();
    _locStatusSub?.cancel();
    _periodicCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshHardwareStates() async {
    if (!mounted) return;
    try {
      final btState = await FlutterBluePlus.adapterState.first;
      final isBtOff = btState != BluetoothAdapterState.on;

      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      final isGpsOff = !isGpsEnabled;

      if (mounted) {
        if (_btOff != isBtOff || _gpsOff != isGpsOff) {
          setState(() {
            _btOff = isBtOff;
            _gpsOff = isGpsOff;
          });
          _checkAllResolved();
        }
      }
    } catch (e) {
      debugPrint('[HardwarePromptSheet] state check error: $e');
    }
  }

  void _checkAllResolved() {
    if (!_btOff && !_gpsOff && mounted) {
      // Auto close and continue with the app seamlessly!
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      });
    }
  }

  Future<void> _enableBluetooth() async {
    setState(() => _isEnablingBt = true);
    try {
      await JustRideBleService.instance.turnOnBluetooth();
    } catch (e) {
      debugPrint('[HardwarePromptSheet] Enable BT error: $e');
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 600));
        _refreshHardwareStates();
      }
    }
  }

  Future<void> _enableGps() async {
    setState(() => _isCheckingGps = true);
    try {
      await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('[HardwarePromptSheet] Open location settings error: $e');
    } finally {
      if (mounted) {
        setState(() => _isCheckingGps = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allResolved = !_btOff && !_gpsOff;

    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header Title & Icon
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: allResolved
                      ? _primary.withValues(alpha: 0.15)
                      : _warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: allResolved ? _primary : _warning,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  allResolved
                      ? Icons.check_circle_rounded
                      : Icons.perm_device_information_rounded,
                  color: allResolved ? _primary : _warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allResolved
                          ? 'All Services Connected'
                          : 'Enable Services to Continue',
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allResolved
                          ? 'Bluetooth and GPS are active. Resuming JustRide...'
                          : 'Turn on Bluetooth and GPS for live HUD & navigation.',
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: _textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Bluetooth Item
          _buildServiceCard(
            title: 'Bluetooth',
            description: _btOff
                ? 'Required to connect to your JustRide device.'
                : 'Bluetooth is connected and ready.',
            isOff: _btOff,
            isLoading: _isEnablingBt,
            icon: Icons.bluetooth_rounded,
            actionLabel: 'Turn On',
            onAction: _enableBluetooth,
          ),

          const SizedBox(height: 12),

          // GPS / Location Item
          _buildServiceCard(
            title: 'GPS Location',
            description: _gpsOff
                ? 'Required for turn-by-turn navigation & live speed.'
                : 'GPS Location is active.',
            isOff: _gpsOff,
            isLoading: _isCheckingGps,
            icon: Icons.location_on_rounded,
            actionLabel: 'Turn On',
            onAction: _enableGps,
          ),

          const SizedBox(height: 24),

          // Action Button: Continue / Done
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: _onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  allResolved ? 'Continue with App' : 'Dismiss & Continue',
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required String title,
    required String description,
    required bool isOff,
    required bool isLoading,
    required IconData icon,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final statusColor = isOff ? _warning : _primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: isOff ? _border : _primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isOff ? 'OFF' : 'ON',
                        style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    color: _textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isOff)
            ElevatedButton(
              onPressed: isLoading ? null : onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: _onPrimary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _onPrimary,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            )
          else
            const Icon(Icons.check_circle_rounded, color: _primary, size: 24),
        ],
      ),
    );
  }
}
