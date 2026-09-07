import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ble_navigation_packet.dart';
import '../models/navigation_state.dart';
import '../utils/route_window_transformer.dart';
import 'bluetooth_service.dart';
import 'navigation_service.dart';

/// Manages GATT Navigation Service (0xFF30) communication with ESP32-S3 TFT Display.
class BleNavigationService {
  BleNavigationService._();
  static final BleNavigationService instance = BleNavigationService._();

  // ── GATT Navigation UUIDs matching firmware ble.c ───────────────────────────
  static const String navServiceUuid = 'ff30';
  static const String navDataCharUuid = 'ff31';
  static const String navStatusCharUuid = 'ff32';

  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _statusChar;

  // FIX #1: ValueNotifier.addListener() returns void, NOT a StreamSubscription.
  // Track the VoidCallback directly so we can removeListener() on dispose/re-init.
  VoidCallback? _connListener;

  NavigationState? _lastTransmittedState;
  DateTime? _lastTransmittedTime;
  bool _useJson = false;

  // FIX #2: Guard concurrent discoverServices() calls (not re-entrant on Android;
  // a parallel call resets MTU negotiation and can drop the BLE connection).
  bool _isDiscovering = false;

  // FIX #3: Serialize GATT characteristic writes to prevent queue congestion.
  Future<void> _writeTail = Future<void>.value();
  bool _isSendingBrightness = false;
  int? _pendingBrightnessPct;

  final ValueNotifier<bool> isNavCharReadyNotifier = ValueNotifier<bool>(false);
  bool get isReady => isNavCharReadyNotifier.value && _dataChar != null;

  /// Queues every characteristic write in FIFO order. Android permits only one
  /// GATT operation at a time; dropping a route segment while nav telemetry is
  /// in flight made left/right cues arrive late or not at all.
  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final scheduled = _writeTail.then<T>(
      (_) => operation(),
      onError: (_, __) => operation(),
    );
    _writeTail = scheduled.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    return scheduled;
  }

  Future<bool> _writeBytes(List<int> bytes, {bool? withoutResponse}) {
    return _enqueueWrite(() async {
      final chr = _dataChar;
      if (chr == null) return false;
      try {
        await chr.write(
          bytes,
          withoutResponse:
              withoutResponse ?? chr.properties.writeWithoutResponse,
        );
        return true;
      } catch (e) {
        // A transient GATT_BUSY must not discard a working characteristic.
        // The following periodic telemetry write can use it immediately.
        debugPrint('[BleNav] GATT write failed: $e');
        return false;
      }
    });
  }

  /// Configure whether to send JSON strings instead of compact binary
  void setDebugJsonMode(bool enable) {
    _useJson = enable;
  }

  /// Initializes the service and listens for connection state changes.
  void init() {
    // Remove any previously registered listener before adding a new one.
    if (_connListener != null) {
      JustRideBleService.instance.connectionStateNotifier
          .removeListener(_connListener!);
      _connListener = null;
    }

    _connListener = _onConnectionStateChanged;
    JustRideBleService.instance.connectionStateNotifier
        .addListener(_connListener!);

    // In case the device is already connected when init() is called.
    if (JustRideBleService.instance.isDeviceConnected) {
      _discoverNavCharacteristics(JustRideBleService.instance.connectedDevice);
    }
  }

  void _onConnectionStateChanged() {
    final state = JustRideBleService.instance.connectionStateNotifier.value;
    if (state == BluetoothConnectionState.connected) {
      final dev = JustRideBleService.instance.connectedDevice;
      if (dev != null) {
        // Delay: let bluetooth_service.syncCurrentTime() finish its discoverServices()
        // call first. Android BLE stack is not re-entrant — two concurrent
        // discoverServices() calls on the same device will reset MTU and can
        // cause an immediate disconnection.
        Future.delayed(const Duration(milliseconds: 1500), () {
          _discoverNavCharacteristics(dev);
        });
      }
    } else {
      _dataChar = null;
      _statusChar = null;
      _isDiscovering = false;
      _writeTail = Future<void>.value();
      isNavCharReadyNotifier.value = false;
    }
  }

  /// Discovers the Navigation characteristics on the connected BLE device.
  /// Guarded by [_isDiscovering] to prevent concurrent calls crashing the BLE stack.
  Future<bool> _discoverNavCharacteristics(BluetoothDevice? device) async {
    if (device == null) return false;
    if (_isDiscovering) {
      debugPrint(
          '[BleNav] discoverServices already in-flight, skipping duplicate call.');
      return false;
    }
    _isDiscovering = true;
    try {
      List<BluetoothService> services = device.servicesList;
      if (services.isEmpty) {
        debugPrint(
            '[BleNav] Discovering GATT services for ${device.remoteId.str}...');
        services = await device.discoverServices();
      }

      debugPrint(
          '[BleNav] Inspected ${services.length} GATT services on ${device.remoteId.str}');
      for (final svc in services) {
        final sUuid = svc.uuid.toString().toLowerCase().replaceAll('-', '');
        if (sUuid.contains(navServiceUuid)) {
          debugPrint('[BleNav] Found matching Nav Service: $sUuid');
          for (final chr in svc.characteristics) {
            final cUuid = chr.uuid.toString().toLowerCase().replaceAll('-', '');
            if (cUuid.contains(navDataCharUuid)) {
              _dataChar = chr;
              debugPrint('[BleNav] Found Nav Data char: $cUuid');
            } else if (cUuid.contains(navStatusCharUuid)) {
              _statusChar = chr;
              debugPrint('[BleNav] Found Nav Status char: $cUuid');
            }
          }
        }
      }

      final ready = _dataChar != null;
      isNavCharReadyNotifier.value = ready;
      if (ready) {
        debugPrint(
            '[BleNav] ✓ Found Navigation characteristic 0xFF31 on ${device.remoteId.str}');

        // Listen to Navigation Status (0xFF32)
        if (_statusChar != null) {
          if (_statusChar!.properties.notify) {
            await _statusChar!.setNotifyValue(true);
            _statusChar!.onValueReceived.listen((value) {
              if (value.isNotEmpty) {
                final status = value[0];
                debugPrint(
                    '[BleNav] Received Status Code: 0x${status.toRadixString(16).padLeft(2, '0')}');
                if (status == 0x05) {
                  // NAV_STATUS_RESUME_ROUTE
                  // Import omitted; assuming this will be resolved in next chunk or it's accessible.
                  NavigationService.instance.recalculateAndResumeRoute();
                } else if (status == 0x06) {
                  // NAV_STATUS_CANCEL_ROUTE
                  NavigationService.instance.stopNavigation();
                }
              }
            });
            debugPrint('[BleNav] Subscribed to Nav Status notifications');
          }
        }

        // Sync if navigation is active in any riding state:
        //   NAVIGATING, REROUTING, or PAUSED — not just NAVIGATING
        if (_lastTransmittedState != null) {
          final status = _lastTransmittedState!.navigationStatus;
          final isActiveState = status == 'NAVIGATING' ||
              status == 'REROUTING' ||
              status == 'PAUSED' ||
              status == 'GPS_LOST';
          if (isActiveState) {
            syncState(_lastTransmittedState!);
          }
        }
      }
      return ready;
    } catch (e) {
      debugPrint('[BleNav] Error discovering nav service: $e');
      return false;
    } finally {
      _isDiscovering = false;
    }
  }

  /// Sends a navigation packet to the ESP32-S3 over BLE with change throttling.
  Future<bool> sendNavUpdate(
    NavigationState state, {
    BleNavOpCode opCode = BleNavOpCode.navUpdate,
    bool force = false,
  }) async {
    final device = JustRideBleService.instance.connectedDevice;
    if (device == null) {
      // Disconnected: save state so it can be synced on reconnection.
      _lastTransmittedState = state;
      return false;
    }

    if (_dataChar == null) {
      // Wait briefly if service discovery is already running.
      for (var attempt = 0;
          _dataChar == null && _isDiscovering && attempt < 8;
          attempt++) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (_dataChar == null) {
        final ok = await _discoverNavCharacteristics(device);
        if (!ok || _dataChar == null) {
          _lastTransmittedState = state;
          return false;
        }
      }
    }

    // Throttle check — only for regular updates, not for forced ops.
    if (!force && opCode == BleNavOpCode.navUpdate) {
      if (!_shouldSendUpdate(state)) {
        return false;
      }
    }

    final packet = BleNavigationPacket.fromState(state, opCode: opCode);
    final bytes = _useJson ? packet.toJsonBytes() : packet.toBinary();
    final isHighFreqUpdate = (opCode == BleNavOpCode.navUpdate);
    final sent = await _writeBytes(
      bytes,
      withoutResponse: isHighFreqUpdate ? true : null,
    );
    if (sent) {
      _lastTransmittedState = state;
      _lastTransmittedTime = DateTime.now();
      return true;
    }
    return false;
  }

  /// Sends full state sync on reconnection or ride resumption
  Future<void> syncState(NavigationState state) async {
    debugPrint('[BleNav] Sending SYNC_STATE to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.syncState, force: true);
  }

  /// Sends NAV_START when rider begins navigation
  Future<void> sendNavStart(NavigationState state) async {
    debugPrint('[BleNav] Sending NAV_START to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.navStart, force: true);
  }

  /// Sends NAV_REROUTE when route recalculation occurs
  Future<void> sendNavReroute(NavigationState state) async {
    debugPrint('[BleNav] Sending NAV_REROUTE to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.navReroute, force: true);
  }

  /// Sends NAV_ARRIVED when destination reached
  Future<void> sendNavArrived(NavigationState state) async {
    debugPrint('[BleNav] Sending NAV_ARRIVED to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.navArrived, force: true);
  }

  /// Sends NAV_STOP when rider cancels/exits ride
  Future<void> sendNavStop(NavigationState state) async {
    debugPrint('[BleNav] Sending NAV_STOP to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.navStop, force: true);
    _lastTransmittedState = null;
  }

  /// Sends immediate standalone NAV_CANCEL to reset the display back to idle
  Future<bool> sendNavCancel() async {
    if (!isReady || _dataChar == null) return false;
    try {
      debugPrint('[BleNav] Sending standalone NAV_CANCEL (0x06) to ESP32...');
      final sent = await _writeBytes(
        [BleNavOpCode.navCancel.value],
        withoutResponse: false,
      );
      if (!sent) return false;
      _lastTransmittedState = null;
      return true;
    } catch (e) {
      debugPrint('[BleNav] Error sending nav cancel: $e');
      return false;
    }
  }

  /// Controls ESP32 display brightness remotely (0 to 100%)
  Future<bool> sendSetBrightness(int brightnessPct) async {
    _pendingBrightnessPct = brightnessPct.clamp(0, 100).toInt();
    if (_isSendingBrightness) return true;

    _isSendingBrightness = true;
    var success = true;
    try {
      // A slider can produce many changes per second.  Send them sequentially
      // and retain only the final value, avoiding a congested Android GATT queue.
      while (_pendingBrightnessPct != null) {
        final brightness = _pendingBrightnessPct!;
        _pendingBrightnessPct = null;

        final device = JustRideBleService.instance.connectedDevice;
        if (device == null) {
          success = false;
          break;
        }
        // The app may open settings during the connection's initial service
        // discovery. Wait briefly for that discovery before attempting another
        // one, so the first brightness gesture is not silently lost.
        for (var attempt = 0;
            _dataChar == null && _isDiscovering && attempt < 8;
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (_dataChar == null) {
          final discovered = await _discoverNavCharacteristics(device);
          if (!discovered || _dataChar == null) {
            success = false;
            break;
          }
        }

        debugPrint(
            '[BleNav] Setting display brightness to $brightness% via BLE...');
        if (!await _writeBytes(
          [BleNavOpCode.setBrightness.value, brightness],
          withoutResponse: false,
        )) {
          success = false;
          break;
        }
      }
    } catch (e) {
      debugPrint('[BleNav] Error setting brightness: $e');
      success = false;
    } finally {
      _isSendingBrightness = false;
    }
    return success;
  }

  /// Restarts the ESP32 microcontroller cleanly via BLE
  Future<bool> sendRestartDevice() async {
    if (!isReady || _dataChar == null) return false;
    try {
      debugPrint('[BleNav] Sending RESTART command to ESP32...');
      return await _writeBytes(
        [BleNavOpCode.restartDevice.value],
        withoutResponse: false,
      );
    } catch (e) {
      debugPrint('[BleNav] Error sending restart command: $e');
      return false;
    }
  }

  /// Resets ESP32 device settings to factory defaults via BLE
  Future<bool> sendResetDevice() async {
    if (!isReady || _dataChar == null) return false;
    try {
      debugPrint('[BleNav] Sending FACTORY RESET command to ESP32...');
      return await _writeBytes(
        [BleNavOpCode.resetDevice.value],
        withoutResponse: false,
      );
    } catch (e) {
      debugPrint('[BleNav] Error sending reset command: $e');
      return false;
    }
  }

  /// Sends sliding route window segment (OpCode 0x0B) to ESP32
  Future<bool> sendRouteSegment(RouteWindowSegment segment) async {
    if (!isReady || _dataChar == null || segment.points.isEmpty) return false;

    final packet = RouteSegmentPacket.fromWindow(segment);
    final bytes = packet.toBinary();
    return await _writeBytes(bytes, withoutResponse: false);
  }

  /// Sends strictly the latest notification (OpCode 0x0F) to the ESP32 HUD display.
  /// Overwrites and replaces any prior notification on the screen.
  Future<bool> sendLatestNotification(String title, String message) async {
    final device = JustRideBleService.instance.connectedDevice;
    if (device == null) {
      debugPrint(
          '[BleNav] Cannot send notification: no BLE display is connected');
      return false;
    }

    // A notification can arrive while the connection's initial GATT discovery
    // is still running.  Wait for it instead of losing the one latest alert.
    for (var attempt = 0;
        _dataChar == null && _isDiscovering && attempt < 8;
        attempt++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (_dataChar == null) {
      await _discoverNavCharacteristics(device);
    }
    if (_dataChar == null) {
      debugPrint(
          '[BleNav] Cannot send notification: Nav characteristic unavailable');
      return false;
    }
    final packet = LatestNotificationPacket(
      title: title,
      message: message,
    );
    final bytes = packet.toBinary();
    try {
      debugPrint(
          '[BleNav] Transmitting latest notification to ESP32: "$title" - "$message"');
      return await _writeBytes(bytes, withoutResponse: false);
    } catch (e) {
      debugPrint('[BleNav] Error sending notification packet: $e');
      return false;
    }
  }

  /// Throttling rule engine: prevents flooding BLE bandwidth with redundant GPS coordinates
  bool _shouldSendUpdate(NavigationState current) {
    final last = _lastTransmittedState;
    if (last == null) return true;

    // Always send immediately if GPS availability changes (GPS lost / recovered)
    if (current.gpsAvailable != last.gpsAvailable) return true;

    // Always send immediately if ride state changes
    if (current.rideState != last.rideState) return true;

    // Always send if maneuver or maneuver lifecycle stage changes
    if (current.maneuver != last.maneuver) return true;
    if (current.maneuverId != last.maneuverId) return true;
    if (current.maneuverState != last.maneuverState) return true;

    // Send every 1m inside near-route window (< 100m) or 2m otherwise
    // to keep the TFT screen pointer perfectly live in real-time
    final distDelta =
        (current.maneuverDistanceMeters - last.maneuverDistanceMeters).abs();
    if (distDelta >= 1.0) return true;

    // Speed changed noticeably (>= 0.4 km/h)
    if ((current.speedKmh - last.speedKmh).abs() >= 0.4) return true;

    // Heading changed noticeably (>= 3 degrees while moving)
    if (current.speedKmh >= 1.5 && (current.heading - last.heading).abs() >= 3.0) {
      return true;
    }

    // ETA changed by >= 15 seconds
    if ((current.remainingDurationSeconds - last.remainingDurationSeconds)
            .abs() >=
        15) {
      return true;
    }

    // Remaining total distance changed by >= 10m
    if ((current.remainingDistanceMeters - last.remainingDistanceMeters)
            .abs() >=
        10) {
      return true;
    }

    // Heartbeat: refresh at least every 250ms to guarantee zero perceived lag
    // between phone movement and the motorcycle HUD display.
    final now = DateTime.now();
    if (_lastTransmittedTime != null &&
        now.difference(_lastTransmittedTime!) > const Duration(milliseconds: 250)) {
      return true;
    }

    return false;
  }

  void dispose() {
    if (_connListener != null) {
      JustRideBleService.instance.connectionStateNotifier
          .removeListener(_connListener!);
      _connListener = null;
    }
  }
}
