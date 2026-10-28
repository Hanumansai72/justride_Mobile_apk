import 'device_presence_service.dart';
import '../models/ride_state.dart';
import 'telephony_service.dart';
import '../models/sensor_status.dart';
import 'system_media_bridge.dart';
import '../constants/device_map_config.dart';
import 'device_map_service.dart';
import '../models/device_map_frame.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ble_media_packet.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  RouteWindowSegment? _latestRouteSegment;
  final Map<int, NavContextPacket> _latestContexts = {};
  StreamSubscription<List<int>>? _statusSubscription;
  DateTime? _lastTransmittedTime;
  bool _useJson = false;

  // FIX #2: Guard concurrent discoverServices() calls (not re-entrant on Android;
  // a parallel call resets MTU negotiation and can drop the BLE connection).
  bool _isDiscovering = false;

  // FIX #3: Serialize GATT characteristic writes to prevent queue congestion.
  Future<void> _writeTail = Future<void>.value();
  int _connectionGeneration = 0;
  int _queuedWrites = 0;
  int _navigationGeneration = 0;
  Timer? _mediaTimer;
  Timer? _discoveryRetryTimer;
  bool _mediaBusy = false;
  bool _mediaRefreshPending = false;
  DateTime? _lastMediaSentAt;
  bool _supportsProtocolV1 = false;
  final sensorSupported = ValueNotifier<bool>(false);
  final sensorStatus = ValueNotifier<SensorStatus?>(null);
  Future<bool> requestSensorStatus({bool calibrate = false}) async {
    if (!isReady || !sensorSupported.value) return false;
    return _writeBytes([0x1a, calibrate ? 1 : 0],
        withoutResponse: false, allowFallback: false);
  }

  bool _supportsMaps = false, _mapSending = false, _supportsHud = false;
  int? _sentMapId;
  DateTime _mapRetryAfter = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> _mapWrite(List<int> packet) async {
    final navigation = _navigationGeneration,
        connection = _connectionGeneration;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (navigation != _navigationGeneration ||
          connection != _connectionGeneration) {
        return false;
      }
      if (await _writeBytes(packet,
          withoutResponse: false, allowFallback: false)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  Future<void> _sendMap() async {
    if (!DeviceMapConfig.enabled ||
        !isReady ||
        !_supportsMaps ||
        _mapSending ||
        DateTime.now().isBefore(_mapRetryAfter)) {
      return;
    }
    final map = DeviceMapService.instance.frame.value;
    final nav = NavigationService.instance;
    if (map == null || map.revision != nav.routeRevision || !nav.isNavigating) {
      return;
    }
    final generation = _navigationGeneration,
        connection = _connectionGeneration;
    bool current() =>
        generation == _navigationGeneration &&
        connection == _connectionGeneration &&
        nav.isNavigating &&
        nav.routeRevision == map.revision &&
        DeviceMapService.instance.frame.value == map &&
        isReady;
    _mapSending = true;
    var committed = _sentMapId == map.id;
    final started = DateTime.now();
    try {
      if (!committed) {
        if (!await _mapWrite(map.start)) throw StateError('Map start rejected');
        final mtu = JustRideBleService.instance.connectedDevice?.mtuNow ?? 23;
        for (final packet in map.chunks(mtu)) {
          if (!current()) return;
          if (!await _mapWrite(packet)) throw StateError('Map chunk rejected');
          // A single chunk at a time shares the existing GATT queue with controls.
          await Future<void>.delayed(Duration.zero);
        }
        if (!current()) return;
        if (!await _mapWrite(map.commit)) {
          throw StateError('Map checksum rejected');
        }
        committed = true;
        _sentMapId = map.id;
        if (DeviceMapService.instance.status.value
            .startsWith('Device map transfer')) {
          DeviceMapService.instance.status.value = 'Map ready';
        }
        debugPrint(
            '[DeviceMap] accepted bytes=${map.compressed.length}, transfer_ms=${DateTime.now().difference(started).inMilliseconds}');
      }
      if (current()) {
        final state = nav.currentState;
        if (state.gpsAvailable) {
          final marker = map.marker(
              LatLng(state.currentLatitude, state.currentLongitude),
              state.heading);
          if (marker == null) {
            await _mapWrite([0x19, 4]);
          }
          if (marker != null && !await _mapWrite(marker)) {
            throw StateError('Map position rejected');
          }
        }
      }
    } catch (_) {
      DeviceMapService.instance.status.value =
          'Device map transfer interrupted; retrying';
      _mapRetryAfter = DateTime.now().add(const Duration(seconds: 10));
      _sentMapId = null;
    } finally {
      if (!committed &&
          connection == _connectionGeneration &&
          generation == _navigationGeneration &&
          isReady) {
        await _writeBytes([0x17, ...DeviceMapFrame.word(map.id)],
            withoutResponse: false, allowFallback: false);
      }
      _mapSending = false;
    }
  }

  List<int>? _lastMediaPacket;
  Future<void> _mediaCommandTail = Future<void>.value();

  Future<void> _syncMedia({int? command}) {
    if (command == null) return _performMediaSync();
    // Serialize button presses separately from map/BLE status writes so a
    // slow snapshot transfer cannot drop or hold up the next phone command.
    final generation = _connectionGeneration;
    final pending = _mediaCommandTail.then((_) async {
      if (generation != _connectionGeneration ||
          !isReady ||
          !_supportsProtocolV1) {
        return;
      }
      final snapshot = await readSystemMedia(command: command);
      if (generation != _connectionGeneration) return;
      unawaited(_performMediaSync(snapshot: snapshot, force: true));
    });
    _mediaCommandTail = pending.catchError((Object error) {
      debugPrint('[BleMedia] Command failed: $error');
    });
    return _mediaCommandTail;
  }

  Future<void> _performMediaSync({
    Map<Object?, Object?>? snapshot,
    bool force = false,
  }) async {
    if (!isReady || !_supportsProtocolV1) return;
    if (_mediaBusy) {
      _mediaRefreshPending |= force;
      return;
    }
    _mediaBusy = true;
    final generation = _connectionGeneration;
    try {
      final current = snapshot ?? await readSystemMedia();
      if (generation != _connectionGeneration || !isReady) return;
      final packet = encodeMediaSnapshot(current);
      // The display can reset its media state while the phone snapshot stays
      // unchanged. Explicit refreshes and a heartbeat must bypass deduplication.
      if (force ||
          !listEquals(packet, _lastMediaPacket) ||
          _lastMediaSentAt == null ||
          DateTime.now().difference(_lastMediaSentAt!) >=
              const Duration(seconds: 10)) {
        if (await _writeBytes(packet, withoutResponse: false) &&
            generation == _connectionGeneration) {
          _lastMediaPacket = packet;
          _lastMediaSentAt = DateTime.now();
        }
      }
    } catch (e) {
      debugPrint('[BleMedia] Snapshot unavailable: $e');
      if (generation == _connectionGeneration && isReady) {
        await _writeBytes(encodeMediaSnapshot(const {'state': 7}),
            withoutResponse: false);
      }
    } finally {
      _mediaBusy = false;
      if (_mediaRefreshPending) {
        _mediaRefreshPending = false;
        // Read again so a command issued during a transfer sends current state.
        unawaited(_performMediaSync(force: true));
      }
    }
  }

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

  Future<bool> _writeBytes(List<int> bytes,
      {bool? withoutResponse, bool allowFallback = true}) {
    if (_queuedWrites >= 16) return Future.value(false);
    final generation = _connectionGeneration;
    final navigationGeneration = _navigationGeneration;
    if (_supportsProtocolV1 &&
        bytes.isNotEmpty &&
        ((bytes[0] >= 1 && bytes[0] <= 8) ||
            bytes[0] == 10 ||
            bytes[0] == 11 ||
            bytes[0] == 17 ||
            (bytes[0] >= 0x14 && bytes[0] <= 0x19))) {
      bytes = [
        0x13,
        navigationGeneration & 255,
        (navigationGeneration >> 8) & 255,
        (navigationGeneration >> 16) & 255,
        (navigationGeneration >> 24) & 255,
        ...bytes
      ];
    }
    final chr = _dataChar;
    _queuedWrites++;
    return _enqueueWrite(() async {
      if (generation != _connectionGeneration ||
          navigationGeneration != _navigationGeneration) {
        return false;
      }
      if (chr == null) return false;
      try {
        final useNoResponse =
            withoutResponse ?? chr.properties.writeWithoutResponse;
        await chr.write(
          bytes,
          withoutResponse: useNoResponse,
        );
        return true;
      } catch (e) {
        if (!allowFallback) return false;
        debugPrint(
            '[BleNav] GATT write failed (noResponse=$withoutResponse): $e. Attempting fallback...');
        try {
          if (generation != _connectionGeneration ||
              navigationGeneration != _navigationGeneration) {
            return false;
          }
          final fallbackNoResponse =
              !(withoutResponse ?? chr.properties.writeWithoutResponse);
          await chr.write(
            bytes,
            withoutResponse: fallbackNoResponse,
          );
          debugPrint('[BleNav] GATT fallback write succeeded!');
          return true;
        } catch (e2) {
          debugPrint('[BleNav] Both write modes failed: $e2');
          return false;
        }
      }
    }).whenComplete(() => _queuedWrites--);
  }

  /// Configure whether to send JSON strings instead of compact binary
  void setDebugJsonMode(bool enable) {
    _useJson = enable;
  }

  /// Initializes the service and listens for connection state changes.
  void init() {
    DeviceMapService.instance.status.removeListener(_onMapStatus);
    DeviceMapService.instance.frame.removeListener(_onMapFrame);
    DeviceMapService.instance.frame.addListener(_onMapFrame);
    DeviceMapService.instance.status.addListener(_onMapStatus);
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
    final connectedDevice = JustRideBleService.instance.connectedDevice;
    if (connectedDevice != null &&
        JustRideBleService.instance.isDeviceConnected) {
      _scheduleNavDiscovery(connectedDevice);
    }
  }

  void _onMapStatus() {
    if (!DeviceMapConfig.enabled ||
        !_supportsMaps ||
        !isReady ||
        !NavigationService.instance.isNavigating) {
      return;
    }
    final status = DeviceMapService.instance.status.value;
    final code = status.contains('429')
        ? 3
        : status.contains('unavailable') || status.contains('HTTP')
            ? 2
            : 0;
    unawaited(_writeBytes([0x19, code],
        withoutResponse: false, allowFallback: false));
  }

  void _onMapFrame() {
    unawaited(_sendMap());
  }

  void _scheduleNavDiscovery(BluetoothDevice device) {
    final generation = _connectionGeneration;
    unawaited(() async {
      final ready = await JustRideBleService.instance.waitForConnectionReady();
      if (ready &&
          generation == _connectionGeneration &&
          JustRideBleService.instance.connectedDevice == device &&
          JustRideBleService.instance.isDeviceConnected) {
        await _discoverNavCharacteristics(device);
      }
    }());
  }

  void _retryNavDiscovery(BluetoothDevice device) {
    _discoveryRetryTimer?.cancel();
    final generation = _connectionGeneration;
    _discoveryRetryTimer = Timer(const Duration(seconds: 2), () {
      if (generation == _connectionGeneration &&
          JustRideBleService.instance.connectedDevice == device &&
          JustRideBleService.instance.isDeviceConnected) {
        _scheduleNavDiscovery(device);
      }
    });
  }

  void _onConnectionStateChanged() {
    final state = JustRideBleService.instance.connectionStateNotifier.value;
    if (state == BluetoothConnectionState.connected) {
      final dev = JustRideBleService.instance.connectedDevice;
      if (dev != null) {
        // bluetooth_service.connectDevice still performs service discovery and
        // the initial clock write after the connection event.  Wait for those
        // GATT operations to finish before inspecting navigation characteristics
        // (Android permits only one GATT operation at a time).
        _scheduleNavDiscovery(dev);
      }
    } else {
      ++_connectionGeneration;
      _discoveryRetryTimer?.cancel();
      _discoveryRetryTimer = null;
      _mediaTimer?.cancel();
      _mediaTimer = null;
      _lastMediaPacket = null;
      _lastMediaSentAt = null;
      _mediaRefreshPending = false;
      _pendingTelemetry = null;
      _supportsProtocolV1 = false;
      sensorSupported.value = false;
      sensorStatus.value = null;
      _supportsMaps = false;
      _supportsHud = false;
      _sentMapId = null;
      _lastTransmittedTime = null;
      _statusSubscription?.cancel();
      _statusSubscription = null;
      _dataChar = null;
      _statusChar = null;
      _isDiscovering = false;
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
    _discoveryRetryTimer?.cancel();
    var setupComplete = false;
    final connectionGeneration = _connectionGeneration;
    try {
      List<BluetoothService> services = device.servicesList;
      final hasNavSvc = services.any((svc) => svc.uuid
          .toString()
          .toLowerCase()
          .replaceAll('-', '')
          .contains(navServiceUuid));
      if (!hasNavSvc) {
        debugPrint(
            '[BleNav] Discovering GATT services for ${device.remoteId.str}...');
        services = await device.discoverServices();
      }
      if (connectionGeneration != _connectionGeneration ||
          JustRideBleService.instance.connectedDevice != device) {
        return false;
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
            if (connectionGeneration != _connectionGeneration) return false;
            await _statusSubscription?.cancel();
            _statusSubscription = _statusChar!.onValueReceived.listen((value) {
              if (value.isNotEmpty) {
                if (connectionGeneration == _connectionGeneration &&
                    JustRideBleService.instance.isDeviceConnected) {
                  DevicePresenceService.instance.report(device.remoteId.str);
                }
                if (value[0] == 0x1a) {
                  final parsed = SensorStatus.parse(value);
                  if (parsed != null) sensorStatus.value = parsed;
                  return;
                }
                final status = value[0];
                debugPrint(
                    '[BleNav] Received Status Code: 0x${status.toRadixString(16).padLeft(2, '0')}');
                if (status == 0x14 && value.length == 2) {
                  if (value[1] == 255) {
                    DeviceMapService.instance.showOverview();
                  } else if (value[1] == 254) {
                    DeviceMapService.instance.recenter();
                  } else {
                    DeviceMapService.instance.setZoom(value[1]);
                  }
                } else if (status == 0x1c && value.length == 2) {
                  if (value[1] == 1) {
                    unawaited(TelephonyService.instance.answerCall());
                  }
                  if (value[1] == 2) {
                    unawaited(TelephonyService.instance.rejectCall());
                  }
                } else if (status == 0x12 && value.length == 2) {
                  unawaited(_syncMedia(command: value[1]));
                } else if (status == 0x05) {
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

        if (_statusChar?.properties.read == true) {
          final capabilities = await _statusChar!.read();
          if (connectionGeneration != _connectionGeneration) return false;
          _supportsProtocolV1 = capabilities.length >= 2 &&
              capabilities[0] == 1 &&
              capabilities[1] >= 1;
          _supportsHud = _supportsProtocolV1 &&
              capabilities[1] >= 3 &&
              capabilities.length >= 3 &&
              (capabilities[2] & 2) != 0;
          _supportsMaps = _supportsProtocolV1 &&
              capabilities.length >= 3 &&
              capabilities[1] >= 2;
          unawaited(TelephonyService.instance.syncDisplay());
          sensorSupported.value =
              capabilities.length >= 3 && (capabilities[2] & 1) != 0;
          if (sensorSupported.value) await requestSensorStatus();
        }
        _mediaTimer?.cancel();
        _mediaTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          unawaited(_syncMedia());
          unawaited(_sendMap());
          if (sensorSupported.value &&
              (sensorStatus.value == null ||
                  DateTime.now().difference(sensorStatus.value!.receivedAt) >=
                      const Duration(seconds: 2))) {
            unawaited(requestSensorStatus());
          }
        });
        unawaited(_syncMedia(command: 7));
        setupComplete = true;

        // Sync if navigation is active in any riding state:
        //   NAVIGATING, REROUTING, or PAUSED — not just NAVIGATING
        final navigation = NavigationService.instance;
        if (navigation.currentState.rideState == RideState.arrived) {
          await sendNavArrived(navigation.currentState);
        }
        if (navigation.isNavigating &&
            navigation.currentState.rideState.isActive) {
          await syncState(navigation.currentState);
          final route = navigation.activeRoute;
          final destination = navigation.currentDestination;
          if (route != null &&
              destination != null &&
              route.polylinePoints.isNotEmpty) {
            final state = navigation.currentState;
            final window = RouteWindowTransformer.transform(
              riderPosition:
                  LatLng(state.currentLatitude, state.currentLongitude),
              riderHeadingDeg: state.heading,
              polylinePoints: route.polylinePoints,
              destination: LatLng(destination.latitude, destination.longitude),
              minimumRouteIndex: navigation.routeProgressIndex,
              distanceToManeuverMeters: state.maneuverDistanceMeters,
              followingLegDistanceMeters: state.nextManeuverDistanceMeters,
            );
            await sendRouteSegment(window);
          } else if (_latestRouteSegment != null) {
            await sendRouteSegment(_latestRouteSegment!);
          }
          for (final context in _latestContexts.values.toList()) {
            await sendNavContext(context);
          }
        } else if (JustRideBleService.instance.isAppVisible) {
          // Only resume a saved ride when the rider has opened the app.
          final resumed = await navigation.recalculateAndResumeRoute();
          if (!resumed && connectionGeneration == _connectionGeneration) {
            await sendNavStop(navigation.currentState);
          }
        }
      }
      return ready;
    } catch (e) {
      debugPrint('[BleNav] Error discovering nav service: $e');
      return false;
    } finally {
      if (connectionGeneration == _connectionGeneration) {
        _isDiscovering = false;
        // A failed notification subscription/capability read used to leave
        // isReady true with no media timer and no way to recover until reconnect.
        if (!setupComplete) _retryNavDiscovery(device);
      }
    }
  }

  /// Sends a navigation packet to the ESP32-S3 over BLE with change throttling.
  NavigationState? _pendingTelemetry;
  bool _drainingTelemetry = false;

  Future<bool> sendNavUpdate(
    NavigationState state, {
    BleNavOpCode opCode = BleNavOpCode.navUpdate,
    bool force = false,
  }) async {
    if (force || opCode != BleNavOpCode.navUpdate) {
      return _sendNavUpdate(state, opCode: opCode, force: force);
    }
    unawaited(_sendMap());
    _pendingTelemetry = state;
    if (_drainingTelemetry) return false;
    _drainingTelemetry = true;
    var sent = false;
    try {
      while (_pendingTelemetry != null) {
        final latest = _pendingTelemetry!;
        _pendingTelemetry = null;
        sent = await _sendNavUpdate(latest);
      }
      return sent;
    } finally {
      _drainingTelemetry = false;
    }
  }

  Future<bool> _sendNavUpdate(
    NavigationState state, {
    BleNavOpCode opCode = BleNavOpCode.navUpdate,
    bool force = false,
  }) async {
    final routeGeneration = _navigationGeneration;
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
    if (sent && routeGeneration == _navigationGeneration) {
      _lastTransmittedState = state;
      _lastTransmittedTime = DateTime.now();
      return true;
    }
    return false;
  }

  void beginRouteRevision() {
    ++_navigationGeneration;
    _sentMapId = null;
    _pendingTelemetry = null;
  }

  /// Sends full state sync on reconnection or ride resumption
  Future<void> syncState(NavigationState state) async {
    debugPrint('[BleNav] Sending SYNC_STATE to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.syncState, force: true);
  }

  /// Sends NAV_START when rider begins navigation
  Future<void> sendNavStart(NavigationState state) async {
    ++_navigationGeneration;
    _sentMapId = null;
    _pendingTelemetry = null;
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
    ++_navigationGeneration;
    _pendingTelemetry = null;
    debugPrint('[BleNav] Sending NAV_ARRIVED to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.navArrived, force: true);
  }

  /// Sends NAV_STOP when rider cancels/exits ride
  Future<void> sendNavStop(NavigationState state) async {
    ++_navigationGeneration;
    _sentMapId = null;
    _pendingTelemetry = null;
    debugPrint('[BleNav] Sending NAV_STOP to ESP32...');
    await sendNavUpdate(state, opCode: BleNavOpCode.navStop, force: true);
    _lastTransmittedState = null;
    _latestRouteSegment = null;
    _latestContexts.clear();
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

  /// Sends DIAGNOSTICS self-test request (0x10) to ESP32 via BLE
  Future<bool> sendDiagnosticsRequest() async {
    if (!isReady || _dataChar == null) return false;
    try {
      debugPrint('[BleNav] Sending DIAGNOSTICS request (0x10) to ESP32...');
      return await _writeBytes([0x10], withoutResponse: false);
    } catch (e) {
      debugPrint('[BleNav] Error sending diagnostics request: $e');
      return false;
    }
  }

  /// Sends sliding route window segment (OpCode 0x0B) to ESP32
  Future<bool> sendRouteSegment(RouteWindowSegment segment) async {
    _latestRouteSegment = segment;
    if (!isReady || _dataChar == null || segment.points.isEmpty) return false;

    final packet = RouteSegmentPacket.fromWindow(segment);
    final bytes = packet.toBinary();
    return await _writeBytes(bytes, withoutResponse: false);
  }

  Future<bool> sendNavContext(NavContextPacket context) async {
    if (context.poiType == 0) _latestContexts.clear();
    _latestContexts[context.poiType] = context;
    if (!isReady || _dataChar == null) return false;
    return _writeBytes(context.toBinary(), withoutResponse: false);
  }

  Future<bool> sendCallState(int state, int actions, String caller) async {
    if (!isReady || !_supportsHud) return false;
    final name = hudUtf8(caller, 47);
    return _writeBytes([0x1c, state, actions, name.length, ...name],
        withoutResponse: false, allowFallback: false);
  }

  /// Sends strictly the latest notification (OpCode 0x0F) to the ESP32 HUD display.
  /// Overwrites and replaces any prior notification on the screen.
  Future<bool> sendLatestNotification(String title, String message,
      {String appName = "Alert"}) async {
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
      appName: _supportsHud ? appName : "",
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
    if (current.speedKmh >= 1.5 &&
        (current.heading - last.heading).abs() >= 3.0) {
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
        now.difference(_lastTransmittedTime!) >
            const Duration(milliseconds: 250)) {
      return true;
    }

    return false;
  }

  void dispose() {
    DeviceMapService.instance.status.removeListener(_onMapStatus);
    DeviceMapService.instance.frame.removeListener(_onMapFrame);
    ++_connectionGeneration;
    _discoveryRetryTimer?.cancel();
    _mediaTimer?.cancel();
    _mediaRefreshPending = false;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    if (_connListener != null) {
      JustRideBleService.instance.connectionStateNotifier
          .removeListener(_connListener!);
      _connListener = null;
    }
  }
}
