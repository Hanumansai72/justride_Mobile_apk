import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/speed_filter.dart';
import 'simulator_location_service.dart';

enum LocationSource {
  realGps,
  simulator,
}

/// Service responsible for GPS acquisition, speed, heading, and permission management.
///
/// Supports two transparent modes:
///   1. [LocationSource.realGps] - Actual hardware GPS from device.
///   2. [LocationSource.simulator] - High-frequency WebSocket stream from JustRide Web Ride Simulator.
///
/// Speed is always passed through [SpeedFilter] before being emitted.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Position>? _simSub;
  Timer? _gpsWatchdog;
  Position? _currentPosition;
  Position? _previousPosition;
  bool _isServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;
  static const Duration _maxFreshFixAge = Duration(seconds: 30);
  DateTime? _lastLiveFixAt;

  final ValueNotifier<LocationSource> locationSourceNotifier =
      ValueNotifier<LocationSource>(LocationSource.realGps);

  LocationSource get locationSource => locationSourceNotifier.value;

  void setLocationSource(LocationSource source) {
    if (locationSourceNotifier.value == source) return;
    locationSourceNotifier.value = source;
    debugPrint('[LocationService] Location source switched to: $source');
    if (_positionSub != null || _simSub != null) {
      startTracking(distanceFilterMeters: _activeDistanceFilterMeters);
    }
  }

  /// Stateful speed filter — reused across updates to track previous speed.
  final SpeedFilter _speedFilter = SpeedFilter();

  final ValueNotifier<Position?> positionNotifier =
      ValueNotifier<Position?>(null);

  /// Filtered, display-ready speed in km/h. Always 0.0 when stationary.
  /// Never shows GPS jitter noise.
  final ValueNotifier<double> speedKmhNotifier = ValueNotifier<double>(0.0);

  final ValueNotifier<double> headingNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> isGpsAvailableNotifier = ValueNotifier<bool>(false);

  Position? get currentPosition => _currentPosition;
  bool get isGpsAvailable => isGpsAvailableNotifier.value;

  /// Last known filtered speed in km/h (0.0 if unavailable).
  double get lastSpeedKmh => speedKmhNotifier.value;

  // ── Permissions ─────────────────────────────────────────────────────────

  /// Checks and requests necessary location permissions.
  Future<bool> ensurePermissions() async {
    try {
      _isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isServiceEnabled) {
        debugPrint('[LocationService] Location services are disabled.');
        isGpsAvailableNotifier.value = false;
        return false;
      }

      _permission = await Geolocator.checkPermission();
      if (_permission == LocationPermission.denied) {
        _permission = await Geolocator.requestPermission();
        if (_permission == LocationPermission.denied) {
          debugPrint('[LocationService] Location permissions are denied');
          isGpsAvailableNotifier.value = false;
          return false;
        }
      }

      if (_permission == LocationPermission.deniedForever) {
        debugPrint('[LocationService] Location permissions permanently denied');
        isGpsAvailableNotifier.value = false;
        return false;
      }

      isGpsAvailableNotifier.value = true;
      return true;
    } catch (e) {
      debugPrint('[LocationService] Error ensuring permissions: $e');
      isGpsAvailableNotifier.value = false;
      return false;
    }
  }

  // ── Current Position ─────────────────────────────────────────────────────

  /// Gets immediate current GPS position (high accuracy, up to 10s timeout).
  Future<Position?> getCurrentPosition() async {
    if (locationSource == LocationSource.simulator) {
      final simPacket =
          SimulatorLocationService.instance.latestPacketNotifier.value;
      if (simPacket != null) {
        final simPos = simPacket.toPosition();
        _onPositionUpdate(simPos);
        return simPos;
      }
      await SimulatorLocationService.instance.connect();
      final freshPacket =
          SimulatorLocationService.instance.latestPacketNotifier.value;
      if (freshPacket != null) {
        final simPos = freshPacket.toPosition();
        _onPositionUpdate(simPos);
        return simPos;
      }
      final fallbackPos = Position(
        latitude: 17.4370,
        longitude: 78.5800,
        timestamp: DateTime.now(),
        accuracy: 2.0,
        altitude: 500.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 0.0,
        speedAccuracy: 0.5,
      );
      _onPositionUpdate(fallbackPos);
      return fallbackPos;
    }

    final hasPerm = await ensurePermissions();
    if (!hasPerm) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (_isFreshUsableFix(pos)) {
        _onPositionUpdate(pos);
        return pos;
      }
      debugPrint('[LocationService] Current GPS fix is stale or inaccurate.');
      return null;
    } catch (e) {
      debugPrint('[LocationService] getCurrentPosition error: $e');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && _isFreshUsableFix(lastKnown)) {
        _onPositionUpdate(lastKnown);
        return lastKnown;
      }
      return null;
    }
  }

  // ── Continuous Tracking ──────────────────────────────────────────────────

  /// Starts continuous high-frequency location streaming for active ride guidance.
  ///
  /// Uses foreground service notification on Android to keep GPS active.
  /// Uses automotive navigation mode on iOS.
  int _activeDistanceFilterMeters = 0;
  Timer? _recoveryTimer;

  // ── Continuous Tracking ──────────────────────────────────────────────────

  /// Starts continuous high-frequency location streaming for active ride guidance.
  ///
  /// Uses foreground service notification on Android to keep GPS active.
  /// Uses automotive navigation mode on iOS.
  /// Seamlessly falls back to standard LocationSettings if platform-specific FGS fails.
  Future<bool> startTracking({
    int distanceFilterMeters = 0,
    int intervalMs = 400,
  }) async {
    if (locationSource == LocationSource.simulator) {
      await stopTracking();
      _activeDistanceFilterMeters = distanceFilterMeters;
      _speedFilter.reset();
      _previousPosition = null;
      _lastLiveFixAt = DateTime.now();
      isGpsAvailableNotifier.value = true;

      await SimulatorLocationService.instance.connect();
      _simSub?.cancel();
      _simSub = SimulatorLocationService.instance.positionStream.listen(
        (pos) {
          final packet =
              SimulatorLocationService.instance.latestPacketNotifier.value;
          if (packet != null && !packet.gpsAvailable) {
            isGpsAvailableNotifier.value = false;
            speedKmhNotifier.value = 0.0;
          } else {
            isGpsAvailableNotifier.value = true;
            _onPositionUpdate(pos);
          }
        },
        onError: (err) {
          debugPrint('[LocationService] Simulator stream error: $err');
          isGpsAvailableNotifier.value = false;
          speedKmhNotifier.value = 0.0;
        },
      );
      return true;
    }

    final hasPerm = await ensurePermissions();
    if (!hasPerm) return false;

    await stopTracking();
    _activeDistanceFilterMeters = distanceFilterMeters;
    _speedFilter.reset();
    _previousPosition = null;
    _lastLiveFixAt = DateTime.now();
    isGpsAvailableNotifier.value = true;

    LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        intervalDuration: Duration(milliseconds: intervalMs),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'JustRide active motorcycle navigation is running in background.',
          notificationTitle: 'JustRide Active Navigation',
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      );
    }

    try {
      _startStream(settings);
    } catch (e) {
      debugPrint(
          '[LocationService] Platform-specific settings failed, falling back to standard: $e');
      final fallbackSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      );
      _startStream(fallbackSettings);
    }

    // Watchdog: detect loss of satellite fix. Android may batch an otherwise
    // valid foreground-service fix briefly while the screen is off, so avoid
    // declaring GPS lost during a normal bridge/urban-canyon interruption.
    // Accommodates cold start, bridges, intersections, and proactively polls.
    _gpsWatchdog = Timer.periodic(const Duration(seconds: 4), (_) async {
      final lastFix = _lastLiveFixAt;
      if (lastFix != null &&
          DateTime.now().difference(lastFix) > const Duration(seconds: 45)) {
        if (isGpsAvailableNotifier.value) {
          debugPrint(
              '[LocationService] No live GPS fix for 45s. Marking GPS lost.');
          isGpsAvailableNotifier.value = false;
          speedKmhNotifier.value = 0.0;
        }
        // Attempt one-shot wake-up to prompt Android GPS hardware
        try {
          final fix = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 4),
            ),
          );
          if (fix.accuracy.isFinite && fix.accuracy <= 120.0) {
            _onPositionUpdate(fix);
          }
        } catch (_) {}
      }
    });

    return true;
  }

  void _startStream(LocationSettings settings) {
    _positionSub?.cancel();
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _onPositionUpdate(pos);
        debugPrint('[LocationService] Live fix: '
            '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)} '
            '±${pos.accuracy.toStringAsFixed(0)}m '
            '${speedKmhNotifier.value.toStringAsFixed(1)}km/h');
      },
      onError: (e) {
        debugPrint('[LocationService] GPS stream error: $e');
        isGpsAvailableNotifier.value = false;
        speedKmhNotifier.value = 0.0;
        _scheduleRecovery();
      },
      cancelOnError: false,
    );
  }

  void _scheduleRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(seconds: 2), () {
      debugPrint(
          '[LocationService] Attempting GPS stream auto-recovery with standard settings...');
      try {
        final fallbackSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _activeDistanceFilterMeters,
        );
        _startStream(fallbackSettings);
      } catch (e) {
        debugPrint('[LocationService] Recovery failed: $e');
      }
    });
  }

  // ── Internal Update Handler ──────────────────────────────────────────────

  void _onPositionUpdate(Position pos) {
    _lastLiveFixAt = DateTime.now();
    _currentPosition = pos;
    isGpsAvailableNotifier.value = true;

    // ── Speed: use GPS Doppler when trustworthy, otherwise displacement ──
    // SpeedFilter applies:
    //   1. m/s → km/h conversion
    //   2. Stationary deadband (< 2.5 km/h → 0.0)
    //   3. Spike rejection (> 80 km/h jump → use last valid)
    //   4. Accuracy check (speedAccuracy > 5 m/s → 0.0)
    final distanceSpeedMs = _calculateDistanceSpeedMs(pos);
    final rawSpeedIsUsable = pos.speed.isFinite &&
        pos.speed >= 0.5 &&
        (pos.speedAccuracy.isNaN || pos.speedAccuracy <= 5.0);
    final chosenSpeedMs = rawSpeedIsUsable ? pos.speed : distanceSpeedMs;
    final filtered = _speedFilter.process(
      rawSpeedMs: chosenSpeedMs,
      // A displacement speed is derived from two GPS positions, so the phone
      // supplied Doppler-accuracy field must not invalidate it.
      speedAccuracy: rawSpeedIsUsable ? pos.speedAccuracy : null,
    );
    // filtered is null only if speed is NaN/infinite (GPS totally invalid)
    speedKmhNotifier.value = filtered ?? 0.0;

    // ── Heading: vector bearing from movement or sensor ──────────────────
    final kmh = speedKmhNotifier.value;
    if (_previousPosition != null && kmh >= 1.5) {
      final dist = Geolocator.distanceBetween(
        _previousPosition!.latitude,
        _previousPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (dist >= 0.8) {
        final calcBearing = Geolocator.bearingBetween(
          _previousPosition!.latitude,
          _previousPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final normalizedBearing = (calcBearing + 360.0) % 360.0;
        // Prefer calculated vector bearing over hardware sensor when moving,
        // as hardware compass suffers from magnetic jitter on motorcycles.
        if (pos.heading <= 0.0 || pos.heading.isNaN) {
          headingNotifier.value = normalizedBearing;
        } else {
          headingNotifier.value = pos.heading;
        }
      }
    } else if (pos.heading > 0 && !pos.heading.isNaN) {
      headingNotifier.value = pos.heading;
    }

    _previousPosition = pos;

    // Publish only after speed and heading have been derived. NavigationService
    // listens to this notifier synchronously; publishing earlier made it read
    // the previous sample (commonly 0 km/h) and send stale telemetry to the HUD.
    positionNotifier.value = pos;
  }

  /// Derives speed from distance/time when Android reports zero, -1, or poor
  /// Doppler accuracy. A small movement threshold avoids reporting GPS drift
  /// as motorcycle motion while parked.
  double? _calculateDistanceSpeedMs(Position pos) {
    final previous = _previousPosition;
    if (previous == null) return null;

    final elapsedMs =
        pos.timestamp.difference(previous.timestamp).inMilliseconds;
    if (elapsedMs < 500 || elapsedMs > 15000) return null;

    final distanceMeters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      pos.latitude,
      pos.longitude,
    );
    final minMotionMeters =
        2.0 + ((previous.accuracy + pos.accuracy).clamp(0.0, 20.0) * 0.25);
    if (distanceMeters < minMotionMeters) return 0.0;

    final speedMs = distanceMeters / (elapsedMs / 1000.0);
    return speedMs.isFinite && speedMs <= 70.0 ? speedMs : null;
  }

  bool _isFreshUsableFix(Position pos) {
    final age = DateTime.now().toUtc().difference(pos.timestamp.toUtc()).abs();
    return age.inSeconds <= 120 &&
        pos.accuracy.isFinite &&
        pos.accuracy <= 200.0;
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  Future<void> stopTracking() async {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    await _simSub?.cancel();
    _simSub = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _lastLiveFixAt = null;
    _previousPosition = null;
    _speedFilter.reset();
  }

  void dispose() {
    stopTracking();
  }
}
