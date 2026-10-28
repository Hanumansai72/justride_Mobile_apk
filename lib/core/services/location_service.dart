import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/speed_filter.dart';

/// Service responsible for GPS acquisition, speed, heading, and permission management.
///
/// Speed is always passed through [SpeedFilter] before being emitted.
class LocationService with WidgetsBindingObserver {
  LocationService._();
  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _positionSub;
  Timer? _gpsWatchdog;
  Position? _currentPosition;
  Position? _previousPosition;
  bool _isServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;
  DateTime? _lastLiveFixAt;

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
      debugPrint(
          '[LocationService] Current GPS fix is stale or inaccurate. Falling back to last known.');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          _isFreshUsableFix(lastKnown, maxAgeSeconds: 1800)) {
        _onPositionUpdate(lastKnown);
        return lastKnown;
      }
      if (_currentPosition != null) return _currentPosition;
      return null;
    } catch (e) {
      debugPrint('[LocationService] getCurrentPosition error: $e');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          _isFreshUsableFix(lastKnown, maxAgeSeconds: 1800)) {
        _onPositionUpdate(lastKnown);
        return lastKnown;
      }
      if (_currentPosition != null) return _currentPosition;
      return null;
    }
  }

  // ── Continuous Tracking ──────────────────────────────────────────────────

  /// Starts continuous high-frequency location streaming for active ride guidance.
  ///
  /// Uses foreground service notification on Android to keep GPS active.
  /// Uses automotive navigation mode on iOS.
  Timer? _recoveryTimer;
  LocationSettings? _trackingSettings;
  bool _trackingActive = false, _streamNeedsRecovery = false;
  int _trackingGeneration = 0;

  // ── Continuous Tracking ──────────────────────────────────────────────────

  /// Starts continuous high-frequency location streaming for active ride guidance.
  ///
  /// Uses foreground service notification on Android to keep GPS active.
  /// Uses automotive navigation mode on iOS.
  /// Retains foreground settings for the entire ride, including GPS recovery.
  Future<bool> startTracking({
    int distanceFilterMeters = 0,
    int intervalMs = 400,
  }) async {
    final hasPerm = await ensurePermissions();
    if (!hasPerm) return false;

    await stopTracking();
    final trackingGeneration = _trackingGeneration;
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
          notificationText:
              'JustRide active motorcycle navigation is running in background.',
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
      _trackingSettings = settings;
      _trackingActive = true;
      WidgetsBinding.instance.addObserver(this);
      await _startStream(settings);
      if (!_trackingActive || trackingGeneration != _trackingGeneration) {
        return false;
      }
    } catch (e) {
      debugPrint('[LocationService] Unable to start ride location stream: $e');
      if (trackingGeneration == _trackingGeneration) await stopTracking();
      return false;
    }

    // Watchdog: detect loss of satellite fix. Android may batch an otherwise
    // valid foreground-service fix briefly while the screen is off, so avoid
    // declaring GPS lost during a normal bridge/urban-canyon interruption.
    // Accommodates cold start, bridges, intersections, and proactively polls.
    _gpsWatchdog = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!_trackingActive || trackingGeneration != _trackingGeneration) return;
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
          if (_trackingActive &&
              trackingGeneration == _trackingGeneration &&
              fix.accuracy.isFinite &&
              fix.accuracy <= 120.0) {
            _onPositionUpdate(fix);
          }
        } catch (_) {}
      }
    });

    return true;
  }

  Future<void> _startStream(LocationSettings settings) async {
    final generation = _trackingGeneration;
    await _positionSub?.cancel();
    if (!_trackingActive || generation != _trackingGeneration) return;
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _streamNeedsRecovery = false;
        _recoveryTimer?.cancel();
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
      onDone: _scheduleRecovery,
      cancelOnError: false,
    );
  }

  void _scheduleRecovery() {
    _recoveryTimer?.cancel();
    if (!_trackingActive || _trackingSettings == null) return;
    _streamNeedsRecovery = true;
    // Keep the existing foreground service/stream alive while off-screen.
    // Recreating a location FGS from the background may be rejected by Android.
    // Transient errors can recover on the same stream; the watchdog keeps polling.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final generation = _trackingGeneration;
    _recoveryTimer = Timer(const Duration(seconds: 2), () async {
      if (!_trackingActive ||
          generation != _trackingGeneration ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      debugPrint(
          '[LocationService] Recovering GPS with the active ride settings.');
      try {
        await _startStream(_trackingSettings!);
      } catch (e) {
        debugPrint('[LocationService] Recovery failed: $e');
        _scheduleRecovery();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _streamNeedsRecovery) {
      _scheduleRecovery();
    }
  }

  // ── Internal Update Handler ──────────────────────────────────────────────

  void _onPositionUpdate(Position pos) {
    if (!_isFreshUsableFix(pos, maxAgeSeconds: 30) ||
        pos.accuracy > 120 ||
        !pos.latitude.isFinite ||
        !pos.longitude.isFinite ||
        pos.latitude.abs() > 90 ||
        pos.longitude.abs() > 180) {
      isGpsAvailableNotifier.value = false;
      speedKmhNotifier.value = 0;
      return;
    }
    _lastLiveFixAt = DateTime.now();
    _currentPosition = pos;
    isGpsAvailableNotifier.value = true;

    // Respect a valid zero-speed fix. GPS coordinate drift must never
    // override it, and inaccurate/missing speed is not inferred from position.
    final filtered = _speedFilter.process(
      rawSpeedMs: pos.speed,
      speedAccuracy: pos.speedAccuracy,
    );
    speedKmhNotifier.value = filtered ?? 0;

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

  bool _isFreshUsableFix(Position pos, {int maxAgeSeconds = 120}) {
    final age = DateTime.now().toUtc().difference(pos.timestamp.toUtc()).abs();
    return age.inSeconds <= maxAgeSeconds &&
        pos.accuracy.isFinite &&
        pos.accuracy <= 200.0;
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  Future<void> stopTracking() async {
    _trackingActive = false;
    ++_trackingGeneration;
    _trackingSettings = null;
    _streamNeedsRecovery = false;
    WidgetsBinding.instance.removeObserver(this);
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
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
