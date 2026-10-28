import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Senior-Grade Real-Time Bluetooth Service for JustRide HUD and IoT hardware.
/// - Continuously re-scans for JustRide devices.
/// - Strictly filters: ONLY devices with "justride" in their name are shown.
/// - On connect: writes the full local calendar and clock to GATT CTS (0x1805 / 0x2A2B).
/// - On disconnect / device reset: detects disconnection, cancels timers, clears state,
///   and immediately restarts scanning so the device shows as available again.
/// - Full reconnect support with live status logging.
class JustRideBleService {
  JustRideBleService._();
  static final JustRideBleService instance = JustRideBleService._();

  /// Bluetooth SIG Current Time: year LE, date, clock, weekday, fraction, reason.
  @visibleForTesting
  static List<int> encodeCurrentTime(DateTime now) => [
        now.year & 0xff,
        (now.year >> 8) & 0xff,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
        now.weekday,
        0,
        1,
      ];

  // ─── Internal state ──────────────────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  Timer? _timeSyncTimer;
  Timer? _rescanTimer;
  BluetoothDevice? _connectedDevice;
  String? _lastConnectedDeviceId;
  bool _autoReconnectEnabled = true;
  bool _isReconnecting = false;
  bool _isSyncingTime = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _startingScan = false;
  Future<bool>? _connectionAttempt;
  String? _connectionTarget;
  // true only when the user explicitly pressed Disconnect – suppresses auto-reconnect
  bool _userInitiatedDisconnect = false;

  static const _companion = MethodChannel('com.justride.app/companion');
  static const _companionSetup =
      MethodChannel('com.justride.app/companion_setup');
  final companionEnabled = ValueNotifier<bool>(false);
  final companionSupported = ValueNotifier<bool>(false);
  final companionError = ValueNotifier<String?>(null);
  bool _companionReady = false, _appVisible = true, _devicePresent = false;
  bool Function() _authenticated = () => false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _mayScan => !_android || (_companionReady && _appVisible);
  bool get isAppVisible => _appVisible;

  Future<void> initializeCompanion(
      {required Future<void> Function() onShowApp,
      required bool Function() authenticated}) async {
    _authenticated = authenticated;
    if (!_android) {
      _companionReady = true;
      return;
    }
    Future<void> apply(Map<dynamic, dynamic> state) async {
      companionEnabled.value = state['enabled'] == true;
      companionSupported.value = state['supported'] == true;
      _appVisible = state['visible'] == true;
      _devicePresent = state['present'] == true;
      _userInitiatedDisconnect = state['paused'] == true;
      _companionReady = true;
      if (_appVisible) await onShowApp();
      if (!_appVisible) await stopScan();
      if (companionEnabled.value &&
          _devicePresent &&
          !_userInitiatedDisconnect &&
          _autoReconnectEnabled &&
          authenticated() &&
          !isDeviceConnected) {
        final address = state['address']?.toString();
        if (address != null && address.isNotEmpty) {
          unawaited(_connectCompanion(address));
        }
      } else if (_appVisible &&
          authenticated() &&
          !isDeviceConnected &&
          !_userInitiatedDisconnect) {
        final address = await loadSavedBleAddress();
        if (address != null &&
            _autoReconnectEnabled &&
            !_userInitiatedDisconnect &&
            authenticated()) {
          unawaited(reconnect(targetBleAddress: address));
        } else {
          unawaited(_startOneScan());
        }
      }
    }

    _companion.setMethodCallHandler((call) async {
      if (call.method == 'state') {
        await apply(Map<dynamic, dynamic>.from(call.arguments as Map));
      }
    });
    try {
      await apply(
          await _companion.invokeMapMethod<dynamic, dynamic>('ready') ?? {});
    } on MissingPluginException {
      // Older installed native shell / unsupported host: foreground BLE still works.
      _companionReady = true;
    } catch (e) {
      companionError.value = 'Background connection setup unavailable';
      _companionReady = true;
    }
  }

  Future<void> _connectCompanion(String address) async {
    if (!_authenticated() ||
        _userInitiatedDisconnect ||
        !companionEnabled.value ||
        !_devicePresent ||
        _disposed ||
        !_autoReconnectEnabled ||
        isDeviceConnected ||
        adapterStateNotifier.value != BluetoothAdapterState.on) {
      return;
    }
    if (_lastConnectedDeviceId == null) await loadSavedBleAddress();
    if (!_authenticated() ||
        _userInitiatedDisconnect ||
        !companionEnabled.value) {
      return;
    }
    if (_normalizeMac(address) != _normalizeMac(_lastConnectedDeviceId ?? '')) {
      return;
    }
    await connectDevice(BluetoothDevice.fromId(address),
        configureCompanion: false);
  }

  Future<bool> enableCompanion({bool prompt = true, String? address}) async {
    if (!_android) return false;
    final target = address ?? await loadSavedBleAddress();
    if (target == null) return false;
    // Existing installs may already have a GATT connection. Android's approval
    // scan needs the device advertising, so briefly release that link first.
    final reconnect = prompt && isDeviceConnected && !companionEnabled.value;
    final device = reconnect ? _connectedDevice : null;
    if (reconnect) await disconnectDevice(restartScan: false);
    try {
      companionError.value = null;
      final state = await _companionSetup.invokeMapMethod<dynamic, dynamic>(
          'enable', {'address': target, 'prompt': prompt});
      companionEnabled.value = state?['enabled'] == true;
      companionSupported.value = state?['supported'] == true;
      return companionEnabled.value;
    } catch (e) {
      companionError.value =
          'Unable to set up background connection. Please try again.';
      return false;
    } finally {
      if (device != null && _authenticated()) {
        await connectDevice(device, configureCompanion: false);
      }
    }
  }

  Future<void> disableCompanion({bool forgetDevice = false}) async {
    _userInitiatedDisconnect = true;
    _devicePresent = false;
    companionEnabled.value = false;
    _cancelRescan();
    if (_android) {
      try {
        await _companion.invokeMethod<void>('disable');
      } catch (_) {}
    }
    if (forgetDevice) _lastConnectedDeviceId = null;
    await disconnectDevice(restartScan: false);
  }

  // ─── JustRide device identity ─────────────────────────────────────────────────
  // Firmware advertises name as 'JUSTRIDE' (all caps). Used for name-based scan filter.
  static const _kDeviceName = 'JUSTRIDE';

  // ─── Public notifiers (drive UI ValueListenableBuilder) ──────────────────────
  final ValueNotifier<List<ScanResult>> justRideDevicesNotifier =
      ValueNotifier<List<ScanResult>>([]);
  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<BluetoothAdapterState> adapterStateNotifier =
      ValueNotifier<BluetoothAdapterState>(BluetoothAdapterState.unknown);
  final ValueNotifier<BluetoothConnectionState> connectionStateNotifier =
      ValueNotifier<BluetoothConnectionState>(
          BluetoothConnectionState.disconnected);

  /// Broadcasts recent BLE error/disconnect diagnostics directly to UI for visibility
  final ValueNotifier<String?> lastBleErrorNotifier =
      ValueNotifier<String?>(null);

  // ─── BLE time sync GATT UUIDs matching firmware ble.c ────────────────────────
  static const String _kCtsServiceUuid = '1805';
  static const String _kCtsCharUuid = '2a2b';

  // ─── Scan configuration ──────────────────────────────────────────────────────
  static const Duration _kScanWindow = Duration(seconds: 15);

  // =========================================================================
  // INIT – call once from screen initState or app startup
  // =========================================================================
  void init() {
    if (_initialized && !_disposed) return;
    _initialized = true;
    _disposed = false;

    // Preload verified saved MAC address from storage for instant recognition
    loadSavedBleAddress();

    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      adapterStateNotifier.value = state;
      if (state == BluetoothAdapterState.off) {
        connectionStateNotifier.value = BluetoothConnectionState.disconnected;
      }
      if (state == BluetoothAdapterState.on &&
          companionEnabled.value &&
          _devicePresent) {
        final address = _lastConnectedDeviceId;
        if (address != null) unawaited(_connectCompanion(address));
      }
      if (!kIsWeb &&
          _mayScan &&
          state == BluetoothAdapterState.on &&
          !FlutterBluePlus.isScanningNow) {
        _startOneScan();
      }
    });

    _isScanSub?.cancel();
    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      isScanningNotifier.value = scanning;
      if (!kIsWeb &&
          _mayScan &&
          !scanning &&
          !_disposed &&
          _connectedDevice == null) {
        // 2s pause between scans prevents Android BLE scan throttling (5 scans per 30s limit)
        _scheduleRescan(delay: const Duration(seconds: 2));
      }
    });
  }

  // =========================================================================
  // PUBLIC: Start continuous JustRide scan
  // =========================================================================
  Future<void> startJustRideScan() async {
    if (_disposed) return;
    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      debugPrint('[BLE] Bluetooth not supported on this device');
      return;
    }
    _cancelRescan();
    await _startOneScan();
  }

  // =========================================================================
  // INTERNAL: Fire one scan window and listen for results
  // =========================================================================
  Future<void> _startOneScan() async {
    if (_disposed ||
        !_mayScan ||
        _connectionAttempt != null ||
        isDeviceConnected ||
        _startingScan ||
        FlutterBluePlus.isScanningNow) {
      return;
    }
    _startingScan = true;
    try {
      await loadSavedBleAddress();
      if (_disposed ||
          !_mayScan ||
          _connectionAttempt != null ||
          isDeviceConnected) return;

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen(
        (results) {
          if (_disposed) return;
          final Map<String, ScanResult> uniqueMap = {};
          for (final r in results) {
            // Accept the device if: (a) name matches 'JUSTRIDE', OR
            // (b) the MAC matches our saved paired device (handles empty advName on Android 12+)
            if (_isJustRideResult(r)) {
              uniqueMap[r.device.remoteId.str] = r;

              // Auto-reconnect if this was our previously connected device
              // BUT ONLY if the user didn't explicitly disconnect
              if (_autoReconnectEnabled &&
                  _authenticated() &&
                  !_userInitiatedDisconnect &&
                  _lastConnectedDeviceId != null &&
                  _normalizeMac(r.device.remoteId.str) ==
                      _normalizeMac(_lastConnectedDeviceId!) &&
                  _connectedDevice == null &&
                  !_isReconnecting) {
                debugPrint(
                    '[BLE] Re-discovered previously paired device ${r.device.remoteId.str}! Auto-reconnecting...');
                _isReconnecting = true;
                connectDevice(r.device, configureCompanion: false).then((_) {
                  _isReconnecting = false;
                });
              }
            }
          }
          final newList = uniqueMap.values.toList();
          if (!_listEquals(justRideDevicesNotifier.value, newList)) {
            justRideDevicesNotifier.value = newList;
          }
        },
        onError: (e) => debugPrint('[BLE] Scan error: $e'),
      );

      try {
        await FlutterBluePlus.startScan(
          withNames: kIsWeb ? [_kDeviceName] : [],
          webOptionalServices: kIsWeb
              ? [Guid('1805'), Guid('180f'), Guid('ff10'), Guid('ff30')]
              : [],
          timeout: _kScanWindow,
          androidUsesFineLocation: false,
        );
      } catch (e) {
        debugPrint('[BLE] startScan error: $e');
      }
    } finally {
      _startingScan = false;
    }
  }

  void _scheduleRescan({Duration delay = const Duration(seconds: 1)}) {
    if (kIsWeb) return;
    if (!_mayScan) {
      _rescanTimer?.cancel();
      final address = _lastConnectedDeviceId;
      if (companionEnabled.value &&
          _devicePresent &&
          address != null &&
          !_userInitiatedDisconnect) {
        _rescanTimer =
            Timer(const Duration(seconds: 5), () => _connectCompanion(address));
      }
      return;
    }
    _rescanTimer?.cancel();
    _rescanTimer = Timer(delay, () {
      if (!_disposed && _connectedDevice == null) _startOneScan();
    });
  }

  void _cancelRescan() {
    _rescanTimer?.cancel();
    _rescanTimer = null;
  }

  Future<void> _safeStopScan() async {
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> stopScan() async {
    _cancelRescan();
    _scanSub?.cancel();
    await _safeStopScan();
    isScanningNotifier.value = false;
  }

  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      debugPrint('[BLE] turnOn error: $e');
    }
  }

  // =========================================================================
  // PUBLIC: Connect to a JustRide device + track state + immediately sync time
  // =========================================================================
  Future<bool> connectDevice(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 20),
    bool configureCompanion = true,
  }) async {
    final id = device.remoteId.str;
    final pending = _connectionAttempt;
    if (pending != null) {
      if (_connectionTarget == id) return await pending;
      return false;
    }
    if (_connectedDevice?.remoteId == device.remoteId && device.isConnected) {
      return true;
    }
    _userInitiatedDisconnect = false;
    _connectionTarget = id;
    final attempt = _connectDevice(device,
        timeout: timeout, configureCompanion: configureCompanion);
    _connectionAttempt = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_connectionAttempt, attempt)) {
        _connectionAttempt = null;
        _connectionTarget = null;
      }
    }
  }

  Future<bool> _connectDevice(
    BluetoothDevice device, {
    required Duration timeout,
    required bool configureCompanion,
  }) async {
    try {
      debugPrint(
          '[BLE] Connecting to JustRide device: ${device.remoteId.str}...');
      lastBleErrorNotifier.value = null;

      // Stop any running scan before connecting (vital for Android GATT stability)
      await stopScan();
      if (_android && configureCompanion && _appVisible) {
        try {
          await _companion.invokeMethod<void>('resume');
        } catch (_) {}
        // Approve while advertising, before establishing the GATT connection.
        await enableCompanion(prompt: false, address: device.remoteId.str);
      }
      if (_userInitiatedDisconnect || _disposed) {
        throw StateError('Connection cancelled');
      }
      await Future.delayed(const Duration(milliseconds: 150));

      // Guard: only treat as disconnection if the device was actually connected
      bool wasConnected = false;
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        debugPrint(
            '[BLE] Connection state for ${device.remoteId.str} -> $state');
        if (state == BluetoothConnectionState.connected) {
          wasConnected = true;
          _connectedDevice = device;
          lastBleErrorNotifier.value = null;
        } else if (state == BluetoothConnectionState.disconnected) {
          connectionStateNotifier.value = state;
          if (wasConnected) {
            wasConnected = false;
            final errStr =
                'Device ${device.platformName.isNotEmpty ? device.platformName : device.remoteId.str} disconnected';
            debugPrint('[BLE] $errStr');
            _connectedDevice = null;
            _timeSyncTimer?.cancel();
            _timeSyncTimer = null;
            if (!_userInitiatedDisconnect) {
              lastBleErrorNotifier.value =
                  'Your JustRide device disconnected. Keep it nearby and powered on.';
            }

            // Automatically restart scan so the device appears as available again in UI
            if (!_disposed) {
              debugPrint(
                  '[BLE] Resuming scanning to show available devices...');
              _scheduleRescan(delay: const Duration(seconds: 1));
            }
          }
        }
      });

      await device.connect(
        license: License.nonprofit,
        timeout: timeout,
        autoConnect: false,
        mtu: null, // Negotiate once below, after the link is established.
      );
      if (_userInitiatedDisconnect || _disposed) {
        throw StateError('Connection cancelled');
      }

      // Request high priority connection for responsive link
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {}

      // 1. Negotiate extended MTU (256 bytes) on Android so large navigation & route packets never drop
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final mtu = await device.requestMtu(256);
          debugPrint('[BLE] ✓ MTU negotiated: $mtu bytes');
        }
      } catch (e) {
        debugPrint('[BLE] MTU request notice: $e');
      }

      // Small stabilization delay for Android Bluetooth stack before discovery
      await Future.delayed(const Duration(milliseconds: 200));

      // 2. Discover all GATT services once sequentially so servicesList is complete
      final svcs = await device.discoverServices();
      if (svcs.isEmpty) throw StateError('No GATT services discovered');
      debugPrint(
          '[BLE] ✓ Discovered ${svcs.length} GATT services on ${device.remoteId.str}');

      if (_userInitiatedDisconnect || _disposed || !device.isConnected) {
        throw StateError('Connection no longer active');
      }
      _connectedDevice = device;
      _lastConnectedDeviceId = device.remoteId.str;
      lastBleErrorNotifier.value = null;
      debugPrint('[BLE] ✓ Successfully connected to ${device.remoteId.str}');

      // Save verified MAC address to SharedPreferences for instant reconnects
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'justride_saved_mac_address', device.remoteId.str);
      } catch (_) {}

      // Complete the first clock write immediately
      await syncCurrentTime(device);
      if (_userInitiatedDisconnect || _disposed || !device.isConnected) {
        throw StateError('Connection no longer active');
      }
      connectionStateNotifier.value = BluetoothConnectionState.connected;

      // Periodic time sync every 60 seconds while device stays connected
      _timeSyncTimer?.cancel();
      _timeSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        final d = _connectedDevice;
        if (d != null) syncCurrentTime(d);
      });

      return true;
    } catch (e) {
      final err = 'Connect failed for ${device.remoteId.str}: $e';
      debugPrint('[BLE] $err');
      lastBleErrorNotifier.value =
          'Unable to connect. Keep your device nearby and powered on, then try again.';
      try {
        await device.disconnect();
      } catch (_) {}
      _connectedDevice = null;
      connectionStateNotifier.value = BluetoothConnectionState.disconnected;
      if (!_disposed) _scheduleRescan(delay: const Duration(milliseconds: 500));
      return false;
    }
  }

  // =========================================================================
  // PUBLIC: Reconnect to the JustRide device by MAC or Name
  // =========================================================================

  /// Loads the saved BLE address from SharedPreferences (persisted on connect / pairing)
  Future<String?> loadSavedBleAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 1. Check dedicated verified MAC address key
      final directMac = prefs.getString('justride_saved_mac_address');
      if (directMac != null && directMac.isNotEmpty && _isValidMac(directMac)) {
        _lastConnectedDeviceId = directMac;
        return directMac;
      }
      // 2. Check in-memory last connected
      if (_lastConnectedDeviceId != null &&
          _isValidMac(_lastConnectedDeviceId!)) {
        return _lastConnectedDeviceId;
      }
      // 3. Fallback to paired device model JSON
      final raw = prefs.getString('justride_paired_device');
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final bleAddr =
            json['BLE_ADDRESS']?.toString() ?? json['bleAddress']?.toString();
        if (bleAddr != null && _isValidMac(bleAddr)) {
          _lastConnectedDeviceId = bleAddr;
          return bleAddr;
        }
        final devId = json['device_id']?.toString();
        if (devId != null && _isValidMac(devId)) {
          _lastConnectedDeviceId = devId;
          return devId;
        }
      }
    } catch (_) {}
    return _lastConnectedDeviceId;
  }

  /// Reconnects to the JustRide device.
  /// Matches the saved target MAC address, bonded devices, or any device advertising JustRide services/name.
  Future<bool> reconnect(
      {String? targetBleAddress,
      Duration timeout = const Duration(seconds: 25)}) async {
    if (_isReconnecting) {
      debugPrint(
          '[BLE] Reconnect already in progress, skipping duplicate call.');
      // A shared destination sheet may request a reconnect while the scan
      // listener has already started one. Wait for that connection attempt
      // instead of making navigation fail immediately.
      final deadline = DateTime.now().add(timeout);
      while (_isReconnecting && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return !_isReconnecting && isDeviceConnected;
    }
    try {
      _isReconnecting = true;
      lastBleErrorNotifier.value = null;

      // Resolve the target MAC or device identifier
      final target = targetBleAddress ?? await loadSavedBleAddress();

      debugPrint('[BLE] Reconnect initiated: target = $target');

      // Allow auto-reconnect now that user explicitly requested it
      _userInitiatedDisconnect = false;

      // ── Step 1: Already connected in app? ───────────────────────────────────
      if (_connectedDevice != null && isDeviceConnected) {
        if (target == null ||
            _normalizeMac(_connectedDevice!.remoteId.str) ==
                _normalizeMac(target)) {
          debugPrint(
              '[BLE] Already connected to ${_connectedDevice!.remoteId.str}. Syncing time...');
          await syncCurrentTime(_connectedDevice!);
          return true;
        }
      }

      // ── Step 2: Check OS-connected & bonded devices (Android OS cache fast-path) ──
      try {
        final connected = FlutterBluePlus.connectedDevices;
        for (final d in connected) {
          final dName = d.platformName.toLowerCase();
          final dMac = _normalizeMac(d.remoteId.str);
          if ((target != null && dMac == _normalizeMac(target)) ||
              dName.contains('justride')) {
            debugPrint(
                '[BLE] Target device already connected to OS (${d.remoteId.str}). Binding...');
            final ok = await connectDevice(d, timeout: timeout);
            if (ok) return true;
          }
        }

        final bonded = await FlutterBluePlus.bondedDevices;
        for (final d in bonded) {
          final dName = d.platformName.toLowerCase();
          final dMac = _normalizeMac(d.remoteId.str);
          if ((target != null && dMac == _normalizeMac(target)) ||
              dName.contains('justride')) {
            debugPrint(
                '[BLE] Target device found in OS bonded devices (${d.remoteId.str}). Connecting...');
            final ok = await connectDevice(d, timeout: timeout);
            if (ok) return true;
          }
        }
      } catch (e) {
        debugPrint('[BLE] Error checking bonded/connected devices: $e');
      }

      // ── Step 3: Scan cache fast-path ───────────────────────────────────────
      final cached = [
        ...justRideDevicesNotifier.value,
        ...FlutterBluePlus.lastScanResults,
      ];
      final seenIds = <String>{};
      for (final result in cached) {
        if (seenIds.add(result.device.remoteId.str)) {
          if (_matchesTarget(result, target)) {
            debugPrint(
                '[BLE] Found matching device in scan cache (${result.device.remoteId.str}). Connecting...');
            final ok = await connectDevice(result.device, timeout: timeout);
            if (ok) return true;
          }
        }
      }

      // ── Step 4: Live scan + fast direct-connect fallback ───────────────────
      debugPrint(
          '[BLE] Scanning for JustRide device (target: $target, timeout: ${timeout.inSeconds}s)...');
      final completer = Completer<bool>();
      StreamSubscription<List<ScanResult>>? sub;
      Timer? directFallbackTimer;

      final timer = Timer(timeout, () {
        directFallbackTimer?.cancel();
        sub?.cancel();
        if (!completer.isCompleted) {
          final diag = target != null
              ? 'Could not find device ($target). Ensure the JustRide display is powered on and within range.'
              : 'Could not find any JustRide device nearby. Ensure the display is powered on.';
          debugPrint('[BLE] Reconnect scan timed out: $diag');
          lastBleErrorNotifier.value =
              'No JustRide device found. Check that your device is nearby and powered on.';
          completer.complete(false);
        }
      });

      // If a known valid MAC exists, try direct connect if scan hasn't matched within 3s
      if (target != null && _isValidMac(target)) {
        directFallbackTimer = Timer(const Duration(seconds: 3), () async {
          if (!completer.isCompleted && _connectedDevice == null) {
            debugPrint(
                '[BLE] Fast fallback: attempting direct connect to $target...');
            try {
              final device = BluetoothDevice.fromId(target);
              final ok = await connectDevice(device,
                  timeout: const Duration(seconds: 12));
              if (ok && !completer.isCompleted) {
                timer.cancel();
                sub?.cancel();
                completer.complete(true);
              }
            } catch (e) {
              debugPrint('[BLE] Direct connect fallback failed: $e');
            }
          }
        });
      }

      // Stop any existing scan and start fresh
      await stopScan();
      await Future.delayed(const Duration(milliseconds: 100));
      await startJustRideScan();

      sub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          if (_matchesTarget(r, target) && !completer.isCompleted) {
            directFallbackTimer?.cancel();
            timer.cancel();
            sub?.cancel();
            debugPrint(
                '[BLE] Discovered matching target ${r.device.remoteId.str} (${getDeviceName(r)})! Connecting...');
            await stopScan();
            await Future.delayed(const Duration(milliseconds: 150));
            final ok = await connectDevice(r.device, timeout: timeout);
            if (!completer.isCompleted) completer.complete(ok);
            break;
          }
        }
      });

      return await completer.future;
    } catch (e) {
      final msg = 'Reconnect error: $e';
      debugPrint('[BLE] $msg');
      lastBleErrorNotifier.value =
          'Unable to reconnect. Check Bluetooth and try again.';
      return false;
    } finally {
      _isReconnecting = false;
    }
  }

  bool _matchesTarget(ScanResult r, String? target) {
    final devMac = _normalizeMac(r.device.remoteId.str);

    // 1. Exact MAC match if target is a MAC address
    if (target != null && target.isNotEmpty && _isValidMac(target)) {
      if (devMac == _normalizeMac(target)) return true;
    }

    // 2. Target name match
    final name = getDeviceName(r).toLowerCase();
    if (target != null && target.isNotEmpty && !_isValidMac(target)) {
      if (name.contains(target.toLowerCase())) return true;
    }

    // 3. JustRide Hardware Service UUID match (0xFF30 Nav, 0xFF10 OTA, 0xFF20 Img, 0x1805 CTS)
    for (final uuid in r.advertisementData.serviceUuids) {
      final u = uuid.toString().toLowerCase().replaceAll('-', '');
      if (u.contains('ff30') ||
          u.contains('ff10') ||
          u.contains('ff20') ||
          u.contains('1805')) {
        return true;
      }
    }

    // 4. General JustRide device fallback by advertised or platform name
    if (name.contains(_kDeviceName.toLowerCase())) return true;

    return false;
  }

  static String _normalizeMac(String str) {
    return str.replaceAll(':', '').replaceAll('-', '').toLowerCase().trim();
  }

  static bool _isValidMac(String str) {
    if (str.isEmpty) return false;
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    final uuidRegex = RegExp(
        r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$');
    return macRegex.hasMatch(str) || uuidRegex.hasMatch(str);
  }

  /// Disconnects the currently connected BLE device WITHOUT unpairing.
  /// Sets _userInitiatedDisconnect = true so auto-reconnect is suppressed.
  Future<void> disconnectDevice({bool restartScan = true}) async {
    _userInitiatedDisconnect = true; // suppress auto-reconnect
    if (_android) {
      try {
        await _companion.invokeMethod<void>('pause');
      } catch (_) {}
    }
    _isReconnecting = false;
    try {
      _timeSyncTimer?.cancel();
      _timeSyncTimer = null;
      // Keep _connectionStateSub alive so the UI updates when the device
      // physically disconnects – we just cancel it after the disconnect call.
      final device = _connectedDevice;
      if (device != null) {
        debugPrint(
            '[BLE] User-initiated disconnect from ${device.remoteId.str}...');
        await device.disconnect();
        debugPrint('[BLE] Cleanly disconnected from ${device.remoteId.str}.');
      }
    } catch (e) {
      debugPrint('[BLE] Error during user disconnect: $e');
    } finally {
      _connectionStateSub?.cancel();
      _connectionStateSub = null;
      _connectedDevice = null;
      connectionStateNotifier.value = BluetoothConnectionState.disconnected;
      // Restart scan so paired device shows in the Available list again
      if (restartScan && !kIsWeb && !_disposed) startJustRideScan();
    }
  }

  bool get isDeviceConnected =>
      connectionStateNotifier.value == BluetoothConnectionState.connected &&
      _connectedDevice?.isConnected == true;
  Future<bool> waitForConnectionReady() =>
      _connectionAttempt ?? Future<bool>.value(isDeviceConnected);
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get lastConnectedDeviceId => _lastConnectedDeviceId;

  void setAutoReconnect(bool enable) {
    _autoReconnectEnabled = enable;
  }

  // =========================================================================
  // PUBLIC: Write real-time to firmware GATT CTS 0x1805 / 0x2A2B
  // =========================================================================
  Future<bool> syncCurrentTime(BluetoothDevice device) async {
    if (_isSyncingTime) return false;
    _isSyncingTime = true;
    try {
      List<BluetoothService> services = device.servicesList;
      BluetoothCharacteristic? findTimeCharacteristic(
          List<BluetoothService> availableServices) {
        for (final svc in availableServices) {
          final sUuid = svc.uuid.toString().toLowerCase().replaceAll('-', '');
          if (sUuid.contains(_kCtsServiceUuid)) {
            for (final chr in svc.characteristics) {
              final cUuid =
                  chr.uuid.toString().toLowerCase().replaceAll('-', '');
              if (cUuid.contains(_kCtsCharUuid)) {
                return chr;
              }
            }
          }
        }
        return null;
      }

      var timeChr = findTimeCharacteristic(services);
      if (timeChr == null) {
        debugPrint(
            '[BLE] CTS characteristic not cached, discovering services...');
        await Future.delayed(const Duration(milliseconds: 200));
        services = await device.discoverServices();
        timeChr = findTimeCharacteristic(services);
      }
      if (timeChr == null) {
        debugPrint(
            '[BLE] ⚠️ CTS characteristic 0x2A2B not found on ${device.remoteId.str}');
        return false;
      }

      final now = DateTime.now();
      final timePacket = encodeCurrentTime(now);
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      // Send confirmed write (withoutResponse: false) first for guaranteed acknowledgement
      bool writeSucceeded = false;
      try {
        await timeChr.write(
          timePacket,
          withoutResponse: false,
        );
        writeSucceeded = true;
      } catch (e1) {
        debugPrint(
            '[BLE] Confirmed CTS write failed: $e1. Retrying with writeWithoutResponse...');
        try {
          await timeChr.write(
            timePacket,
            withoutResponse: true,
          );
          writeSucceeded = true;
        } catch (e2) {
          debugPrint('[BLE] CTS fallback write also failed: $e2');
        }
      }

      if (writeSucceeded) {
        debugPrint('[BLE] ✓ Time synced to JustRide HUD: $timeStr');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BLE] Error syncing time: $e');
      return false;
    } finally {
      _isSyncingTime = false;
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  /// Accepts a scan result as a JustRide device if:
  /// (a) The device advertises JustRide hardware services (0xFF30 Nav, 0xFF10 OTA, 0xFF20 Img, 0x1805 CTS), OR
  /// (b) The advertisement or platform name contains 'justride' (case-insensitive), OR
  /// (c) The device MAC matches our last saved/connected device (handles empty advName on Android 12+)
  bool _isJustRideResult(ScanResult r) {
    // 1. Hardware Service UUID match (Primary indicator - 100% reliable even when Android strips advName)
    for (final uuid in r.advertisementData.serviceUuids) {
      final u = uuid.toString().toLowerCase().replaceAll('-', '');
      if (u.contains('ff30') ||
          u.contains('ff10') ||
          u.contains('ff20') ||
          u.contains('1805')) {
        return true;
      }
    }

    // 2. Name match (advName or platformName contains 'justride')
    final name = getDeviceName(r).toLowerCase();
    if (name.contains(_kDeviceName.toLowerCase())) return true;

    // 3. MAC-based fallback: accept if this matches our last known paired device
    final devMac = _normalizeMac(r.device.remoteId.str);
    if (_lastConnectedDeviceId != null &&
        devMac == _normalizeMac(_lastConnectedDeviceId!)) {
      debugPrint(
          '[BLE] MAC-match fallback: accepted ${r.device.remoteId.str} (advName was empty)');
      return true;
    }
    return false;
  }

  static bool _listEquals(List<ScanResult> a, List<ScanResult> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].device.remoteId.str != b[i].device.remoteId.str ||
          a[i].rssi != b[i].rssi) {
        return false;
      }
    }
    return true;
  }

  static String getDeviceName(ScanResult result) {
    final adv = result.advertisementData.advName.trim();
    if (adv.isNotEmpty) return adv;
    final plat = result.device.platformName.trim();
    if (plat.isNotEmpty) return plat;
    return '';
  }

  static (String label, int bars) getSignalInfo(int rssi) {
    if (rssi >= -65) return ('Strong', 3);
    if (rssi >= -80) return ('Good', 2);
    return ('Fair', 1);
  }

  void dispose() {
    _disposed = true;
    _connectionStateSub?.cancel();
    _timeSyncTimer?.cancel();
    _rescanTimer?.cancel();
    _scanSub?.cancel();
    _isScanSub?.cancel();
    _adapterSub?.cancel();
    _connectedDevice = null;
    connectionStateNotifier.value = BluetoothConnectionState.disconnected;
  }
}
