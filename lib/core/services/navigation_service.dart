import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/destination.dart';
import '../models/navigation_state.dart';
import '../models/navigation_session.dart';
import '../models/ride_state.dart';
import '../models/device_map_frame.dart';
import '../models/ble_navigation_packet.dart';
import '../utils/gps_accuracy_filter.dart';
import '../utils/maneuver_state_machine.dart';
import '../utils/route_window_transformer.dart';
import '../utils/off_route_detector.dart';
import 'google_maps_service.dart';
import 'location_service.dart';
import 'ble_navigation_service.dart';
import 'bluetooth_service.dart';
import 'ride_history_service.dart';
import 'backend_service.dart';
import '../network/api_client.dart';

/// Central owner of the JustRide navigation session.
///
/// Architecture:
///   LocationService  â†’  NavigationService  â†’  NavigationState  â†’  UI / BLE
///
/// Rules enforced here:
///   â€¢ Speed is ALWAYS sourced from LocationService (SpeedFilter applied there)
///   â€¢ Speed is 0.0 when stationary or GPS unavailable
///   â€¢ Google APIs are called only for route calculation and rerouting
///   â€¢ NavigationState is the one source of truth â€” no other component owns state
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

  // â”€â”€ High-Accuracy Navigation Filters & State Machine â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final GpsAccuracyFilter _gpsFilter = GpsAccuracyFilter();
  final ManeuverStateMachine _maneuverFsm = ManeuverStateMachine();
  LatLng? _lastTransmittedRouteWindowRiderPos;
  double? _lastTransmittedRouteWindowHeading;

  // â”€â”€ Route & Coordinates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Destination? _currentDestination;
  final List<Destination> _stops = [];
  final stopsChanged = ValueNotifier<int>(0);
  List<Destination> get remainingStops => List.unmodifiable(_stops);
  bool _changingStop = false;

  Future<void> addStop(Destination stop) async {
    if (!_isNavigating || _stops.length >= 20) return;
    if (!stop.latitude.isFinite ||
        !stop.longitude.isFinite ||
        stop.latitude.abs() > 90 ||
        stop.longitude.abs() > 180 ||
        (stop.latitude == 0 && stop.longitude == 0)) {
      throw ArgumentError('Select a resolved destination');
    }
    _stops.add(stop);
    await _saveStops();
  }

  Future<void> removeStop(int index) async {
    if (index <= 0 || index >= _stops.length) return;
    _stops.removeAt(index);
    await _saveStops();
  }

  Future<void> moveStop(int from, int to) async {
    // The active leg stays pinned. Skipping explicitly changes that leg.
    if (from <= 0 || to <= 0 || from >= _stops.length || to >= _stops.length)
      return;
    _stops.insert(to, _stops.removeAt(from));
    await _saveStops();
  }

  Future<void> _saveStops() async {
    stopsChanged.value++;
    final prefs = await SharedPreferences.getInstance();
    if (_isNavigating)
      await prefs.setStringList(
          'resume_stops', _stops.map((s) => s.toJson()).toList());
  }

  Future<void> skipStop() async {
    if (!_isNavigating || _stops.length < 2 || _changingStop || _paused) return;
    final generation =
        ++_rideGeneration; // Discard a late response for the previous destination.
    _stops.removeAt(0);
    _currentDestination = _stops.first;
    _destination = LatLng(_stops.first.latitude, _stops.first.longitude);
    _changingStop = true;
    _isRerouting = false;
    _reroutePending = true;
    _arrivalConfirmCount = 0;
    _arrivalCandidateSince = null;
    _nextRerouteAllowedAt = null;
    _offRouteDetector.reset();
    // Set the new target before awaiting persistence or the network.
    _currentState = _currentState.copyWith(
        rerouting: true,
        rideState: RideState.rerouting,
        maneuverText: 'Next stop - calculating');
    navigationStateNotifier.value = _currentState;
    await _saveStops();
    if (generation != _rideGeneration || !_isNavigating || !_changingStop)
      return;
    await _triggerReroute(
        LatLng(_currentState.currentLatitude, _currentState.currentLongitude));
  }

  LatLng? _origin;
  LatLng? _destination;
  NavigationRoute? _activeRoute;
  int _currentStepIndex = 0;
  int _routeProgressIndex = 0;
  DateTime? _lastContextFetchAt;
  LatLng? _lastContextFetchPosition;
  bool _contextFetchInFlight = false;
  String _cityName = '';
  final Map<int, Destination> _hudPois = {};
  Map<int, Destination> get hudPois => Map.unmodifiable(_hudPois);
  DateTime? _lastPoiPublish;
  Future<void> _publishHudPois(LatLng rider, double heading) async {
    for (var type = 1; type <= 2; type++) {
      final place = _hudPois[type];
      final distance = place == null
          ? 0.0
          : _calculateDistanceMeters(
              rider, LatLng(place.latitude, place.longitude));
      await BleNavigationService.instance.sendNavContext(NavContextPacket(
          city: _cityName,
          poiType: type,
          poiDistanceMeters: distance.round(),
          poiName: place?.displayTitle ?? '',
          poiPoint: place == null
              ? null
              : RouteWindowTransformer.projectPoint(
                  rider: rider,
                  target: LatLng(place.latitude, place.longitude),
                  headingDeg: heading)));
    }
  }

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  NavigationState _currentState = NavigationState.idle();
  bool _isNavigating = false;
  bool _isRerouting = false;
  bool _reroutePending =
      false; // Confirmed deviation persists across request failures/backoff.
  bool _isStarting = false;
  Future<void>? _stopping;
  int _rideGeneration = 0;
  int _routeRevision = 0;
  int _rerouteFailures = 0;
  bool _paused = false;
  bool _resuming = false;
  Future<void> _gpsTransition = Future<void>.value();
  Timer? _deviceAccessTimer;
  bool _checkingDeviceAccess = false;

  void _startDeviceAccessChecks() {
    _deviceAccessTimer?.cancel();
    _deviceAccessTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (!_isNavigating) { timer.cancel(); return; }
      if (_checkingDeviceAccess || !ApiClient.instance.isAuthenticated) return;
      _checkingDeviceAccess = true;
      try { await BackendService.instance.getMyDevice(); }
      finally { _checkingDeviceAccess = false; }
    });
  }
  DateTime? _nextRerouteAllowedAt;
  static const _rerouteRetryCooldown = Duration(seconds: 10);
  final OffRouteDetector _offRouteDetector = OffRouteDetector();
  // Arrival confirmation counter â€” requires 2 samples < 30m to avoid
  // triggering on a momentary GPS jump near the destination.
  DateTime? _arrivalCandidateSince;
  int _arrivalConfirmCount = 0;

  // â”€â”€ Ride session tracking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  NavigationSession? _currentSession;
  String? _sessionUserId;
  double _sessionDistanceTravelled = 0.0;
  double _sessionMaxSpeedKmh = 0.0;
  final Stopwatch _rideClock = Stopwatch();
  int _savedActiveSeconds = 0;
  DateTime? _lastRecordedAt, _lastCheckpointAt;
  bool _trailBreak = true;
  final List<Map<String, dynamic>> _trailBuffer = [];
  NavigationSession? lastCompletedSession;

  double get distanceTravelledMeters => _isNavigating
      ? _sessionDistanceTravelled
      : lastCompletedSession?.distanceMeters ?? 0;
  int get activeRideSeconds =>
      _savedActiveSeconds + _rideClock.elapsed.inSeconds;

  NavigationSession _checkpointSession() => NavigationSession(
      sessionId: _currentSession!.sessionId,
      startTime: _currentSession!.startTime,
      origin: _currentSession!.origin,
      destination: _currentDestination,
      durationSeconds: activeRideSeconds,
      distanceMeters: _sessionDistanceTravelled,
      averageSpeedKmh: activeRideSeconds > 0
          ? _sessionDistanceTravelled * 3.6 / activeRideSeconds
          : 0,
      maxSpeedKmh: _sessionMaxSpeedKmh,
      status: _paused ? 'paused' : 'recording');

  void _flushTrail() {
    if (_currentSession == null || _trailBuffer.isEmpty) return;
    final points = List<Map<String, dynamic>>.of(_trailBuffer);
    _trailBuffer.clear();
    unawaited(RideHistoryService.instance.appendTrail(
        _sessionUserId ?? 'guest', _currentSession!.sessionId, points));
  }

  Future<void> _checkpointRide() async {
    if (_currentSession == null) return;
    _flushTrail();
    final session = _checkpointSession();
    final generation = _rideGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _rideGeneration || _currentSession == null) return;
    await prefs.setString('resume_active_session', session.toJson());
  }

  void _recordFix(Position pos) {
    final now = pos.timestamp;
    if (_lastRecordedAt == null ||
        now.difference(_lastRecordedAt!).inSeconds >= 5) {
      _trailBuffer.add({
        'lat': pos.latitude,
        'lon': pos.longitude,
        'at': now.toUtc().toIso8601String(),
        'segment': _trailBreak
      });
      _lastRecordedAt = now;
      _trailBreak = false;
    }
    if (_lastCheckpointAt == null ||
        now.difference(_lastCheckpointAt!).inSeconds >= 30) {
      _lastCheckpointAt = now;
      unawaited(_checkpointRide());
    }
  }

  // â”€â”€ GPS listener reference â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  VoidCallback? _gpsTickListener;
  VoidCallback? _gpsAvailabilityListener;

  // â”€â”€ Public Notifiers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
  int _deviceViewLevel = 2, _deviceCameraGeneration = 0;
  int get deviceViewLevel => _deviceViewLevel;
  int get deviceCameraGeneration => _deviceCameraGeneration;
  int _deviceViewportRevision = -1;
  ({LatLng center, int zoom})? _deviceOverview;
  ({LatLng center, int zoom})? get deviceOverviewViewport {
    if (deviceViewLevel != 5 || _activeRoute == null) return null;
    if (_deviceOverview == null || _deviceViewportRevision != _routeRevision) {
      _deviceViewportRevision = _routeRevision;
      _deviceOverview = fitDeviceMapViewport([
        LatLng(_currentState.currentLatitude, _currentState.currentLongitude),
        ..._activeRoute!.polylinePoints.skip(_routeProgressIndex)
      ]);
    }
    return _deviceOverview;
  }

  void selectDeviceView(int command) {
    final next = command == 255
        ? 5
        : command == 254
            ? 2
            : command >= 14 && command <= 17
                ? 18 - command
                : 0;
    if (next == 0) return;
    if (next != deviceViewLevel) {
      _deviceViewLevel = next;
      _deviceCameraGeneration++;
      _deviceOverview = null;
    }
    if (!_isNavigating || _activeRoute == null || !_currentState.gpsAvailable) {
      return;
    }
    unawaited(BleNavigationService.instance.sendRouteSegment(_routeWindow(
        LatLng(_currentState.currentLatitude, _currentState.currentLongitude),
        _currentState.heading)));
  }

  RouteWindowSegment currentDeviceRouteWindow() => _routeWindow(
      LatLng(_currentState.currentLatitude, _currentState.currentLongitude),
      _currentState.heading);

  RouteWindowSegment _routeWindow(LatLng rider, double heading) {
    final window = RouteWindowTransformer.transform(
      riderPosition: rider,
      riderHeadingDeg: heading,
      polylinePoints: _activeRoute!.polylinePoints,
      destination: _destination!,
      minimumRouteIndex: _routeProgressIndex,
      distanceToManeuverMeters: _currentState.maneuverDistanceMeters,
      followingLegDistanceMeters: _currentState.nextManeuverDistanceMeters,
      windowMeters: const [
        150.0,
        300.0,
        700.0,
        1800.0,
        1800.0
      ][deviceViewLevel - 1],
      focusManeuver: deviceViewLevel <= 2,
      overviewViewport: deviceOverviewViewport,
    );
    _routeProgressIndex = window.routeIndex;
    return window;
  }

  Future<void> _refreshNavContextIfNeeded(LatLng rider, double heading) async {
    if (_routeLoader != null ||
        _contextFetchInFlight ||
        !_isNavigating ||
        _activeRoute == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastPoiPublish == null ||
        now.difference(_lastPoiPublish!) >= const Duration(seconds: 5)) {
      _lastPoiPublish = now;
      unawaited(_publishHudPois(rider, heading));
    }
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
      final selected = <int, Destination>{};
      final points = route.polylinePoints;
      for (var type = 1; type <= 2; type++) {
        var bestScore = double.infinity;
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
            selected[type] = place;
            bestScore = score;
          }
        }
      }
      if (!_isNavigating || !identical(_activeRoute, route)) return;
      _hudPois
        ..clear()
        ..addAll(selected);
      await _publishHudPois(rider, heading);
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

  // â”€â”€ START NAVIGATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Starts turn-by-turn motorcycle navigation to the given destination.
  ///
  /// STEP 1â€“12 of the master prompt START RIDE workflow.
  /// The live phone fix always drives progress after the ride begins.  An
  /// optional [startLocation] lets the planner preview and initialise a route
  /// between two entered places (instead of silently assuming current GPS).
  /// If the rider starts somewhere else, the existing off-route logic safely
  /// recalculates from the real phone position.
  Future<bool> startNavigation(
    Destination destination, {
    Destination? startLocation,
    NavigationSession? resumedSession,
    List<Destination>? journeyStops,
  }) async {
    if (_stopping != null) await _stopping;
    if (_isStarting) return false;
    if (_isNavigating) return true;
    _isStarting = true;
    final generation = ++_rideGeneration;
    _deviceViewLevel = 2;
    _deviceCameraGeneration++;
    _deviceOverview = null;
    try {
      _currentDestination = destination;
      _stops
        ..clear()
        ..addAll(
            journeyStops?.isNotEmpty == true ? journeyStops! : [destination]);
      _changingStop = false;
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
      _stops[0] = resolvedDest;

      // 2. Obtain fresh current GPS position as origin (STEP 3â€“4 of master prompt)
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
      _hudPois.clear();
      _lastContextFetchAt = null;
      _currentStepIndex = 0;
      _isNavigating = true;
      _isRerouting = false;
      _reroutePending = false;
      _paused = false;
      _routeRevision++;
      _rerouteFailures = 0;
      _nextRerouteAllowedAt = null;
      _offRouteDetector.reset();
      _arrivalCandidateSince = null;
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
      _sessionDistanceTravelled = resumedSession?.distanceMeters ?? 0;
      _sessionMaxSpeedKmh = resumedSession?.maxSpeedKmh ?? 0;
      _savedActiveSeconds = resumedSession?.durationSeconds ?? 0;
      _rideClock
        ..reset()
        ..start();
      _lastRecordedAt = null;
      _lastCheckpointAt = null;
      _trailBreak = true;
      _trailBuffer.clear();
      _previousPos = null;

      // 5. Build initial NavigationState
      //    Speed MUST be 0.0 via SpeedFilter â€” do NOT multiply pos.speed blindly.
      final initialSpeed = LocationService.instance.lastSpeedKmh;
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
        speedKmh: initialSpeed, // 0.0 when parked âœ“
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
          await prefs.setString('resume_session_owner', 'guest');
        }
        if (generation != _rideGeneration) return false;
        await prefs.setString(
            'resume_active_session', _currentSession!.toJson());
        await _saveStops();
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
      _startDeviceAccessChecks();

      debugPrint(
          '[NavService] âœ“ Navigation started to ${destination.displayTitle} '
          '(${route.totalDistanceMeters.round()}m, ${route.steps.length} steps)');
      if (resumedSession?.status == 'paused') {
        _isStarting = false;
        pauseNavigation();
      }
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

  // â”€â”€ GPS LOST / RECOVERED â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onGpsAvailabilityChanged() {
    if (_paused) return;
    final isAvailable = LocationService.instance.isGpsAvailable;

    if (!isAvailable && _isNavigating) {
      // GPS lost during active navigation
      debugPrint('[NavService] âš  GPS signal lost during navigation');
      _currentState = NavigationState.gpsLost(_currentState);
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = RideState.gpsLost;
      BleNavigationService.instance.sendNavUpdate(_currentState, force: true);
    } else if (isAvailable && _currentState.rideState == RideState.gpsLost) {
      // GPS recovered
      debugPrint('[NavService] âœ“ GPS signal recovered');
      _currentState = _currentState.copyWith(
        gpsAvailable: true,
        rideState: RideState.navigating,
      );
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = RideState.navigating;
      BleNavigationService.instance.sendNavUpdate(_currentState, force: true);
    }
  }

  // â”€â”€ GPS TICK (Live Update Loop) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Called on every GPS position update from LocationService.
  /// This is the main navigation progress loop â€” runs locally, no network calls.
  void _onGpsTick() {
    if (!_isNavigating || _paused || _activeRoute == null) {
      return;
    }

    final rawPos = LocationService.instance.currentPosition;
    if (rawPos == null) return;

    // Validate raw GPS fix (reject stale fixes, poor accuracy, or teleportation jumps)
    final pos = _gpsFilter.filter(rawPos);
    if (pos == null) {
      // Discard invalid / noisy GPS point per Master Prompt Â§10
      return;
    }

    // Speed is pre-filtered by LocationService â†’ SpeedFilter (never shows jitter)
    final currentSpeed = LocationService.instance.speedKmhNotifier.value;
    final currentHeading = LocationService.instance.headingNotifier.value;
    final bleConnected = JustRideBleService.instance.isDeviceConnected;
    final riderLatLng = LatLng(pos.latitude, pos.longitude);

    final previousPos = _previousPos;
    // Record only fresh, accurate fixes. Never join a GPS outage with a straight line.
    if (pos.accuracy <= 25 &&
        LocationService.navigationFixFresh(pos, DateTime.now())) {
      final gap = _previousPos == null ||
          pos.timestamp.difference(_previousPos!.timestamp).inSeconds > 10;
      if (gap) _trailBreak = true;
      if (!gap && _previousPos != null && currentSpeed >= 1.5) {
        _sessionDistanceTravelled += _calculateDistanceMeters(
            LatLng(_previousPos!.latitude, _previousPos!.longitude),
            riderLatLng);
      }
      _previousPos = pos;
      if (currentSpeed > _sessionMaxSpeedKmh)
        _sessionMaxSpeedKmh = currentSpeed;
      _recordFix(pos);
    } else {
      _previousPos = null;
      _trailBreak = true;
    }

    var missedTurn = false;
    if (!_reroutePending && pos.accuracy <= 25 &&
        LocationService.navigationFixFresh(pos, DateTime.now())) {
      final steps = _activeRoute!.steps;
      missedTurn = _maneuverFsm.update(
        riderPosition: riderLatLng,
        riderHeading: currentHeading,
        steps: steps,
        riderSpeedKmh: currentSpeed,
        remainingAlongRouteMeters: _remainingStepDistance(
            riderLatLng, steps[_currentStepIndex.clamp(0, steps.length - 1)]),
      );
      _currentStepIndex = _maneuverFsm.activeStepIndex.clamp(0, steps.length - 1);
    }

    final offRouteState = _offRouteDetector.update(
      riderPosition: riderLatLng,
      timestamp: pos.timestamp,
      accuracyMeters: pos.accuracy,
      speedMs: currentSpeed / 3.6,
      polylinePoints: _activeRoute!.polylinePoints,
    );
    if (offRouteState == OffRouteState.offRoute ||
        (missedTurn && currentSpeed >= 5)) _reroutePending = true;
    if (_reroutePending &&
        !_changingStop &&
        _maneuverFsm.stage != ManeuverStage.missed &&
        !_isRerouting &&
        offRouteState == OffRouteState.onRoute &&
        pos.accuracy <= 25 &&
        currentSpeed >= 5) {
      _reroutePending = false;
      _rerouteFailures = 0;
      _nextRerouteAllowedAt = null;
    }
    if (_reroutePending) {
      _currentState = _currentState.copyWith(
        currentLatitude: pos.latitude,
        currentLongitude: pos.longitude,
        speedKmh: currentSpeed,
        heading: currentHeading,
        bleConnected: bleConnected,
        gpsAvailable: true,
        rerouting: true,
        rideState: RideState.rerouting,
        maneuverState: 'NONE',
        maneuverText: _changingStop
            ? (_isRerouting
                ? 'Next stop - calculating'
                : 'Next stop - retrying')
            : (_isRerouting || _rerouteFailures == 0
                ? 'Off route - rerouting'
                : 'Off route - retrying'),
      );
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = RideState.rerouting;
      unawaited(BleNavigationService.instance.sendNavUpdate(_currentState));
      if (!_isRerouting &&
          pos.accuracy <= 25 &&
          LocationService.navigationFixFresh(pos, DateTime.now())) {
        unawaited(_triggerReroute(riderLatLng));
      }
      return; // Never advance old steps or confirm arrival against an invalid route.
    }

    // 1. Arrival requires the final route segment, slow speed and a five-second dwell to
    //    avoid false arrival from GPS noise near the destination.
    final distanceToFinalDest =
        _calculateDistanceMeters(riderLatLng, _destination!);
    if (distanceToFinalDest <= 30.0 &&
        pos.accuracy <= 25 &&
        currentSpeed <= 10 &&
        _currentStepIndex == _activeRoute!.steps.length - 1 &&
        _remainingStepDistance(riderLatLng, _activeRoute!.steps.last) <= 25) {
      _arrivalCandidateSince ??= pos.timestamp;
      _arrivalConfirmCount++;
      if (_arrivalConfirmCount >= 5 &&
          pos.timestamp.difference(_arrivalCandidateSince!).inSeconds >= 5) {
        _onArrived(pos, bleConnected);
        return;
      }
    } else {
      _arrivalCandidateSince = null;
      _arrivalConfirmCount = 0;
    }

    // 2. Evaluate active step progress via Maneuver State Machine
    final steps = _activeRoute!.steps;

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

    final String effectiveManeuver = _maneuverFsm.displayManeuver;
    final int effectiveManeuverId = _currentStepIndex + 1;
    final String effectiveManeuverState = _maneuverFsm.maneuverStateString;
    double effectiveManeuverDist =
        _maneuverFsm.stage == ManeuverStage.turning && distToTurn <= 10
            ? 0.0
            : distToTurn;

    // 8. Determine ride state: STATIONARY when speed < 3.0 km/h
    final RideState activeRideState;
    if (currentSpeed < 3.0) {
      activeRideState = RideState.stationary;
    } else {
      activeRideState = RideState.navigating;
    }

    // Stationary GPS jitter filter:
    // When parked or stopped at a signal, GPS coordinates drift by Â±2-5m.
    // Freeze distance to prevent the HUD/app numbers from jumping around.
    if (activeRideState == RideState.stationary &&
        _currentState.maneuverDistanceMeters > 0) {
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

    final maneuverChanged = _currentState.maneuverId != effectiveManeuverId;

    // 9. Update NavigationState â€” single source of truth
    _currentState = NavigationState(
      currentLatitude: pos.latitude,
      currentLongitude: pos.longitude,
      speedKmh: currentSpeed, // 0.0 when stationary âœ“
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
      rerouting: false,
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
    // Refresh the display after 3 m of GPS movement or a new current maneuver.
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

    if (maneuverChanged ||
        distDelta >= 3.0 ||
        (headingDelta >= 15.0 && headingDelta <= 345.0)) {
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

  // â”€â”€ Previous position for session distance tracking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Position? _previousPos;

  // â”€â”€ REROUTE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _triggerReroute(LatLng riderLocation) async {
    if (!_isNavigating || _paused || _destination == null || _isRerouting) {
      return;
    }
    final generation = _rideGeneration;
    final now = DateTime.now();
    if (_nextRerouteAllowedAt != null && now.isBefore(_nextRerouteAllowedAt!)) {
      return;
    }

    _reroutePending = true;
    _isRerouting = true;
    _nextRerouteAllowedAt = now.add(_rerouteRetryCooldown);
    debugPrint('[NavService] Off-route! Triggering automatic reroute...');

    _currentState = _currentState.copyWith(
      rerouting: true,
      rideState: RideState.rerouting,
      maneuverText:
          _changingStop ? 'Next stop - calculating' : 'Off route - rerouting',
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
        _reroutePending = false;
        _changingStop = false;
        _activeRoute = newRoute;
        _routeProgressIndex = 0;
        _hudPois.clear();
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
        debugPrint('[NavService] âœ“ Rerouted successfully!');

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
            rerouting: true,
            rideState: _currentState.gpsAvailable
                ? RideState.rerouting
                : RideState.gpsLost,
            maneuverText: _changingStop
                ? 'Next stop - retrying'
                : 'Off route - retrying');
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
      // Keep invalid guidance suppressed while the cooldown limits network retries.
      _rerouteFailures++;
      _currentState = _currentState.copyWith(
          rerouting: true,
          rideState: _currentState.gpsAvailable
              ? RideState.rerouting
              : RideState.gpsLost,
          maneuverText:
              _changingStop ? 'Next stop - retrying' : 'Off route - retrying');
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

  // â”€â”€ ARRIVED â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onArrived(Position pos, bool bleConnected) {
    if (_stops.length > 1) {
      unawaited(skipStop());
      return;
    }
    _reroutePending = false;
    ++_rideGeneration;
    _isNavigating = false;
    _deviceAccessTimer?.cancel();
    _deviceAccessTimer = null;
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
    debugPrint('[NavService] â˜… Destination reached!');
  }

  // â”€â”€ PAUSE / RESUME â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> pauseNavigation() async {
    if (!_isNavigating || _paused) return;
    ++_rideGeneration; // Invalidate any in-flight reroute.
    _paused = true;
    _rideClock.stop();
    _trailBreak = true;
    _flushTrail();
    unawaited(_checkpointRide());
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
    _gpsTransition = _gpsTransition.then((_) => LocationService.instance.stopTracking());
    await _gpsTransition;
  }

  Future<void> resumeNavigation() async {
    if (!_isNavigating || !_paused || _resuming) return;
    _resuming = true;
    final generation = _rideGeneration;
    _gpsTransition = _gpsTransition.then((_) async {
      if (!_isNavigating || generation != _rideGeneration) return;
      final location = LocationService.instance;
      final resumeAt = DateTime.now();
      final started = await location.startTracking(distanceFilterMeters: 0, intervalMs: 400);
      if (!_isNavigating || generation != _rideGeneration) return;
      if (!started) return; // Stay paused; another Resume can retry permissions/GPS.
      final latest = location.currentPosition;
      final fix = latest != null && latest.timestamp.isAfter(resumeAt)
          ? latest : await location.getCurrentPosition();
      if (!_isNavigating || generation != _rideGeneration) return;
      final fresh = LocationService.navigationFixFresh(fix, DateTime.now()) &&
          fix!.timestamp.isAfter(resumeAt.subtract(const Duration(seconds: 1)));
      _paused = false;
      _rideClock.start();
      _trailBreak = true;
      _previousPos = null;
      _gpsFilter.reset();
      _offRouteDetector.reset();
      if (!fresh) location.isGpsAvailableNotifier.value = false;
      _currentState = _currentState.copyWith(
        gpsAvailable: fresh,
        rideState: !fresh ? RideState.gpsLost :
            _reroutePending ? RideState.rerouting : RideState.navigating,
        rerouting: _reroutePending,
        maneuverText: _reroutePending ? 'Off route - retrying' : _currentState.maneuverText,
      );
      navigationStateNotifier.value = _currentState;
      rideStateNotifier.value = _currentState.rideState;
      await BleNavigationService.instance.sendNavUpdate(
        _currentState, opCode: BleNavOpCode.navResume, force: true);
      if (fresh && _isNavigating && generation == _rideGeneration) _onGpsTick();
    });
    try { await _gpsTransition; } finally { _resuming = false; }
  }

  // â”€â”€ STOP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> stopNavigation() {
    return _stopping ??= _stopNavigation().whenComplete(() => _stopping = null);
  }

  Future<void> _stopNavigation() async {
    _deviceAccessTimer?.cancel();
    _deviceAccessTimer = null;
    ++_rideGeneration;
    _isStarting = false;
    _changingStop = false;
    _stops.clear();
    stopsChanged.value++;
    _paused = false;
    _isNavigating = false;
    _routeProgressIndex = 0;
    _reroutePending = false;
    _hudPois.clear();
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

    await _gpsTransition;
    await LocationService.instance.stopTracking();
    await BleNavigationService.instance.sendNavStop(_currentState);

    debugPrint('[NavService] Navigation stopped.');
  }

  // â”€â”€ Session Tracking Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _clearSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('resume_active_session');
      await prefs.remove('resume_destination');
      await prefs.remove('resume_stops');
      await prefs.remove('resume_session_owner');
    } catch (e) {
      debugPrint('[NavService] Failed to clear finished ride: $e');
    }
  }

  void _completeSession({String status = 'completed'}) {
    if (_currentSession != null) {
      _rideClock.stop();
      _flushTrail();
      final avgSpeed = activeRideSeconds > 0
          ? _sessionDistanceTravelled * 3.6 / activeRideSeconds
          : 0.0;
      final completed = _checkpointSession().complete(
        status: status,
        distanceMeters: _sessionDistanceTravelled,
        averageSpeedKmh: avgSpeed,
        maxSpeedKmh: _sessionMaxSpeedKmh,
        activeDurationSeconds: activeRideSeconds,
      );
      lastCompletedSession = completed;
      unawaited(RideHistoryService.instance
          .save(completed, _sessionUserId ?? 'guest'));
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

  // â”€â”€ Geometry Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
      if (prefs.getString('resume_session_owner') != (owner ?? 'guest')) {
        return false;
      }
      final savedSession = prefs.getString('resume_active_session');
      if (savedSession != null) {
        final session = NavigationSession.fromJson(savedSession);
        if (session.endTime == null && session.destination != null) {
          final stops = (prefs.getStringList('resume_stops') ?? [])
              .map(Destination.fromJson)
              .toList();
          return await startNavigation(
              stops.isNotEmpty ? stops.first : session.destination!,
              resumedSession: session,
              journeyStops: stops);
        }
        await prefs.remove('resume_active_session');
      }
    } catch (e) {
      debugPrint('[NavService] Failed to resume route: $e');
    }
    return false;
  }
}
