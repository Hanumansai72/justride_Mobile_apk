import '../../../app/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/services/bluetooth_service.dart';
import 'package:geolocator/geolocator.dart';
import '../../../shared/widgets/hardware_prompt_sheet.dart';
import '../../../shared/widgets/app_logo.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const surfCont = AppColors.surface;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const textSec = AppColors.textSecondary;
  static const outlineVariant = AppColors.border;
}

class DevicePairingScreen extends StatefulWidget {
  final bool showBottomNav;

  const DevicePairingScreen({super.key, this.showBottomNav = true});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  final JustRideBleService _bleService = JustRideBleService.instance;
  String? _connectingDeviceId;
  final Map<String, String> _registeredNames = {};
  final Set<String> _lookedUpAddresses = {};
  bool _resolvingNames = false;

  String _deviceName(ScanResult result) =>
      _registeredNames[result.device.remoteId.str.toUpperCase()] ??
      JustRideBleService.getDeviceName(result);

  Future<void> _resolveDeviceNames() async {
    if (_resolvingNames || !mounted) return;
    final addresses = _bleService.justRideDevicesNotifier.value
        .map((result) => result.device.remoteId.str.toUpperCase())
        .where((address) =>
            RegExp(r'^(?:[A-F0-9]{2}:){5}[A-F0-9]{2}$').hasMatch(address) &&
            !_lookedUpAddresses.contains(address))
        .take(30)
        .toList();
    if (addresses.isEmpty) return;
    _lookedUpAddresses.addAll(addresses);
    _resolvingNames = true;
    try {
      final response =
          await BackendService.instance.getScanDeviceDetails(addresses);
      if (!mounted) return;
      if (response.success) {
        setState(() {
          for (final device in response.data ?? []) {
            final address = device['BLE_ADDRESS']?.toString().toUpperCase();
            final name =
                (device['device_type'] ?? device['devicename'])?.toString();
            if (address != null && name != null && name.isNotEmpty) {
              _registeredNames[address] = name;
            }
          }
        });
      }
    } finally {
      _resolvingNames = false;
      if (mounted) _resolveDeviceNames();
    }
  }

  Future<String> _readSetupCredential(BluetoothDevice device) async {
    var services = device.servicesList;
    for (var attempt = 0; attempt < 2; attempt++) {
      for (final service in services) {
        if (service.uuid != Guid('ff40')) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid != Guid('ff42')) continue;
          try {
            final bytes = await characteristic.read();
            final code = String.fromCharCodes(bytes);
            if (RegExp(r'^[A-F0-9]{32}$').hasMatch(code)) return code;
          } catch (_) {
            throw StateError(
                'Could not read device setup over Bluetooth. Reconnect and confirm the pairing code, then retry.');
          }
          throw StateError(
              'The display returned incomplete setup data. Contact your device administrator.');
        }
      }
      if (attempt == 0) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          await device.clearGattCache();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        services = await device.discoverServices();
      }
    }
    throw StateError(
        'The display setup service is unavailable. Update the firmware, forget the old Bluetooth pairing, and reconnect.');
  }

  @override
  void initState() {
    super.initState();

    // Pairing keeps fast discovery; idle reconnects can back off.
    _bleService.setPairingScanActive(true);
    _bleService.init();
    _bleService.justRideDevicesNotifier.addListener(_resolveDeviceNames);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      if (!kIsWeb) _startScanning();
      _checkHardwareIfOff();
    });
  }

  Future<void> _checkHardwareIfOff() async {
    if (kIsWeb) return;
    final btState = _bleService.adapterStateNotifier.value;
    final isGpsOn = await Geolocator.isLocationServiceEnabled();
    if (btState == BluetoothAdapterState.off || !isGpsOn) {
      if (mounted) {
        HardwarePromptSheet.show(
          context,
          btOff: btState != BluetoothAdapterState.on,
          gpsOff: !isGpsOn,
        );
      }
    }
  }

  void _startScanning() {
    _lookedUpAddresses.clear();
    _resolveDeviceNames();
    _bleService.startJustRideScan();
  }

  @override
  void dispose() {
    _bleService.setPairingScanActive(false);
    _bleService.justRideDevicesNotifier.removeListener(_resolveDeviceNames);
    // Do NOT dispose _bleService singleton here!
    // Disposing the singleton drops active BLE connections app-wide when navigating away.
    super.dispose();
  }

  Future<void> _connectToDiscoveredDevice(ScanResult result) async {
    if (_connectingDeviceId != null) return;
    final devId = result.device.remoteId.str;
    final devName = _deviceName(result);

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
            backgroundColor: AppColors.error,
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: AppColors.textPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    errorMsg,
                    style: const TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    final secureConnected = await _bleService.connectDevice(result.device);
    if (!mounted) return;
    if (!secureConnected) {
      setState(() => _connectingDeviceId = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not connect. Confirm the Bluetooth code on your display and try again.')));
      return;
    }
    // Link the account only after authenticated Bluetooth pairing.
    final accessReason = checkRes.data?['reason']?.toString() ?? '';
    if (accessReason != 'ALREADY_PAIRED_TO_YOU') {
      late final String setupCode;
      try {
        setupCode = await _readSetupCredential(result.device);
      } catch (error) {
        if (!mounted) return;
        setState(() => _connectingDeviceId = null);
        await _bleService.disconnectDevice(restartScan: false);
        final message = error is StateError
            ? error.message.toString()
            : 'Could not refresh the Bluetooth connection. Reconnect the display and retry.';
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }
      if (!mounted) return;
      final pairRes = await BackendService.instance.pairDevice(
        bleAddress: devId,
        setupCode: setupCode,
        deviceName: devName.isNotEmpty ? devName : 'JustRide Module',
        deviceId: devId,
      );

      if (!pairRes.success) {
        await _bleService.disconnectDevice(restartScan: false);
        if (!mounted) return;
        setState(() => _connectingDeviceId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: AppColors.textPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pairRes.message.isNotEmpty
                        ? pairRes.message
                        : 'Could not link this display. Try again.',
                    style: const TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textPrimary),
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
        backgroundColor: AppColors.primaryContainer,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _C.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                connected
                    ? 'Display connected.'
                    : 'Device paired. Unable to connect right now. Please try again.',
                style: const TextStyle(
                  fontFamily: 'Stack Sans Text',
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (connected) Navigator.of(context).pushReplacementNamed('/device');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _buildBody(),
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
              if (!widget.showBottomNav)
                const SizedBox(width: 48)
              else if (canPop)
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
              if (widget.showBottomNav)
                IconButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/profile-settings'),
                  icon: const Icon(Icons.settings_outlined,
                      color: _C.textSec, size: 24),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      top: false,
      child: LayoutBuilder(builder: (context, constraints) {
        final visualSize = constraints.maxHeight < 660 ? 128.0 : 176.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        _bleService.isScanningNotifier,
                        _bleService.justRideDevicesNotifier,
                        _bleService.adapterStateNotifier,
                      ]),
                      builder: (context, _) {
                        final enabled =
                            _bleService.adapterStateNotifier.value ==
                                BluetoothAdapterState.on;
                        return _DiscoveryVisual(
                          size: visualSize,
                          scanning:
                              enabled && _bleService.isScanningNotifier.value,
                          detected: enabled &&
                              _bleService
                                  .justRideDevicesNotifier.value.isNotEmpty,
                          enabled: enabled,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Connect your display',
                      style: AppTextStyles.headingLarge.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                      )),
                  const SizedBox(height: 8),
                  Text('Turn on your JustRide and keep it nearby.',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: _C.textSec,
                        height: 1.5,
                      )),
                  const SizedBox(height: 28),
                  ValueListenableBuilder<BluetoothAdapterState>(
                    valueListenable: _bleService.adapterStateNotifier,
                    builder: (context, adapter, _) {
                      final bluetoothOff = adapter == BluetoothAdapterState.off;
                      if (bluetoothOff) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _C.surfCont,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _C.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.bluetooth_disabled_rounded,
                                  color: _C.textSec, size: 28),
                              const SizedBox(height: 12),
                              Text('Bluetooth is off',
                                  style: AppTextStyles.headingMedium),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: () =>
                                      _bleService.turnOnBluetooth(),
                                  style: _connectStyle,
                                  child: const Text('Turn on Bluetooth'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ValueListenableBuilder<bool>(
                        valueListenable: _bleService.isScanningNotifier,
                        builder: (context, scanning, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('Nearby displays',
                                        style: AppTextStyles.headingSmall),
                                  ),
                                  if (scanning) ...[
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: _C.primary),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Searching',
                                        style: AppTextStyles.bodySmall),
                                  ] else
                                    TextButton.icon(
                                      onPressed: _connectingDeviceId == null
                                          ? _startScanning
                                          : null,
                                      style: TextButton.styleFrom(
                                        foregroundColor: _C.primary,
                                        minimumSize: const Size(48, 48),
                                      ),
                                      icon: const Icon(Icons.refresh_rounded,
                                          size: 18),
                                      label: const Text('Scan again'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ValueListenableBuilder<List<ScanResult>>(
                                valueListenable:
                                    _bleService.justRideDevicesNotifier,
                                builder: (context, devices, _) {
                                  if (devices.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 24),
                                      child: Row(
                                        children: [
                                          const Icon(
                                              Icons.bluetooth_searching_rounded,
                                              color: _C.textSec,
                                              size: 28),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              scanning
                                                  ? 'Looking for your display…'
                                                  : 'No display found. Move closer and scan again.',
                                              style: AppTextStyles.bodyMedium
                                                  .copyWith(height: 1.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Column(
                                    children: [
                                      for (final device in devices)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _buildDeviceCard(device),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  ButtonStyle get _connectStyle => FilledButton.styleFrom(
        backgroundColor: _C.primary,
        foregroundColor: _C.onPrimary,
        disabledBackgroundColor: AppColors.primaryContainer,
        disabledForegroundColor: _C.textSec,
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: AppTextStyles.labelLarge.copyWith(fontSize: 16),
      );

  Widget _buildDeviceCard(ScanResult result) {
    final name = _deviceName(result);
    final connecting = _connectingDeviceId == result.device.remoteId.str;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surfCont,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded,
                    color: _C.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(name.isNotEmpty ? name : 'JustRide display',
                    style: AppTextStyles.headingMedium, softWrap: true),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _connectingDeviceId == null
                  ? () => _connectToDiscoveredDevice(result)
                  : null,
              style: _connectStyle,
              child: connecting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _C.textSec,
                            semanticsLabel: 'Connecting to display',
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Connecting…'),
                      ],
                    )
                  : const Text('Connect display'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Only animates during a live scan; detection replaces search with the display icon.
class _DiscoveryVisual extends StatelessWidget {
  const _DiscoveryVisual(
      {required this.size,
      required this.scanning,
      required this.detected,
      required this.enabled});

  final double size;
  final bool scanning, detected, enabled;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = scanning && !detected;
    return Semantics(
      label: detected
          ? 'Display found'
          : active
              ? 'Searching for displays'
              : enabled
                  ? 'Scan paused'
                  : 'Bluetooth is off',
      liveRegion: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final scale in [1.0, 0.76])
              Container(
                width: size * scale,
                height: size * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: detected
                          ? _C.primary.withValues(alpha: 0.3)
                          : _C.outlineVariant),
                ),
              ),
            if (active)
              SizedBox.square(
                dimension: size,
                child: CircularProgressIndicator(
                  value: reduceMotion ? 1 : null,
                  strokeWidth: 2,
                  color: _C.primary,
                ),
              ),
            Container(
              width: size * 0.52,
              height: size * 0.52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: detected ? AppColors.primaryContainer : _C.surfCont,
                border: Border.all(color: _C.outlineVariant),
              ),
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduceMotion ? 0 : 220),
                child: Icon(
                  detected
                      ? Icons.navigation_rounded
                      : enabled
                          ? Icons.bluetooth_searching_rounded
                          : Icons.bluetooth_disabled_rounded,
                  key: ValueKey((detected, enabled)),
                  color: enabled ? _C.primary : _C.textSec,
                  size: size * 0.23,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
