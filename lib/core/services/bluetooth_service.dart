import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Senior-Grade Real-Time Bluetooth Service for JustRide HUD and IoT hardware.
/// - Continuously re-scans for JustRide devices.
/// - Strictly filters: ONLY devices with "justride" in their name are shown.
/// - On connect: immediately writes phone real-time (HH:MM:SS) to firmware GATT CTS (0x1805 / 0x2A2B).
/// - On disconnect / device reset: detects disconnection, cancels timers, clears state,
///   and immediately restarts scanning so the device shows as available again.
/// - Full reconnect support with live status logging.
class JustRideBleService {
  JustRideBleService._();
  static final JustRideBleService instance = JustRideBleService._();

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
  bool _disposed = false;
  // true only when the user explicitly pressed Disconnect – suppresses auto-reconnect
  bool _userInitiatedDisconnect = false;

  // ─── Public notifiers (drive UI ValueListenableBuilder) ──────────────────────
  final ValueNotifier<List<ScanResult>> justRideDevicesNotifier =
      ValueNotifier<List<ScanResult>>([]);
  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<BluetoothAdapterState> adapterStateNotifier =
      ValueNotifier<BluetoothAdapterState>(BluetoothAdapterState.unknown);
  final ValueNotifier<BluetoothConnectionState> connectionStateNotifier =
      ValueNotifier<BluetoothConnectionState>(BluetoothConnectionState.disconnected);

  // ─── BLE time sync GATT UUIDs matching firmware ble.c ────────────────────────
  static const String _kCtsServiceUuid = '1805';
  static const String _kCtsCharUuid = '2a2b';

  // ─── Scan configuration ──────────────────────────────────────────────────────
  static const Duration _kScanWindow = Duration(seconds: 10);

  // =========================================================================
  // INIT – call once from screen initState or app startup
  // =========================================================================
  void init() {
    _disposed = false;

    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      adapterStateNotifier.value = state;
      if (state == BluetoothAdapterState.on && !FlutterBluePlus.isScanningNow) {
        _startOneScan();
      }
    });

    _isScanSub?.cancel();
    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      isScanningNotifier.value = scanning;
      if (!scanning && !_disposed && _connectedDevice == null) {
        _scheduleRescan(delay: const Duration(milliseconds: 300));
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
    if (_disposed) return;

    await _safeStopScan();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen(
      (results) {
        if (_disposed) return;
        final Map<String, ScanResult> uniqueMap = {};
        for (final r in results) {
          if (_isJustRideResult(r)) {
            uniqueMap[r.device.remoteId.str] = r;

            // Auto-reconnect if this was our previously connected device
            // BUT ONLY if the user didn't explicitly disconnect
            if (_autoReconnectEnabled &&
                !_userInitiatedDisconnect &&
                _lastConnectedDeviceId != null &&
                r.device.remoteId.str.toLowerCase() ==
                    _lastConnectedDeviceId!.toLowerCase() &&
                _connectedDevice == null &&
                !_isReconnecting) {
              debugPrint(
                  '[BLE] Re-discovered previously paired device ${r.device.remoteId.str}! Auto-reconnecting...');
              _isReconnecting = true;
              connectDevice(r.device).then((_) {
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
        timeout: _kScanWindow,
        androidUsesFineLocation: false,
      );
    } catch (e) {
      debugPrint('[BLE] startScan failed: $e');
    }
  }

  void _scheduleRescan({Duration delay = const Duration(seconds: 1)}) {
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
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      debugPrint('[BLE] Connecting to JustRide device: ${device.remoteId.str}...');
      await stopScan();

      // Listen to physical connection state
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        debugPrint('[BLE] Connection state for ${device.remoteId.str} -> $state');
        connectionStateNotifier.value = state;

        if (state == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          _lastConnectedDeviceId = device.remoteId.str;
        } else if (state == BluetoothConnectionState.disconnected) {
          debugPrint('[BLE] Device disconnected (reset/power cycle/disconnected).');
          _connectedDevice = null;
          _timeSyncTimer?.cancel();
          _timeSyncTimer = null;

          // Automatically restart scan so the device appears as available again in UI
          if (!_disposed) {
            debugPrint('[BLE] Resuming scanning to show available devices...');
            startJustRideScan();
          }
        }
      });

      await device.connect(
        license: License.nonprofit,
        timeout: timeout,
        autoConnect: false,
      );

      _connectedDevice = device;
      _lastConnectedDeviceId = device.remoteId.str;
      connectionStateNotifier.value = BluetoothConnectionState.connected;
      debugPrint('[BLE] ✓ Successfully connected to ${device.remoteId.str}');

      // Immediate time sync after connection stabilises
      syncCurrentTime(device);

      // Periodic time sync every 60 seconds while device stays connected
      _timeSyncTimer?.cancel();
      _timeSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        final d = _connectedDevice;
        if (d != null) syncCurrentTime(d);
      });

      return true;
    } catch (e) {
      debugPrint('[BLE] Connect failed for ${device.remoteId.str}: $e');
      _connectedDevice = null;
      connectionStateNotifier.value = BluetoothConnectionState.disconnected;
      if (!_disposed) _startOneScan();
      return false;
    }
  }

  // =========================================================================
  // PUBLIC: Reconnect to the EXACT previously paired JustRide device by MAC
  // =========================================================================

  /// Loads the saved BLE address from SharedPreferences (persisted on pairDevice)
  Future<String?> loadSavedBleAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('justride_paired_device');
      if (raw == null) return _lastConnectedDeviceId;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Prefer explicit BLE_ADDRESS stored during pairing, fall back to device_id
      return json['BLE_ADDRESS']?.toString() ??
          json['bleAddress']?.toString() ??
          json['device_id']?.toString() ??
          _lastConnectedDeviceId;
    } catch (_) {
      return _lastConnectedDeviceId;
    }
  }

  /// Reconnects STRICTLY to the MAC address that was saved during pairing.
  /// If [targetBleAddress] is provided it overrides the saved address.
  Future<bool> reconnect(
      {String? targetBleAddress,
      Duration timeout = const Duration(seconds: 20)}) async {
    try {
      // Resolve the exact MAC to connect to
      final target =
          targetBleAddress ?? await loadSavedBleAddress();

      if (target == null || target.isEmpty) {
        debugPrint('[BLE] Reconnect: no saved BLE address found.');
        return false;
      }

      debugPrint('[BLE] Reconnect: targeting exact MAC = $target');

      // Allow auto-reconnect now that user explicitly requested it
      _userInitiatedDisconnect = false;

      // 1. If already connected to the right device, just sync time
      if (_connectedDevice != null &&
          _connectedDevice!.remoteId.str.toLowerCase() ==
              target.toLowerCase() &&
          isDeviceConnected) {
        debugPrint('[BLE] Already connected to $target. Syncing time...');
        await syncCurrentTime(_connectedDevice!);
        return true;
      }

      // 2. Check currently discovered devices first (fast path)
      final cached = justRideDevicesNotifier.value;
      for (final result in cached) {
        if (result.device.remoteId.str.toLowerCase() ==
            target.toLowerCase()) {
          debugPrint(
              '[BLE] Found $target in scan cache. Connecting immediately...');
          return await connectDevice(result.device, timeout: timeout);
        }
      }

      // 3. Start fresh scan and wait ONLY for the specific MAC address
      debugPrint('[BLE] Starting scan to find MAC: $target');
      final completer = Completer<bool>();
      StreamSubscription<List<ScanResult>>? sub;

      final timer = Timer(timeout, () {
        sub?.cancel();
        if (!completer.isCompleted) {
          debugPrint(
              '[BLE] Reconnect scan timed out. $target not found within ${timeout.inSeconds}s.');
          completer.complete(false);
        }
      });

      await startJustRideScan();

      sub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          // STRICT match – only connect to the exact saved MAC
          if (r.device.remoteId.str.toLowerCase() == target.toLowerCase() &&
              !completer.isCompleted) {
            timer.cancel();
            sub?.cancel();
            debugPrint(
                '[BLE] Found exact target $target! Connecting...');
            final ok = await connectDevice(r.device, timeout: timeout);
            if (!completer.isCompleted) completer.complete(ok);
            break;
          }
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('[BLE] Error during reconnect: $e');
      return false;
    }
  }

  /// Disconnects the currently connected BLE device WITHOUT unpairing.
  /// Sets _userInitiatedDisconnect = true so auto-reconnect is suppressed.
  Future<void> disconnectDevice() async {
    _userInitiatedDisconnect = true; // suppress auto-reconnect
    _isReconnecting = false;
    try {
      _timeSyncTimer?.cancel();
      _timeSyncTimer = null;
      // Keep _connectionStateSub alive so the UI updates when the device
      // physically disconnects – we just cancel it after the disconnect call.
      final device = _connectedDevice;
      if (device != null) {
        debugPrint('[BLE] User-initiated disconnect from ${device.remoteId.str}...');
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
      if (!_disposed) startJustRideScan();
    }
  }

  bool get isDeviceConnected => _connectedDevice != null;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get lastConnectedDeviceId => _lastConnectedDeviceId;

  void setAutoReconnect(bool enable) {
    _autoReconnectEnabled = enable;
  }

  // =========================================================================
  // PUBLIC: Write real-time to firmware GATT CTS 0x1805 / 0x2A2B
  // =========================================================================
  Future<void> syncCurrentTime(BluetoothDevice device) async {
    try {
      await Future.delayed(const Duration(milliseconds: 800));

      final services = await device.discoverServices();
      BluetoothCharacteristic? timeChr;

      for (final svc in services) {
        final sUuid = svc.uuid.toString().toLowerCase().replaceAll('-', '');
        if (sUuid.contains(_kCtsServiceUuid)) {
          for (final chr in svc.characteristics) {
            final cUuid = chr.uuid.toString().toLowerCase().replaceAll('-', '');
            if (cUuid.contains(_kCtsCharUuid)) {
              timeChr = chr;
              break;
            }
          }
        }
        if (timeChr != null) break;
      }

      if (timeChr == null) {
        debugPrint('[BLE] CTS characteristic 0x2A2B not found.');
        return;
      }

      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      await timeChr.write(
        utf8.encode(timeStr),
        withoutResponse: timeChr.properties.writeWithoutResponse,
      );

      debugPrint('[BLE] ✓ Time synced to JustRide OLED: $timeStr');
    } catch (e) {
      debugPrint('[BLE] Error syncing time: $e');
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================
  static bool _isJustRideResult(ScanResult r) {
    return getDeviceName(r).toLowerCase().contains('justride');
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
  }
}
