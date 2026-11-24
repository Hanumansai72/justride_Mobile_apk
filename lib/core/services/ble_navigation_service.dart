import 'notification_listener_service.dart';
import 'device_presence_service.dart';
import '../models/ride_state.dart';
import 'telephony_service.dart';
import '../models/sensor_status.dart';
import '../models/power_status.dart';
import 'system_media_bridge.dart';
import '../constants/device_map_config.dart';
import 'device_map_service.dart';
import '../models/device_map_frame.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/ble_media_packet.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ble_navigation_packet.dart';
import '../models/navigation_state.dart';
import '../utils/route_window_transformer.dart';
import 'bluetooth_service.dart';
import 'navigation_service.dart';
import 'ride_history_service.dart';
import 'location_service.dart';

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
  Map<Object?, Object?>? _pendingMediaSnapshot;
  DateTime? _lastMediaSentAt;
  bool _mediaEventsActive = false;
  Map<Object?, Object?>? _mediaSnapshot;
  DateTime? _mediaSnapshotAt;
  bool _supportsProtocolV1 = false;
  final sensorSupported = ValueNotifier<bool>(false);
  final sensorStatus = ValueNotifier<SensorStatus?>(null);
  final powerSupported = ValueNotifier<bool>(false);
  final powerStatus = ValueNotifier<PowerStatus?>(null);
  int? firmwareChipId;
  final firmwareVersion = ValueNotifier<String?>(null);
  bool signedOtaSupported = false;
  bool _otaBusy = false;
  Future<void> prepareForOta() async {
    _otaBusy = true;
    await _writeTail;
  }

  void finishOta() {
    _otaBusy = false;
  }

  bool _supportsRiderOptions = false;
  bool _supportsRichMedia = false;
  bool get photoUploadSupported => firmwareChipId == 0;
  bool _supportsSleepTimeout = false;
  bool _supportsRideCheckpoint = false;
  bool _supportsRouteTraffic = false;
  bool _writingRideCheckpoint = false;
  ({
    int rideId,
    int revision,
    int remaining,
    DateTime sentAt
  })? _lastRideCheckpoint;
  final sleepMinutes = ValueNotifier<int>(5);
  final mediaState = ValueNotifier<int>(6);
  static List<int> encodeRiderOptions(
          bool glove, bool automatic, int manual, int minutes,
          {required bool supportsSleep}) =>
      [
        0x1e,
        glove ? 1 : 0,
        automatic ? 1 : 0,
        manual.clamp(0, 100),
        if (supportsSleep) [0, 1, 5, 10].contains(minutes) ? minutes : 5,
      ];
  Future<bool> setSleepMinutes(int minutes) async {
    if (![0, 1, 5, 10].contains(minutes)) throw ArgumentError.value(minutes);
    if (!_supportsSleepTimeout || !await _sendRiderOptions(minutes: minutes))
      return false;
    sleepMinutes.value = minutes;
    await (await SharedPreferences.getInstance())
        .setInt('device_sleep_minutes', minutes);
    return true;
  }

  Future<void> connectMusic() async {
    final snapshot = await readSystemMedia();
    mediaState.value = (snapshot['state'] as num? ?? 7).toInt().clamp(0, 7);
    if (mediaState.value == 1) await readSystemMedia(command: 8);
    final device = JustRideBleService.instance.connectedDevice;
    if (!isReady && device != null) await _discoverNavCharacteristics(device);
    await _syncMedia(command: 7);
  }

  final gloveMode = ValueNotifier<bool>(false);
  final automaticBrightness = ValueNotifier<bool>(false);
  final manualBrightness = ValueNotifier<int>(80);
  Future<bool> _sendRiderOptions(
      {bool? glove, bool? automatic, int? minutes}) async {
    if (!_supportsRiderOptions) return false;
    return _writeBytes(
        encodeRiderOptions(
            glove ?? gloveMode.value,
            automatic ?? automaticBrightness.value,
            manualBrightness.value,
            minutes ?? sleepMinutes.value,
            supportsSleep: _supportsSleepTimeout),
        withoutResponse: false);
  }

  Future<bool> setAutomaticBrightness(bool enabled) async {
    if (!await _sendRiderOptions(automatic: enabled)) return false;
    automaticBrightness.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('device_auto_brightness', enabled);
    return true;
  }

  Future<void> _rememberManualBrightness(int value) async {
    automaticBrightness.value = false;
    manualBrightness.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('device_auto_brightness', false);
    await prefs.setInt('device_manual_brightness', value);
  }

  String? _lastDestination;
  Future<bool> setGloveMode(bool enabled) async {
    if (!await _sendRiderOptions(glove: enabled)) return false;
    gloveMode.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('device_glove_mode', enabled);
    return true;
  }

  List<int>? _lastTripStats;
  Future<void> _syncHomeStats() async {
    if (!_supportsRichMedia || !isReady) return;
    final history = RideHistoryService.instance;
    if (!history.hasCurrentTotal) {
      unawaited(history.refreshTotalDistance());
      return;
    }
    final packet = encodeHomeDistance(history.totalDistanceMeters.value!);
    if (listEquals(packet, _lastTripStats)) return;
    if (await _writeBytes(packet, withoutResponse: false))
      _lastTripStats = packet;
  }

  Future<void> _syncDestination() async {
    if (!_supportsRiderOptions || !isReady) return;
    final name = NavigationService.instance.isNavigating
        ? NavigationService.instance.currentDestination?.displayTitle ?? ''
        : '';
    if (name == _lastDestination) return;
    final label = <int>[];
    for (final rune in name.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (label.length + bytes.length > 31) break;
      label.addAll(bytes);
    }
    if (await _writeBytes([0x1f, label.length, ...label],
        withoutResponse: false)) _lastDestination = name;
  }

  Timer? _powerExpiry;
  Future<bool> requestPowerStatus() async {
    if (!isReady || !powerSupported.value) return false;
    return _writeBytes([0x1d, 0], withoutResponse: false, allowFallback: false);
  }

  void _acceptPowerStatus(List<int> bytes) {
    final parsed = PowerStatus.parse(bytes);
    if (parsed == null) return;
    powerStatus.value = parsed;
    _powerExpiry?.cancel();
    _powerExpiry = Timer(const Duration(seconds: 15), () {
      if (identical(powerStatus.value, parsed)) powerStatus.value = null;
    });
  }

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
    final camera = nav.deviceCameraGeneration;
    bool current() =>
        generation == _navigationGeneration &&
        connection == _connectionGeneration &&
        camera == nav.deviceCameraGeneration &&
        nav.isNavigating &&
        nav.routeRevision == map.revision &&
        DeviceMapService.instance.frame.value == map &&
        isReady;
    _mapSending = true;
    var committed = _sentMapId == map.id;
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
      if (DeviceMapService.instance.frame.value != map && isReady) {
        unawaited(_sendMap());
      }
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
      if (command == 7) _mediaEventsActive = await startSystemMediaUpdates();
      if (generation != _connectionGeneration) return;
      unawaited(_performMediaSync(snapshot: snapshot, force: true));
    });
    _mediaCommandTail = pending.catchError((Object error) {});
    return _mediaCommandTail;
  }

  Future<void> _performMediaSync({
    Map<Object?, Object?>? snapshot,
    bool force = false,
  }) async {
    if (!isReady || !_supportsProtocolV1) return;
    if (_mediaBusy) {
      if (snapshot != null)
        _pendingMediaSnapshot = Map<Object?, Object?>.of(snapshot);
      _mediaRefreshPending |= force;
      return;
    }
    _mediaBusy = true;
    final generation = _connectionGeneration;
    try {
      Map<Object?, Object?> current;
      final cachedAt = _mediaSnapshotAt;
      if (snapshot == null &&
          _mediaEventsActive &&
          _mediaSnapshot != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt).inSeconds < 10) {
        current = Map<Object?, Object?>.of(_mediaSnapshot!);
        if (current['state'] == 4) {
          final elapsed = (current['elapsedSeconds'] as num? ?? 0).toInt() +
              DateTime.now().difference(cachedAt).inSeconds;
          final duration = (current['durationSeconds'] as num? ?? 0).toInt();
          current['elapsedSeconds'] =
              duration > 0 ? elapsed.clamp(0, duration) : elapsed;
        }
      } else {
        current = snapshot ?? await readSystemMedia();
        if (generation != _connectionGeneration || !isReady) return;
        _mediaSnapshot = Map<Object?, Object?>.of(current);
        _mediaSnapshotAt = DateTime.now();
      }
      if (generation != _connectionGeneration || !isReady) return;
      mediaState.value = (current['state'] as num? ?? 7).toInt().clamp(0, 7);
      final packet =
          encodeMediaSnapshot(current, includeTimeline: _supportsRichMedia);
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
      if (generation == _connectionGeneration && isReady) {
        await _writeBytes(encodeMediaSnapshot(const {'state': 7}),
            withoutResponse: false);
      }
    } finally {
      _mediaBusy = false;
      if (_mediaRefreshPending) {
        _mediaRefreshPending = false;
        final pending = _pendingMediaSnapshot;
        _pendingMediaSnapshot = null;
        unawaited(_performMediaSync(snapshot: pending, force: true));
      }
    }
  }

  Future<bool>? _brightnessWrite;
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
    if (_otaBusy || _queuedWrites >= 16) return Future.value(false);
    final generation = _connectionGeneration;
    final navigationGeneration = _navigationGeneration;
    if (_supportsProtocolV1 &&
        bytes.isNotEmpty &&
        ((bytes[0] >= 1 && bytes[0] <= 8) ||
            bytes[0] == 10 ||
            bytes[0] == 11 ||
            bytes[0] == 17 ||
            bytes[0] == 0x1f ||
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
        if (!allowFallback || withoutResponse == false) return false;

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

          return true;
        } catch (e2) {
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
    setSystemMediaListener((snapshot) {
      if (isReady && !_otaBusy)
        unawaited(_performMediaSync(snapshot: snapshot, force: true));
    });
    unawaited(SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt('device_sleep_minutes') ?? 5;
      sleepMinutes.value = [0, 1, 5, 10].contains(saved) ? saved : 5;
    }));
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
      _mediaEventsActive = false;
      _mediaSnapshot = null;
      _mediaSnapshotAt = null;
      _pendingMediaSnapshot = null;
      unawaited(stopSystemMediaUpdates());
      _mediaRefreshPending = false;
      _pendingTelemetry = null;
      _supportsProtocolV1 = false;
      sensorSupported.value = false;
      sensorStatus.value = null;
      powerSupported.value = false;
      firmwareChipId = null;
      firmwareVersion.value = null;
      signedOtaSupported = false;
      _supportsRiderOptions = false;
      _supportsRichMedia = false;
      _supportsSleepTimeout = false;
      _supportsRideCheckpoint = false;
      _supportsRouteTraffic = false;
      _lastRideCheckpoint = null;
      mediaState.value = 6;
      _lastDestination = null;
      _lastTripStats = null;
      powerStatus.value = null;
      _powerExpiry?.cancel();
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
        services = await device.discoverServices();
      }
      if (connectionGeneration != _connectionGeneration ||
          JustRideBleService.instance.connectedDevice != device) {
        return false;
      }

      for (final svc in services) {
        final sUuid = svc.uuid.toString().toLowerCase().replaceAll('-', '');
        if (sUuid.contains(navServiceUuid)) {
          for (final chr in svc.characteristics) {
            final cUuid = chr.uuid.toString().toLowerCase().replaceAll('-', '');
            if (cUuid.contains(navDataCharUuid)) {
              _dataChar = chr;
            } else if (cUuid.contains(navStatusCharUuid)) {
              _statusChar = chr;
            }
          }
        }
      }

      final ready = _dataChar != null;
      if (ready) {
        // Listen to Navigation Status (0xFF32)
        if (_statusChar != null) {
          if (_statusChar!.properties.notify) {
            await _statusChar!.setNotifyValue(true);
            if (connectionGeneration != _connectionGeneration) return false;
            await _statusSubscription?.cancel();
            _statusSubscription = _statusChar!.onValueReceived.listen((value) {
              if (connectionGeneration != _connectionGeneration ||
                  !JustRideBleService.instance.isDeviceConnected) return;
              if (value.isNotEmpty) {
                if (value[0] == 0x20 && value.length == 2 && value[1] <= 100) {
                  unawaited(_rememberManualBrightness(value[1]));
                  return;
                }
                if (value[0] == 0x1d) {
                  _acceptPowerStatus(value);
                  return;
                }
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

                if (status == 0x14 && value.length == 2) {
                  if (![14, 15, 16, 17, 254, 255].contains(value[1])) return;
                  NavigationService.instance.selectDeviceView(value[1]);
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
          }
        }

        if (_statusChar?.properties.read == true) {
          final capabilities = await _statusChar!.read();
          if (connectionGeneration != _connectionGeneration) return false;
          _supportsProtocolV1 = capabilities.length >= 2 &&
              capabilities[0] == 1 &&
              capabilities[1] >= 1;
          firmwareChipId = _supportsProtocolV1
              ? (capabilities.length >= 4 ? capabilities[3] : 0)
              : null;
          _supportsHud = _supportsProtocolV1 &&
              capabilities[1] >= 3 &&
              capabilities.length >= 3 &&
              (capabilities[2] & 2) != 0;
          _supportsMaps = _supportsProtocolV1 &&
              capabilities.length >= 3 &&
              capabilities[1] >= 2;
          signedOtaSupported =
              capabilities.length >= 5 && (capabilities[4] & 1) != 0;
          _supportsRideCheckpoint = firmwareChipId == 9 &&
              capabilities.length >= 5 &&
              (capabilities[4] & 2) != 0;
          _supportsRouteTraffic = firmwareChipId == 9 &&
              capabilities.length >= 5 &&
              (capabilities[4] & 4) != 0;
          firmwareVersion.value = capabilities.length > 5
              ? utf8.decode(
                  capabilities.skip(5).takeWhile((b) => b != 0).toList(),
                  allowMalformed: true)
              : null;
          _supportsRichMedia = _supportsProtocolV1 && capabilities[1] >= 5;
          _supportsRiderOptions = _supportsProtocolV1 && capabilities[1] >= 4;
          _supportsSleepTimeout = _supportsProtocolV1 && capabilities[1] >= 6;
          final prefs = await SharedPreferences.getInstance();
          if (connectionGeneration != _connectionGeneration) return false;
          gloveMode.value = prefs.getBool('device_glove_mode') ?? false;
          automaticBrightness.value =
              prefs.getBool('device_auto_brightness') ?? false;
          manualBrightness.value =
              (prefs.getInt('device_manual_brightness') ?? 80).clamp(0, 100);
          final savedSleep = prefs.getInt('device_sleep_minutes') ?? 5;
          sleepMinutes.value =
              [0, 1, 5, 10].contains(savedSleep) ? savedSleep : 5;
          await _sendRiderOptions();
          unawaited(TelephonyService.instance.syncDisplay());
          sensorSupported.value =
              capabilities.length >= 3 && (capabilities[2] & 1) != 0;
          if (sensorSupported.value) await requestSensorStatus();
          powerSupported.value =
              capabilities.length >= 3 && (capabilities[2] & 4) != 0;
          if (powerSupported.value) await requestPowerStatus();
        }
        _mediaTimer?.cancel();
        _mediaTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (_otaBusy) return;
          final navigation = NavigationService.instance;
          if (navigation.isNavigating) {
            unawaited(sendNavUpdate(navigation.currentState));
            unawaited(_sendRideCheckpoint());
          }
          if (powerSupported.value &&
              (powerStatus.value == null ||
                  DateTime.now().difference(powerStatus.value!.receivedAt) >=
                      const Duration(seconds: 7))) {
            unawaited(requestPowerStatus());
          }
          unawaited(_syncDestination());
          unawaited(_syncHomeStats());
          unawaited(_syncMedia());
          unawaited(_sendMap());
        });
        unawaited(_syncMedia(command: 7));
        setupComplete = true;
        isNavCharReadyNotifier.value = true;

        // Sync if navigation is active in any riding state:
        //   NAVIGATING, REROUTING, or PAUSED — not just NAVIGATING
        final navigation = NavigationService.instance;
        if (navigation.currentState.rideState == RideState.arrived) {
          await sendNavArrived(navigation.currentState);
        } else if (navigation.isNavigating &&
            navigation.currentState.rideState.isActive) {
          await syncState(navigation.currentState);
          final route = navigation.activeRoute;
          final destination = navigation.currentDestination;
          if (route != null &&
              destination != null &&
              route.polylinePoints.isNotEmpty) {
            final window = navigation.currentDeviceRouteWindow();
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
        } else if (_supportsRideCheckpoint) {
          await sendNavStop(navigation.currentState);
        }
      }
      return ready;
    } catch (e) {
      return false;
    } finally {
      if (connectionGeneration == _connectionGeneration) {
        _isDiscovering = false;
        // A failed notification subscription/capability read used to leave
        // isReady true with no media timer and no way to recover until reconnect.
        if (!setupComplete) {
          isNavCharReadyNotifier.value = false;
          _retryNavDiscovery(device);
        }
      }
    }
  }

  Future<void> _sendRideCheckpoint() async {
    if (!_supportsRideCheckpoint || !isReady || _writingRideCheckpoint) return;
    final nav = NavigationService.instance;
    final state = nav.currentState;
    final rideId = nav.activeRideCheckpointId;
    if (rideId == null ||
        !nav.isNavigating ||
        !state.rideState.isActive ||
        state.rerouting ||
        !state.remainingDistanceMeters.isFinite) {
      return;
    }

    final revision = nav.routeRevision;
    final remaining = state.remainingDistanceMeters.round().clamp(0, 10000000);
    final now = DateTime.now();
    final last = _lastRideCheckpoint;
    if (last != null &&
        last.rideId == rideId &&
        last.revision == revision &&
        (now.difference(last.sentAt) < const Duration(minutes: 1) ||
            last.remaining - remaining < 250)) {
      return;
    }

    final packet = ByteData(21)
      ..setUint8(0, 0x23)
      ..setUint64(1, rideId, Endian.little)
      ..setUint32(9, revision, Endian.little)
      ..setUint32(13, remaining, Endian.little)
      ..setUint32(17, now.millisecondsSinceEpoch ~/ 1000, Endian.little);
    final connection = _connectionGeneration;
    _writingRideCheckpoint = true;
    try {
      if (await _writeBytes(packet.buffer.asUint8List(),
              withoutResponse: false) &&
          connection == _connectionGeneration) {
        _lastRideCheckpoint = (
          rideId: rideId,
          revision: revision,
          remaining: remaining,
          sentAt: now
        );
      }
    } finally {
      _writingRideCheckpoint = false;
    }
  }

  NavigationState? _pendingTelemetry;
  bool _drainingTelemetry = false;

  /// Sends a navigation packet to the ESP32-S3 over BLE with change throttling.
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

    // Keep the phone's long GPS recovery window, but suppress stale HUD guidance.
    if (state.rideState.isActive &&
        !LocationService.instance.hasFreshNavigationFix) {
      state = state.copyWith(gpsAvailable: false, speedKmh: 0);
    }
    // Throttle check — only for regular updates, not for forced ops.
    if (!force && opCode == BleNavOpCode.navUpdate) {
      if (!_shouldSendUpdate(state)) {
        return false;
      }
    }

    final packet = BleNavigationPacket.fromState(state, opCode: opCode);
    final bytes = _useJson ? packet.toJsonBytes() : packet.toBinary();
    final sent = await _writeBytes(
      bytes,
      withoutResponse: false,
      allowFallback: false,
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
    _lastDestination = null;
    _sentMapId = null;
    _pendingTelemetry = null;
  }

  /// Sends full state sync on reconnection or ride resumption
  Future<void> syncState(NavigationState state) async {
    if (await sendNavUpdate(state,
        opCode: BleNavOpCode.syncState, force: true)) {
      unawaited(_sendRideCheckpoint());
    }
  }

  /// Sends NAV_START when rider begins navigation
  Future<bool> sendNavStart(NavigationState state) async {
    ++_navigationGeneration;
    _sentMapId = null;
    _pendingTelemetry = null;

    return sendNavUpdate(state, opCode: BleNavOpCode.navStart, force: true);
  }

  /// Sends NAV_REROUTE when route recalculation occurs
  Future<void> sendNavReroute(NavigationState state) async {
    await sendNavUpdate(state, opCode: BleNavOpCode.navReroute, force: true);
  }

  /// Sends NAV_ARRIVED when destination reached
  Future<void> sendNavArrived(NavigationState state) async {
    ++_navigationGeneration;
    _pendingTelemetry = null;

    if (!await sendNavUpdate(state,
        opCode: BleNavOpCode.navArrived, force: true)) return;
    final ride = NavigationService.instance.lastCompletedSession;
    if (ride == null || !_supportsRichMedia || !isReady) return;
    await _writeBytes(
      encodeRideSummary(
          ride.distanceMeters, ride.durationSeconds, ride.averageSpeedKmh),
      withoutResponse: false,
    );
  }

  /// Sends NAV_STOP when rider cancels/exits ride
  Future<void> sendNavStop(NavigationState state) async {
    ++_navigationGeneration;
    _sentMapId = null;
    _pendingTelemetry = null;

    await sendNavUpdate(state, opCode: BleNavOpCode.navStop, force: true);
    _lastTransmittedState = null;
    _latestRouteSegment = null;
    _latestContexts.clear();
  }

  /// Sends immediate standalone NAV_CANCEL to reset the display back to idle
  Future<bool> sendNavCancel() async {
    if (!isReady || _dataChar == null) return false;
    try {
      final sent = await _writeBytes(
        [BleNavOpCode.navCancel.value],
        withoutResponse: false,
      );
      if (!sent) return false;
      _lastTransmittedState = null;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Controls ESP32 display brightness remotely (0 to 100%)
  Future<bool> sendSetBrightness(int brightnessPct) async {
    _pendingBrightnessPct = brightnessPct.clamp(0, 100).toInt();
    final pending = _brightnessWrite;
    if (pending != null) return pending;
    final write = _drainBrightness();
    _brightnessWrite = write;
    try {
      return await write;
    } finally {
      _brightnessWrite = null;
    }
  }

  Future<bool> _drainBrightness() async {
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

        if (!await _writeBytes(
          [BleNavOpCode.setBrightness.value, brightness],
          withoutResponse: false,
        )) {
          success = false;
          break;
        }
        await _rememberManualBrightness(brightness);
      }
    } catch (e) {
      success = false;
    }
    return success;
  }

  /// Restarts the ESP32 microcontroller cleanly via BLE
  Future<bool> sendRestartDevice() async {
    if (!isReady || _dataChar == null) return false;
    try {
      return await _writeBytes(
        [BleNavOpCode.restartDevice.value],
        withoutResponse: false,
      );
    } catch (e) {
      return false;
    }
  }

  /// Resets ESP32 device settings to factory defaults via BLE
  Future<bool> sendResetDevice() async {
    if (!isReady || _dataChar == null) return false;
    try {
      final sent = await _writeBytes(
        [BleNavOpCode.resetDevice.value],
        withoutResponse: false,
      );
      if (!sent) return false;
      gloveMode.value = false;
      sleepMinutes.value = 5;
      await _rememberManualBrightness(70);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('device_glove_mode', false);
      await prefs.setInt('device_sleep_minutes', 5);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sends DIAGNOSTICS self-test request (0x10) to ESP32 via BLE
  Future<bool> sendDiagnosticsRequest() async {
    if (!isReady || _dataChar == null) return false;
    try {
      return await _writeBytes([0x10], withoutResponse: false);
    } catch (e) {
      return false;
    }
  }

  /// Sends sliding route window segment (OpCode 0x0B) to ESP32
  RouteWindowSegment? _pendingRoute;
  bool _routeSending = false;
  Future<bool> sendRouteSegment(RouteWindowSegment segment) async {
    _latestRouteSegment = segment;
    if (!isReady || _dataChar == null || segment.points.isEmpty) return false;
    _pendingRoute = segment;
    if (_routeSending) return false;
    _routeSending = true;
    final generation = _navigationGeneration,
        connection = _connectionGeneration;
    var sent = false;
    try {
      while (_pendingRoute != null &&
          generation == _navigationGeneration &&
          connection == _connectionGeneration &&
          isReady) {
        final latest = _pendingRoute!;
        _pendingRoute = null;
        sent = await _writeBytes(
            RouteSegmentPacket.fromWindow(latest)
                .toBinary(includeTraffic: _supportsRouteTraffic),
            withoutResponse: false);
        if (!sent) break;
      }
      return sent;
    } finally {
      _routeSending = false;
      final pending = _pendingRoute;
      _pendingRoute = null;
      if (pending != null && isReady) unawaited(sendRouteSegment(pending));
    }
  }

  Future<bool> sendNavContext(NavContextPacket context) async {
    if (context.poiType == 0) _latestContexts.clear();
    _latestContexts[context.poiType] = context;
    if (!isReady || _dataChar == null) return false;
    return _writeBytes(context.toBinary(), withoutResponse: false);
  }

  Future<bool> sendCallState(int state, int actions, String caller,
      {String number = ''}) async {
    if (!isReady || !_supportsHud) return false;
    final name = hudUtf8(caller, 47);
    final phone = hudUtf8(number, 24);
    return _writeBytes([
      0x1c,
      state,
      actions,
      name.length,
      ...name,
      if (_supportsRichMedia) ...[phone.length, ...phone]
    ], withoutResponse: false, allowFallback: false);
  }

  /// Sends strictly the latest notification (OpCode 0x0F) to the ESP32 HUD display.
  /// Overwrites and replaces any prior notification on the screen.
  Future<bool> sendLatestNotification(String title, String message,
      {String appName = "Alert", String? packageName}) async {
    final notifications = NotificationListenerService.instance;
    await notifications.settingsReady;
    if (!notifications.allowsAppNotification(packageName)) return false;
    final device = JustRideBleService.instance.connectedDevice;
    if (device == null) {
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
      return false;
    }
    if (!notifications.allowsAppNotification(packageName)) return false;
    final packet = LatestNotificationPacket(
      title: title,
      message: message,
      appName: _supportsHud ? appName : "",
    );
    final bytes = packet.toBinary();
    try {
      return await _writeBytes(bytes, withoutResponse: false);
    } catch (e) {
      return false;
    }
  }

  /// Sends a short group-safety alert outside the phone-notification allowlist.
  /// During navigation, defer it until the rider is clear of an active turn.
  Future<bool> sendRideSafetyAlert(String title, String message) async {
    if (!isReady || !_supportsHud) return false;
    final navigation = NavigationService.instance;
    if (navigation.isNavigating) {
      final state = navigation.currentState;
      if (!state.gpsAvailable ||
          state.rerouting ||
          state.maneuverDistanceMeters <= 120 ||
          state.maneuverState == 'TURN_ACTIVE' ||
          state.maneuverState == 'TURN_PREVIEW') return false;
    }
    final device = JustRideBleService.instance.connectedDevice;
    if (device == null) return false;
    for (var attempt = 0;
        _dataChar == null && _isDiscovering && attempt < 8;
        attempt++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (_dataChar == null) await _discoverNavCharacteristics(device);
    if (_dataChar == null) return false;
    try {
      final packet = LatestNotificationPacket(
        title: title,
        message: message,
        appName: 'Group Ride',
      );
      return await _writeBytes(packet.toBinary(), withoutResponse: false);
    } catch (_) {
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
    setSystemMediaListener(null);
    unawaited(stopSystemMediaUpdates());
    _mediaEventsActive = false;
    _powerExpiry?.cancel();
    powerStatus.value = null;
    powerSupported.value = false;
    firmwareChipId = null;
    _supportsRouteTraffic = false;
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
