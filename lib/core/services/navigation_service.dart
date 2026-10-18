import '../constants/device_map_config.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/destination.dart';
import '../models/navigation_state.dart';
import '../models/navigation_session.dart';
import '../models/ride_state.dart';
import '../models/ble_navigation_packet.dart';
import '../utils/speed_filter.dart';
import '../utils/gps_accuracy_filter.dart';
import '../utils/maneuver_state_machine.dart';
import '../utils/route_window_transformer.dart';
import '../utils/off_route_detector.dart';
import 'google_maps_service.dart';
import 'location_service.dart';
import 'simulator_location_service.dart';
import 'ble_navigation_service.dart';
import 'bluetooth_service.dart';
import 'ride_history_service.dart';

/// Central owner of the JustRide navigation session.
///
/// Architecture:
///   LocationService  →  NavigationService  →  NavigationState  →  UI / BLE
///
/// Rules enforced here:
///   • Speed is ALWAYS sourced from LocationService (SpeedFilter applied there)
///   • Speed is 0.0 when stationary or GPS unavailable
///   • Google APIs are called only for route calculation and rerouting
///   • NavigationState is the one source of truth — no other component owns state
class NavigationService {
  NavigationService._() : _routeLoader = null;
  @visibleForTesting
  NavigationService.testing(
      Future<NavigationRoute?> Function(LatLng, LatLng) routeLoader)
      : _routeLoader = routeLoader;
  final Future<NavigationRoute?> Function(LatLng, LatLng)? _routeLoader;

  Future<NavigationRoute?> _loadRoute(LatLng origin, LatLng destination) =>
      _routeLoader?.call(origin, destination) ??
      GoogleMapsService.instance
          .calculateRoute(origin: origin, destination: destination);

  static final NavigationService instance = NavigationService._();

  // ── High-Accuracy Navigation Filters & State Machine ────────────────────────
  final GpsAccuracyFilter _gpsFilter = GpsAccuracyFilter();
  final ManeuverStateMachine _maneuverFsm = ManeuverStateMachine();
  LatLng? _lastTransmittedRouteWindowRiderPos;
  double? _lastTransmittedRouteWindowHeading;

  // ── Route & Coordinates ────────────────────────────────────────────────────
  Destination? _currentDestination;
  LatLng? _origin;
  LatLng? _destination;
  NavigationRoute? _activeRoute;
  int _currentStepIndex = 0;
  int _routeProgressIndex = 0;
  DateTime? _lastContextFetchAt;
  LatLng? _lastContextFetchPosition;
  bool _contextFetchInFlight = false;
  String _cityName = '';

  // ── State ──────────────────────────────────────────────────────────────────
  NavigationState _currentState = NavigationState.idle();
  bool _isNavigating = false;
  bool _isRerouting = false;
  bool _isStarting = false;
  Future<void>? _stopping;
  int _rideGeneration = 0;
  int _routeRevision = 0;
  int _rerouteFailures = 0;
  bool _paused = false;
  DateTime? _nextRerouteAllowedAt;
  static const _rerouteRetryCooldown = Duration(seconds: 10);
  final OffRouteDetector _offRouteDetector = OffRouteDetector();
  // Arrival confirmation counter — requires 2 samples < 30m to avoid
  // triggering on a momentary GPS jump near the destination.
  int _arrivalConfirmCount = 0;

  // ── Ride session tracking ──────────────────────────────────────────────────
  NavigationSession? _currentSession;
  String? _sessionUserId;
  double _sessionDistanceTravelled = 0.0;
  double _sessionMaxSpeedKmh = 0.0;
  double _sessionSpeedSum = 0.0;
  int _sessionSpeedSamples = 0;

  // ── GPS listener reference ─────────────────────────────────────────────────
  VoidCallback? _gpsTickListener;
  VoidCallback? _gpsAvailabilityListener;

  // ── Public Notifiers ───────────────────────────────────────────────────────
  final ValueNotifier<NavigationState> navigationStateNotifier =
      ValueNotifier<NavigationState>(NavigationState.idle());
  final ValueNotifier<NavigationRoute?> activeRouteNotifier =
      ValueNotifier<NavigationRoute?>(null);
  final ValueNotifier<bool> isNavigatingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<RideState> rideStateNotifier =
      ValueNotifier<RideState>(RideState.idle);

  NavigationState get currentState => _currentState;
  bool get isNavigating => _isNavigating;
  NavigationRoute? get activeRoute => _activeRoute;
  Destination? get currentDestination => _currentDestination;
  int get routeProgressIndex => _routeProgressIndex;
  int get routeRevision => _routeRevision;

  RouteWindowSegment _routeWindow(LatLng rider, double heading) {
    final window = RouteWindowTransformer.transform(
      riderPosition: rider,
      riderHeadingDeg: heading,
      polylinePoints: _activeRoute!.polylinePoints,
      destination: _destination!,
      minimumRouteIndex: _routeProgressIndex,
    );
    _routeProgressIndex = window.routeIndex;
    return window;
  }

  Future<void> _refreshNavContextIfNeeded(LatLng rider, double heading) async {
    if (DeviceMapConfig.enabled ||
        _routeLoader != null ||
        _contextFetchInFlight ||
        !_isNavigating ||
        _activeRoute == null) {
      return;
    }
    final now = DateTime.now();
    final moved = _lastContextFetchPosition == null
        ? double.infinity
        : _calculateDistanceMeters(_lastContextFetchPosition!, rider);
    if (_lastContextFetchAt != null &&
        moved < 1000 &&
        now.difference(_lastContextFetchAt!) < const Duration(minutes: 10)) {
      return;
    }
    _contextFetchInFlight = true;
    _lastContextFetchAt = now;
    _lastContextFetchPosition = rider;
    final route = _activeRoute!;
    try {
      final city = await GoogleMapsService.instance
          .reverseGeocodeCity(rider.latitude, rider.longitude);
      if (!_isNavigating || !identical(_activeRoute, route)) return;
      if (city != null && city.isNotEmpty) _cityName = city;

      final results = await Future.wait([
        GoogleMapsService.instance.searchPlaces('petrol station'),
        GoogleMapsService.instance.searchPlaces('motorcycle repair'),
      ]);
      Destination? best;
      var bestType = 0;
      var bestDistance = 0.0;
      var bestScore = double.infinity;
      final points = route.polylinePoints;
      for (var type = 1; type <= 2; type++) {
        for (final place in results[type - 1]) {
          final location = LatLng(place.latitude, place.longitude);
          final riderDistance = _calculateDistanceMeters(rider, location);
          if (riderDistance > 1500) continue;
          var routeDistance = double.infinity;
          var routeIndex = 0;
          for (var i = 0; i < points.length; i++) {
            final distance = _calculateDistanceMeters(location, points[i]);
            if (distance < routeDistance) {
              routeDistance = distance;
              routeIndex = i;
            }
          }
          if (routeDistance > 300 || routeIndex < _routeProgressIndex - 1) {
            continue;
          }
          final score = riderDistance + routeDistance + (type == 1 ? 0 : 100);
          if (score < bestScore) {
            best = place;
            bestType = type;
            bestDistance = riderDistance;
            bestScore = score;
          }
        }
      }
      if (!_isNavigating || !identical(_activeRoute, route)) return;
      final poiPoint = best != null && bestDistance <= 300
          ? RouteWindowTransformer.projectPoint(
              rider: rider,
              target: LatLng(best.latitude, best.longitude),
              headingDeg: heading,
            )
          : null;
      await BleNavigationService.instance.sendNavContext(NavContextPacket(
        city: _cityName,
        poiType: bestType,
        poiDistanceMeters: bestDistance.round(),
        poiName: best?.displayTitle ?? '',
        poiPoint: poiPoint,
      ));
    } catch (e) {
      debugPrint('[NavService] Optional city/POI lookup failed: $e');
    } finally {
      _contextFetchInFlight = false;
    }
  }

  void _setRideState(RideState state) {
    rideStateNotifier.value = state;
    _currentState = _currentState.copyWith(rideState: state);
    navigationStateNotifier.value = _currentState;
  }

  // ── START NAVIGATION ───────────────────────────────────────────────────────

  /// Starts turn-by-turn motorcycle navigation to the given destination.
  ///
  /// STEP 1–12 of the master prompt START RIDE workflow.
  /// The live phone fix always drives progress after the ride begins.  An
  /// optional [startLocation] lets the planner preview and initialise a route
  /// between two entered places (instead of silently assuming current GPS).
  /// If the rider starts somewhere else, the existing off-route logic safely
  /// recalculates from the real phone position.
  Future<bool> startNavigation(
    Destination destination, {
    Destination? startLocation,
    NavigationSession? resumedSession,
  }) async {
    if (_stopping != null) await _stopping;
    if (_isStarting) return false;
    if (_isNavigating) return true;
    _isStarting = true;
    final generation = ++_rideGeneration;
    try {
      _currentDestination = destination;
      _setRideState(RideState.starting);
      _gpsFilter.reset();

      // 1. Resolve destination coordinates if missing
      Destination? resolvedDest = destination;
      if (destination.latitude == 0.0 && destination.longitude == 0.0) {
        resolvedDest =
            await GoogleMapsService.instance.resolveDestination(destination);
        if (generation != _rideGeneration) return false;
        if (resolvedDest == null ||
            (resolvedDest.latitude == 0.0 && resolvedDest.longitude == 0.0)) {
          debugPrint(
              '[NavService] Failed to resolve coordinates for ${destination.displayTitle}');
          _setRideState(RideState.navigationError);
          return false;
        }
        _currentDestination = resolvedDest;
      }

      _destination = LatLng(resolvedDest.latitude, resolvedDest.longitude);

      // 2. Obtain fresh current GPS position as origin (STEP 3–4 of master prompt)
      final currentPos = await LocationService.instance.getCurrentPosition();
      if (generation != _rideGeneration) return false;
      if (currentPos == null || _gpsFilter.filter(currentPos) == null) {
        debugPrint('[NavService] Unable to obtain current GPS origin.');
        _setRideState(RideState.navigationError);
        return false;
      }

      // Resolve an explicitly entered start place.  We still acquire a fresh
      // phone position above because it is the only valid source for live speed,
      // heading and turn-by-turn progress.
      Destination? resolvedStart = startLocation;
      if (resolvedStart != null &&
          resolvedStart.latitude == 0.0 &&
          resolvedStart.longitude == 0.0) {
        resolvedStart =
            await GoogleMapsService.instance.resolveDestination(resolvedStart);
        if (generation != _rideGeneration) return false;
        if (resolvedStart == null ||
            (resolvedStart.latitude == 0.0 && resolvedStart.longitude == 0.0)) {
          debugPrint('[NavService] Failed to resolve entered start location.');
          _setRideState(RideState.navigationError);
          return false;
        }
      }

      _origin = resolvedStart == null
          ? LatLng(currentPos.latitude, currentPos.longitude)
          : LatLng(resolvedStart.latitude, resolvedStart.longitude);

      // 3. Calculate route via Google Routes API v2 / OSRM fallback (network call)
      final route = await _loadRoute(_origin!, _destination!);
      if (generation != _rideGeneration) return false;

      if (route == null || route.steps.isEmpty) {
        debugPrint(
            '[NavService] Could not calculate motorcycle route to destination.');
        _setRideState(RideState.navigationError);
        return false;
      }

      _activeRoute = route;
      _routeProgressIndex = 0;
      _lastContextFetchAt = null;
      _currentStepIndex = 0;
      _isNavigating = true;
      _isRerouting = false;
      _paused = false;
      _routeRevision++;
      _rerouteFailures = 0;
      _nextRerouteAllowedAt = null;
      _offRouteDetector.reset();
      _arrivalConfirmCount = 0;

      activeRouteNotifier.value = route;
      isNavigatingNotifier.value = true;

      // 4. Session tracking
      final sessionUserId = await RideHistoryService.instance.currentUserId();
      if (generation != _rideGeneration) return false;
      _sessionUserId = sessionUserId;
      _currentSession = resumedSession ??
          NavigationSession.start(
            origin: resolvedStart ?? _originAsDestination(currentPos),
            destination: resolvedDest,
          );
      _sessionDistanceTravelled = 0;
      _sessionMaxSpeedKmh = 0;
      _sessionSpeedSum = 0;
      _sessionSpeedSamples = 0;
      _previousPos = null;

      // 5. Build initial NavigationState
      //    Speed MUST be 0.0 via SpeedFilter — do NOT multiply pos.speed blindly.
      final initialSpeed =
          SpeedFilter.toKmh(currentPos.speed.clamp(0.0, 300.0));
      final firstStep = route.steps[0];
      final nextStep = route.steps.length > 1 ? route.steps[1] : null;
      final bleOk = JustRideBleService.instance.isDeviceConnected;

      // Upcoming turn to display while on the first step:
      final bool isInitialStepUTurn =
          firstStep.maneuver.toUpperCase().contains('U_TURN') ||
              firstStep.maneuver.toUpperCase().contains('UTURN');
      final String initialManeuver = firstStep.maneuver;
      final String initialTargetStreet = isInitialStepUTurn
          ? (firstStep.instruction.isNotEmpty
              ? firstStep.instruction
              : firstStep.streetName)
          : (firstStep.instruction.isNotEmpty
              ? firstStep.instruction
              : (firstStep.streetName.isNotEmpty
                  ? firstStep.streetName
                  : (nextStep?.instruction ??
                      nextStep?.streetName ??
                      resolvedDest.displayTitle)));
      final String initialNextManeuver = isInitialStepUTurn
          ? (nextStep?.maneuver ?? 'STRAIGHT')
          : (nextStep?.maneuver ?? 'ARRIVE');
      final String initialNextStreet = isInitialStepUTurn
          ? (nextStep?.streetName ?? '')
          : (nextStep != null
              ? (nextStep.instruction.isNotEmpty
                  ? nextStep.instruction
                  : (nextStep.streetName.isNotEmpty
                      ? nextStep.streetName
                      : resolvedDest.displayTitle))
              : resolvedDest.displayTitle);

      _currentState = NavigationState(
        currentLatitude: currentPos.latitude,
        currentLongitude: currentPos.longitude,
        speedKmh: initialSpeed, // 0.0 when parked ✓
        heading: currentPos.heading >= 0 ? currentPos.heading : 0.0,
        remainingDistanceMeters: route.totalDistanceMeters,
        remainingDurationSeconds: route.totalDurationSeconds,
        maneuver: initialManeuver,
        maneuverText: initialTargetStreet,
        maneuverDistanceMeters: firstStep.distanceMeters,
        nextManeuver: initialNextManeuver,
        nextManeuverText: initialNextStreet,
        nextManeuverDistanceMeters:
            (route.steps.length > 1) ? route.steps[1].distanceMeters : 0.0,
        maneuverId: 1,
        maneuverState: 'APPROACHING',
        rerouting: false,
        gpsAvailable: true,
        bleConnected: bleOk,
        rideState: RideState.navigating,
      );

      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = RideState.navigating;

      // 6. Start continuous GPS tracking before publishing a live route.  Do
      // not leave the UI/HUD on a static initial packet when Android declined
      // the foreground location stream.
      _gpsFilter.reset();
      _maneuverFsm.reset(
        initialStepIndex: 0,
        initialManeuver: initialManeuver,
      );
      _lastTransmittedRouteWindowRiderPos = _origin;
      _lastTransmittedRouteWindowHeading = _currentState.heading;

      // 7. Track GPS availability changes (GPS LOST / recovered)
      _gpsAvailabilityListener = _onGpsAvailabilityChanged;
      LocationService.instance.isGpsAvailableNotifier
          .removeListener(_onGpsAvailabilityChanged);
      LocationService.instance.isGpsAvailableNotifier
          .addListener(_onGpsAvailabilityChanged);

      final trackingStarted = await LocationService.instance
          .startTracking(distanceFilterMeters: 0, intervalMs: 400);
      if (generation != _rideGeneration) return false;
      if (!trackingStarted) {
        _currentSession = null;
        _sessionUserId = null;
        debugPrint('[NavService] Unable to start continuous GPS tracking.');
        _isNavigating = false;
        isNavigatingNotifier.value = false;
        _setRideState(RideState.navigationError);
        LocationService.instance.positionNotifier.removeListener(_onGpsTick);
        LocationService.instance.isGpsAvailableNotifier
            .removeListener(_onGpsAvailabilityChanged);
        _gpsTickListener = null;
        _gpsAvailabilityListener = null;
        return false;
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        if (generation != _rideGeneration) return false;
        if (_sessionUserId != null) {
          await prefs.setString('resume_session_owner', _sessionUserId!);
        } else {
          await prefs.remove('resume_session_owner');
        }
        if (generation != _rideGeneration) return false;
        await prefs.setString(
            'resume_active_session', _currentSession!.toJson());
        if (generation != _rideGeneration) return false;
      } catch (e) {
        debugPrint('[NavService] Failed to save active ride: $e');
      }

      // Deliver NAV_START and initial route window to the ESP32 first.
      // The ESP32 requires opcode 0x01 (NAV_OP_START) to switch screen to SCREEN_NAV.
      await BleNavigationService.instance.sendNavStart(_currentState);
      if (generation != _rideGeneration) return false;
      await Future.delayed(const Duration(milliseconds: 60));
      if (generation != _rideGeneration) return false;
      final initialWindow = _routeWindow(
        LatLng(_currentState.currentLatitude, _currentState.currentLongitude),
        _currentState.heading,
      );
      await BleNavigationService.instance.sendRouteSegment(initialWindow);
      if (generation != _rideGeneration) return false;

      // Now recalculate from live fix and start continuous listening
      _onGpsTick();
      _gpsTickListener = _onGpsTick;
      LocationService.instance.positionNotifier.addListener(_onGpsTick);

      debugPrint(
          '[NavService] ✓ Navigation started to ${destination.displayTitle} '
          '(${route.totalDistanceMeters.round()}m, ${route.steps.length} steps)');
      return true;
    } catch (e) {
      if (generation == _rideGeneration) {
        await stopNavigation();
        _setRideState(RideState.navigationError);
      }
      debugPrint('[NavService] Start failed: $e');
      return false;
    } finally {
      if (generation == _rideGeneration) _isStarting = false;
    }
  }

  // ── GPS LOST / RECOVERED ──────────────────────────────────────────────────

  void _onGpsAvailabilityChanged() {
    if (_paused) return;
    final isAvailable = LocationService.instance.isGpsAvailable;

    if (!isAvailable && _isNavigating) {
      // GPS lost during active navigation
      debugPrint('[NavService] ⚠ GPS signal lost during navigation');
      _currentState = NavigationState.gpsLost(_currentState);
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = RideState.gpsLost;
      BleNavigationService.instance.sendNavUpdate(_currentState, force: true);
    } else if (isAvailable && _currentState.rideState == RideState.gpsLost) {
      // GPS recovered
      debugPrint('[NavService] ✓ GPS signal recovered');
      _currentState = _currentState.copyWith(
        gpsAvailable: true,
        rideState: RideState.navigating,
      );
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = RideState.navigating;
      BleNavigationService.instance.sendNavUpdate(_currentState, force: true);
    }
  }

  // ── GPS TICK (Live Update Loop) ───────────────────────────────────────────

  /// Called on every GPS position update from LocationService.
  /// This is the main navigation progress loop — runs locally, no network calls.
  void _onGpsTick() {
    if (!_isNavigating || _paused || _activeRoute == null) {
      return;
    }

    final rawPos = LocationService.instance.currentPosition;
    if (rawPos == null) return;

    // Validate raw GPS fix (reject stale fixes, poor accuracy, or teleportation jumps)
    final pos = _gpsFilter.filter(rawPos);
    if (pos == null) {
      // Discard invalid / noisy GPS point per Master Prompt §10
      return;
    }

    // Speed is pre-filtered by LocationService → SpeedFilter (never shows jitter)
    final currentSpeed = LocationService.instance.speedKmhNotifier.value;
    final currentHeading = LocationService.instance.headingNotifier.value;
    final bleConnected = JustRideBleService.instance.isDeviceConnected;
    final riderLatLng = LatLng(pos.latitude, pos.longitude);

    final previousPos = _previousPos;
    // Session telemetry accumulation: only when actively riding (not parked GPS drift)
    if (_previousPos != null && currentSpeed >= 1.5) {
      final seg = _calculateDistanceMeters(
        LatLng(_previousPos!.latitude, _previousPos!.longitude),
        riderLatLng,
      );
      _sessionDistanceTravelled += seg;
    }
    _previousPos = pos;
    if (currentSpeed > _sessionMaxSpeedKmh) _sessionMaxSpeedKmh = currentSpeed;
    if (currentSpeed > 0) {
      _sessionSpeedSum += currentSpeed;
      _sessionSpeedSamples++;
    }

    // 1. Arrival detection: require 2 consecutive samples within 30m to
    //    avoid false arrival from GPS noise near the destination.
    final distanceToFinalDest =
        _calculateDistanceMeters(riderLatLng, _destination!);
    if (distanceToFinalDest <= 30.0 &&
        pos.accuracy <= 25 &&
        _currentStepIndex >= _activeRoute!.steps.length - 2) {
      _arrivalConfirmCount++;
      if (_arrivalConfirmCount >= 2) {
        _onArrived(pos, bleConnected);
        return;
      }
    } else {
      _arrivalConfirmCount = 0;
    }

    // 2. Evaluate active step progress via Maneuver State Machine
    final steps = _activeRoute!.steps;

    // Progress is monotonic within a route. Backtracking is handled by the
    // confirmed corridor detector, not nearest historical vertices.
    _maneuverFsm.update(
      riderPosition: riderLatLng,
      riderHeading: currentHeading,
      steps: steps,
      riderSpeedKmh: currentSpeed,
    );

    _currentStepIndex = _maneuverFsm.activeStepIndex.clamp(0, steps.length - 1);
    final step = steps[_currentStepIndex];
    final distToTurn = _remainingStepDistance(riderLatLng, step);

    // 3. Lookahead: next step after current
    final nextStepIdx = _currentStepIndex + 1;
    final nextStep = (nextStepIdx < steps.length) ? steps[nextStepIdx] : null;
    final afterNextIdx = _currentStepIndex + 2;
    final afterNextStep =
        (afterNextIdx < steps.length) ? steps[afterNextIdx] : null;

    // Target street name and next lookahead maneuvers:
    final String targetStreet = step.instruction.isNotEmpty
        ? step.instruction
        : (step.streetName.isNotEmpty
            ? step.streetName
            : (nextStep != null && nextStep.instruction.isNotEmpty
                ? nextStep.instruction
                : (nextStep?.streetName ??
                    (_currentDestination?.displayTitle ?? 'Destination'))));

    final String lookaheadNextManeuver =
        (step.maneuver.toUpperCase().contains('U_TURN') ||
                step.maneuver.toUpperCase().contains('UTURN'))
            ? (nextStep?.maneuver ?? 'STRAIGHT')
            : (nextStep?.maneuver ?? (afterNextStep?.maneuver ?? 'ARRIVE'));

    final String lookaheadNextStreet = nextStep != null
        ? (nextStep.instruction.isNotEmpty
            ? nextStep.instruction
            : (nextStep.streetName.isNotEmpty
                ? nextStep.streetName
                : (_currentDestination?.displayTitle ?? '')))
        : (afterNextStep?.instruction ??
            (_currentDestination?.displayTitle ?? ''));

    // 4. Remaining route distance
    double remainingDist = distToTurn;
    for (int i = _currentStepIndex + 1; i < steps.length; i++) {
      remainingDist += steps[i].distanceMeters;
    }

    // Retain provider travel-time estimates, scaled by progress on this step.
    var remainingSecs = step.distanceMeters > 0
        ? (step.durationSeconds *
                (distToTurn / step.distanceMeters).clamp(0.0, 1.0))
            .round()
        : 0;
    for (var i = _currentStepIndex + 1; i < steps.length; i++) {
      remainingSecs += steps[i].durationSeconds;
    }

    // 6. Off-route detection using 3-state OffRouteDetector.
    //    Suppresses rerouting while stationary; requires confirmed deviation.
    final offRouteState = _offRouteDetector.update(
      riderPosition: riderLatLng,
      timestamp: pos.timestamp,
      accuracyMeters: pos.accuracy,
      speedMs: currentSpeed / 3.6, // km/h → m/s
      polylinePoints: _activeRoute!.polylinePoints,
    );
    if (offRouteState == OffRouteState.offRoute && !_isRerouting) {
      _offRouteDetector.reset();
      _triggerReroute(riderLatLng);
      return;
    }

    // 7. Heading: when stationary or low-speed, orient toward the next step
    //    endpoint (so the map arrow points the right direction while parked).
    //    Use route bearing whenever speed < 3 km/h regardless of raw heading value,
    //    since GPS heading is unreliable below walking speed.
    double activeHeading = currentHeading;
    if (currentSpeed < 3.0) {
      // Always use route-derived bearing when nearly stationary
      final headingTarget = nextStepIdx < steps.length
          ? steps[_currentStepIndex].endLocation
          : step.endLocation;
      final bearingToNext = Geolocator.bearingBetween(
        riderLatLng.latitude,
        riderLatLng.longitude,
        headingTarget.latitude,
        headingTarget.longitude,
      );
      if (!bearingToNext.isNaN && bearingToNext != 0.0) {
        activeHeading = (bearingToNext + 360.0) % 360.0;
      }
    } else if ((activeHeading <= 0.0 || currentHeading.isNaN)) {
      // Fallback for valid speed but bad heading reading
      final headingTarget = nextStepIdx < steps.length
          ? steps[_currentStepIndex].endLocation
          : step.endLocation;
      final bearingToNext = Geolocator.bearingBetween(
        riderLatLng.latitude,
        riderLatLng.longitude,
        headingTarget.latitude,
        headingTarget.longitude,
      );
      if (!bearingToNext.isNaN && bearingToNext != 0.0) {
        activeHeading = (bearingToNext + 360.0) % 360.0;
      }
    }

    // Section 29: Synchronize canonical maneuver state with simulator if active,
    // or rely on local ManeuverStateMachine on real phone GPS.
    final simPacket =
        LocationService.instance.locationSource == LocationSource.simulator
            ? SimulatorLocationService.instance.latestPacketNotifier.value
            : null;

    final String effectiveManeuver =
        simPacket != null && simPacket.maneuver.isNotEmpty
            ? simPacket.maneuver
            : _maneuverFsm.displayManeuver;
    final int effectiveManeuverId =
        simPacket != null && simPacket.maneuverId > 0
            ? simPacket.maneuverId
            : (_currentStepIndex + 1);
    final String effectiveManeuverState =
        simPacket != null && simPacket.maneuverState != 'NONE'
            ? simPacket.maneuverState
            : _maneuverFsm.maneuverStateString;
    double effectiveManeuverDist =
        simPacket != null && simPacket.maneuverDistance > 0
            ? simPacket.maneuverDistance
            : (_maneuverFsm.stage == ManeuverStage.turning && distToTurn <= 10
                ? 0.0
                : distToTurn);

    // 8. Determine ride state: STATIONARY when speed < 3.0 km/h
    final RideState activeRideState;
    if (_isRerouting) {
      activeRideState = RideState.rerouting;
    } else if (currentSpeed < 3.0) {
      activeRideState = RideState.stationary;
    } else {
      activeRideState = RideState.navigating;
    }

    // Stationary GPS jitter filter:
    // When parked or stopped at a signal, GPS coordinates drift by ±2-5m.
    // Freeze distance to prevent the HUD/app numbers from jumping around.
    if (activeRideState == RideState.stationary &&
        _currentState.maneuverDistanceMeters > 0 &&
        simPacket == null) {
      final prevLat = previousPos?.latitude ?? pos.latitude;
      final prevLng = previousPos?.longitude ?? pos.longitude;
      final driftMeters = Geolocator.distanceBetween(
        prevLat,
        prevLng,
        pos.latitude,
        pos.longitude,
      );
      if (driftMeters < 5.0) {
        effectiveManeuverDist = _currentState.maneuverDistanceMeters;
        remainingDist = _currentState.remainingDistanceMeters;
      }
    }

    // 9. Update NavigationState — single source of truth
    _currentState = NavigationState(
      currentLatitude: pos.latitude,
      currentLongitude: pos.longitude,
      speedKmh: currentSpeed, // 0.0 when stationary ✓
      heading: activeHeading,
      remainingDistanceMeters: remainingDist,
      remainingDurationSeconds: remainingSecs,
      maneuver: effectiveManeuver,
      maneuverText: targetStreet,
      maneuverDistanceMeters: effectiveManeuverDist,
      nextManeuver: lookaheadNextManeuver,
      nextManeuverText: lookaheadNextStreet,
      nextManeuverDistanceMeters: nextStep?.distanceMeters ?? 0.0,
      maneuverId: effectiveManeuverId,
      maneuverState: effectiveManeuverState,
      rerouting: _isRerouting,
      gpsAvailable: true,
      bleConnected: bleConnected,
      rideState: activeRideState,
    );

    navigationStateNotifier.value = _currentState;
    rideStateNotifier.value = activeRideState;

    // 9. Throttled BLE telemetry update
    BleNavigationService.instance.sendNavUpdate(_currentState);
    unawaited(_refreshNavContextIfNeeded(riderLatLng, activeHeading));

    // 10. Update the map window as the rider moves or rotates at an intersection.
    // Eight metres makes the pointer visibly follow low-speed city travel without flooding BLE.
    // 15 degrees heading change rotates the displayed road geometry to match rider perspective.
    final double headingDelta = _lastTransmittedRouteWindowHeading == null
        ? 360.0
        : (activeHeading - _lastTransmittedRouteWindowHeading!).abs();
    final double distDelta = _lastTransmittedRouteWindowRiderPos == null
        ? 100.0
        : Geolocator.distanceBetween(
            _lastTransmittedRouteWindowRiderPos!.latitude,
            _lastTransmittedRouteWindowRiderPos!.longitude,
            riderLatLng.latitude,
            riderLatLng.longitude,
          );

    if (distDelta >= 8.0 || (headingDelta >= 15.0 && headingDelta <= 345.0)) {
      _lastTransmittedRouteWindowRiderPos = riderLatLng;
      _lastTransmittedRouteWindowHeading = activeHeading;
      final window = _routeWindow(riderLatLng, activeHeading);
      BleNavigationService.instance.sendRouteSegment(window);
    }
  }

  static double _remainingStepDistance(LatLng rider, RouteStep step) {
    final points = step.points;
    if (points.length < 2) {
      return Geolocator.distanceBetween(rider.latitude, rider.longitude,
          step.endLocation.latitude, step.endLocation.longitude);
    }
    var index = 0;
    var closest = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final ab = Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude);
      final ar = Geolocator.distanceBetween(
          a.latitude, a.longitude, rider.latitude, rider.longitude);
      final br = Geolocator.distanceBetween(
          b.latitude, b.longitude, rider.latitude, rider.longitude);
      final along = ab > 0
          ? ((ar * ar + ab * ab - br * br) / (2 * ab)).clamp(0.0, ab)
          : 0.0;
      final projection =
          ab > 0 ? (ar * ar + ab * ab - br * br) / (2 * ab) : 0.0;
      final squared = (ar * ar + along * along - 2 * along * projection)
          .clamp(0.0, double.infinity);
      if (squared < closest) {
        closest = squared;
        index = i;
      }
    }
    // Segment projection in local metre coordinates.
    final a = points[index];
    final b = points[index + 1];
    final ab = Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
    final ar = Geolocator.distanceBetween(
        a.latitude, a.longitude, rider.latitude, rider.longitude);
    final br = Geolocator.distanceBetween(
        b.latitude, b.longitude, rider.latitude, rider.longitude);
    final along = ab > 0
        ? ((ar * ar + ab * ab - br * br) / (2 * ab)).clamp(0.0, ab)
        : 0.0;
    var remaining = ab - along;
    for (var i = index + 2; i < points.length; i++) {
      remaining += Geolocator.distanceBetween(points[i - 1].latitude,
          points[i - 1].longitude, points[i].latitude, points[i].longitude);
    }
    return remaining;
  }

  // ── Previous position for session distance tracking ───────────────────────
  Position? _previousPos;

  // ── REROUTE ──────────────────────────────────────────────────────────────

  Future<void> _triggerReroute(LatLng riderLocation) async {
    if (!_isNavigating || _paused || _destination == null || _isRerouting) {
      return;
    }
    final generation = _rideGeneration;
    final now = DateTime.now();
    if (_nextRerouteAllowedAt != null && now.isBefore(_nextRerouteAllowedAt!)) {
      return;
    }

    final previousInstruction = _currentState.maneuverText;
    _isRerouting = true;
    _nextRerouteAllowedAt = now.add(_rerouteRetryCooldown);
    debugPrint('[NavService] Off-route! Triggering automatic reroute...');

    _currentState = _currentState.copyWith(
      rerouting: true,
      rideState: RideState.rerouting,
      maneuverText: 'Recalculating route...',
    );
    navigationStateNotifier.value = _currentState;
    rideStateNotifier.value = RideState.rerouting;
    BleNavigationService.instance.sendNavReroute(_currentState);

    try {
      final newRoute = await _loadRoute(riderLocation, _destination!);

      if (generation != _rideGeneration || !_isNavigating || _paused) return;
      if (newRoute != null && newRoute.steps.isNotEmpty) {
        _routeRevision++;
        BleNavigationService.instance.beginRouteRevision();
        _rerouteFailures = 0;
        _activeRoute = newRoute;
        _routeProgressIndex = 0;
        _lastContextFetchAt = null;
        _currentStepIndex = 0;
        final firstStep = newRoute.steps[0];
        final nextStep = newRoute.steps.length > 1 ? newRoute.steps[1] : null;

        final bool isInitialStepUTurn =
            firstStep.maneuver.toUpperCase().contains('U_TURN') ||
                firstStep.maneuver.toUpperCase().contains('UTURN');
        final String rerouteManeuver = firstStep.maneuver;
        final String rerouteTargetStreet = isInitialStepUTurn
            ? (firstStep.instruction.isNotEmpty
                ? firstStep.instruction
                : firstStep.streetName)
            : (firstStep.instruction.isNotEmpty
                ? firstStep.instruction
                : (firstStep.streetName.isNotEmpty
                    ? firstStep.streetName
                    : (nextStep?.instruction ??
                        nextStep?.streetName ??
                        (_currentDestination?.displayTitle ?? 'Destination'))));
        final String rerouteNextManeuver = isInitialStepUTurn
            ? (nextStep?.maneuver ?? 'STRAIGHT')
            : (nextStep?.maneuver ?? 'ARRIVE');
        final String rerouteNextStreet = isInitialStepUTurn
            ? (nextStep?.streetName ?? '')
            : (nextStep != null
                ? (nextStep.instruction.isNotEmpty
                    ? nextStep.instruction
                    : (nextStep.streetName.isNotEmpty
                        ? nextStep.streetName
                        : (_currentDestination?.displayTitle ?? '')))
                : (_currentDestination?.displayTitle ?? ''));

        _offRouteDetector.reset();
        // Reset the ManeuverStateMachine so its step index starts fresh
        // on the newly calculated route (fixes step index drift after reroute).
        _maneuverFsm.reset(
          initialStepIndex: 0,
          initialManeuver: rerouteManeuver,
        );
        activeRouteNotifier.value = newRoute;
        debugPrint('[NavService] ✓ Rerouted successfully!');

        // Publish the new navigation state before its route window. The BLE
        // write queue preserves this order, so the HUD never renders a new
        // maneuver alongside an older route segment.
        _currentState = _currentState.copyWith(
          rerouting: false,
          rideState: RideState.navigating,
          maneuver: rerouteManeuver,
          maneuverText: rerouteTargetStreet,
          maneuverDistanceMeters: firstStep.distanceMeters,
          remainingDistanceMeters: newRoute.totalDistanceMeters,
          remainingDurationSeconds: newRoute.totalDurationSeconds,
          nextManeuver: rerouteNextManeuver,
          nextManeuverText: rerouteNextStreet,
          nextManeuverDistanceMeters: nextStep?.distanceMeters ?? 0.0,
          maneuverId: 1,
          maneuverState: 'APPROACHING',
        );
        navigationStateNotifier.value = _currentState;
        rideStateNotifier.value = RideState.navigating;
        await BleNavigationService.instance.sendNavUpdate(
          _currentState,
          force: true,
        );

        if (generation != _rideGeneration || !_isNavigating) return;
        // Immediately transmit the matching route window.
        final latestRider = LatLng(
            _currentState.currentLatitude, _currentState.currentLongitude);
        final newWindow = _routeWindow(latestRider, _currentState.heading);
        _lastTransmittedRouteWindowRiderPos = latestRider;
        _lastTransmittedRouteWindowHeading = _currentState.heading;
        await BleNavigationService.instance.sendRouteSegment(newWindow);
      } else {
        debugPrint('[NavService] Reroute returned no usable route.');
        _rerouteFailures++;
        _currentState = _currentState.copyWith(
            rerouting: false,
            rideState: _currentState.gpsAvailable
                ? RideState.navigating
                : RideState.gpsLost,
            maneuverText: _currentState.maneuverText == 'Recalculating route...'
                ? previousInstruction
                : _currentState.maneuverText);
        navigationStateNotifier.value = _currentState;
        rideStateNotifier.value = _currentState.rideState;
        await BleNavigationService.instance.sendNavUpdate(
          _currentState,
          force: true,
        );
      }
    } catch (e) {
      if (generation != _rideGeneration || !_isNavigating || _paused) return;
      debugPrint('[NavService] Reroute failed: $e');
      // Leave the user in the last valid navigation state. The cooldown
      // prevents an immediate retry loop while the network/GPS recovers.
      _rerouteFailures++;
      _currentState = _currentState.copyWith(
          rerouting: false,
          rideState: _currentState.gpsAvailable
              ? RideState.navigating
              : RideState.gpsLost,
          maneuverText: _currentState.maneuverText == 'Recalculating route...'
              ? previousInstruction
              : _currentState.maneuverText);
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = _currentState.rideState;
      await BleNavigationService.instance.sendNavUpdate(
        _currentState,
        force: true,
      );
    } finally {
      if (generation == _rideGeneration) {
        _isRerouting = false;
        final seconds = 10 * (1 << _rerouteFailures.clamp(0, 3));
        _nextRerouteAllowedAt = DateTime.now().add(Duration(seconds: seconds));
      }
    }
  }

  // ── ARRIVED ──────────────────────────────────────────────────────────────

  void _onArrived(Position pos, bool bleConnected) {
    ++_rideGeneration;
    _isNavigating = false;
    _isRerouting = false;
    _isStarting = false;
    LocationService.instance.positionNotifier.removeListener(_onGpsTick);
    LocationService.instance.isGpsAvailableNotifier
        .removeListener(_onGpsAvailabilityChanged);
    _gpsTickListener = null;
    _gpsAvailabilityListener = null;
    _stopping = Future.wait(
            [LocationService.instance.stopTracking(), _clearSavedSession()])
        .then<void>((_) {})
        .whenComplete(() => _stopping = null);

    _currentState = NavigationState(
      currentLatitude: pos.latitude,
      currentLongitude: pos.longitude,
      speedKmh: 0,
      heading: pos.heading >= 0 ? pos.heading : 0.0,
      remainingDistanceMeters: 0,
      remainingDurationSeconds: 0,
      maneuver: 'ARRIVE',
      maneuverText: 'Destination Reached',
      maneuverDistanceMeters: 0,
      nextManeuver: 'ARRIVE',
      nextManeuverText: '',
      nextManeuverDistanceMeters: 0.0,
      rerouting: false,
      gpsAvailable: true,
      bleConnected: bleConnected,
      rideState: RideState.arrived,
    );

    navigationStateNotifier.value = _currentState;
    isNavigatingNotifier.value = false;
    rideStateNotifier.value = RideState.arrived;

    // Complete session
    _completeSession();

    BleNavigationService.instance.sendNavArrived(_currentState);
    debugPrint('[NavService] ★ Destination reached!');
  }

  // ── PAUSE / RESUME ────────────────────────────────────────────────────────

  void pauseNavigation() {
    if (!_isNavigating) return;
    ++_rideGeneration; // Invalidate any in-flight reroute.
    _paused = true;
    _isRerouting = false;
    _offRouteDetector.reset();
    _currentState =
        _currentState.copyWith(rideState: RideState.paused, rerouting: false);
    navigationStateNotifier.value = _currentState;
    rideStateNotifier.value = RideState.paused;
    BleNavigationService.instance.sendNavUpdate(
      _currentState,
      opCode: BleNavOpCode.navPause,
      force: true,
    );
  }

  void resumeNavigation() {
    if (!_isNavigating) return;
    _paused = false;
    _previousPos = null;
    _offRouteDetector.reset();
    _currentState = _currentState.copyWith(rideState: RideState.navigating);
    navigationStateNotifier.value = _currentState;
    rideStateNotifier.value = RideState.navigating;
    BleNavigationService.instance.sendNavUpdate(
      _currentState,
      opCode: BleNavOpCode.navResume,
      force: true,
    );
  }

  // ── STOP ─────────────────────────────────────────────────────────────────

  Future<void> stopNavigation() {
    return _stopping ??= _stopNavigation().whenComplete(() => _stopping = null);
  }

  Future<void> _stopNavigation() async {
    ++_rideGeneration;
    _isStarting = false;
    _paused = false;
    _isNavigating = false;
    _routeProgressIndex = 0;
    _lastContextFetchAt = null;
    _cityName = '';
    _isRerouting = false;
    _nextRerouteAllowedAt = null;
    _offRouteDetector.reset();
    _arrivalConfirmCount = 0;

    // Remove all listeners
    if (_gpsTickListener != null) {
      LocationService.instance.positionNotifier
          .removeListener(_gpsTickListener!);
      _gpsTickListener = null;
    }
    if (_gpsAvailabilityListener != null) {
      LocationService.instance.isGpsAvailableNotifier
          .removeListener(_gpsAvailabilityListener!);
      _gpsAvailabilityListener = null;
    }

    _completeSession(status: 'stopped');
    await _clearSavedSession();

    _currentState = NavigationState.idle(
      bleConnected: JustRideBleService.instance.isDeviceConnected,
    );
    navigationStateNotifier.value = _currentState;
    isNavigatingNotifier.value = false;
    rideStateNotifier.value = RideState.idle;
    activeRouteNotifier.value = null;

    await LocationService.instance.stopTracking();
    await BleNavigationService.instance.sendNavStop(_currentState);

    debugPrint('[NavService] Navigation stopped.');
  }

  // ── Session Tracking Helpers ──────────────────────────────────────────────

  Future<void> _clearSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('resume_active_session');
      await prefs.remove('resume_destination');
      await prefs.remove('resume_session_owner');
    } catch (e) {
      debugPrint('[NavService] Failed to clear finished ride: $e');
    }
  }

  void _completeSession({String status = 'completed'}) {
    if (_currentSession != null) {
      final avgSpeed = _sessionSpeedSamples > 0
          ? _sessionSpeedSum / _sessionSpeedSamples
          : 0.0;
      final completed = _currentSession!.complete(
        status: status,
        distanceMeters: _sessionDistanceTravelled,
        averageSpeedKmh: avgSpeed,
        maxSpeedKmh: _sessionMaxSpeedKmh,
      );
      final owner = _sessionUserId;
      if (owner != null) {
        unawaited(RideHistoryService.instance.save(completed, owner));
      }
      _currentSession = null;
      _sessionUserId = null;
      _previousPos = null;
    }
  }

  Destination? _originAsDestination(Position pos) {
    return Destination(
      name: 'Start',
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
  }

  // ── Geometry Helpers ──────────────────────────────────────────────────────

  static double _calculateDistanceMeters(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(
      p1.latitude,
      p1.longitude,
      p2.latitude,
      p2.longitude,
    );
  }

  /// Attempts to resume the route after an interruption using the last saved destination.
  Future<bool> recalculateAndResumeRoute() async {
    if (_isNavigating) {
      await BleNavigationService.instance.syncState(_currentState);
      final route = _activeRoute;
      if (route != null && _destination != null) {
        final window = _routeWindow(
          LatLng(_currentState.currentLatitude, _currentState.currentLongitude),
          _currentState.heading,
        );
        await BleNavigationService.instance.sendRouteSegment(window);
      }
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = await RideHistoryService.instance.currentUserId();
      if (owner == null || prefs.getString('resume_session_owner') != owner) {
        return false;
      }
      final savedSession = prefs.getString('resume_active_session');
      if (savedSession != null) {
        final session = NavigationSession.fromJson(savedSession);
        if (session.endTime == null && session.destination != null) {
          return await startNavigation(session.destination!,
              resumedSession: session);
        }
        await prefs.remove('resume_active_session');
      }
    } catch (e) {
      debugPrint('[NavService] Failed to resume route: $e');
    }
    return false;
  }
}
