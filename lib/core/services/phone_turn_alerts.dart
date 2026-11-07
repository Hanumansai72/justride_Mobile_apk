import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/navigation_state.dart';
import '../models/ride_state.dart';
import 'navigation_service.dart';
import 'location_service.dart';

/// Optional native phone haptics; never changes the route or BLE guidance.
class PhoneTurnAlerts {
  static final enabled = ValueNotifier<bool>(false);
  static String? _lastManeuver;
  static bool _initialized = false;
  static const _key = 'phone_turn_vibration';

  static bool eligible(NavigationState state) =>
      state.rideState.isActive &&
      state.rideState != RideState.paused &&
      state.gpsAvailable &&
      !state.rerouting &&
      state.maneuverState.toUpperCase() != 'COMPLETED' &&
      state.maneuverState.toUpperCase() != 'TURN_COMPLETED' &&
      state.maneuverDistanceMeters.isFinite &&
      state.maneuverDistanceMeters >= 0 &&
      state.maneuverDistanceMeters <= 100 &&
      const {
        'LEFT',
        'RIGHT',
        'TURN_LEFT',
        'TURN_RIGHT',
        'SLIGHT_LEFT',
        'SLIGHT_RIGHT',
        'SHARP_LEFT',
        'SHARP_RIGHT'
      }.contains(state.maneuver.toUpperCase());

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      enabled.value = preferences.getBool(_key) ?? false;
    } catch (error) {
      debugPrint('[TurnAlerts] Saved preference unavailable: $error');
    }
    NavigationService.instance.navigationStateNotifier
        .addListener(_onNavigation);
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, value);
  }

  static void _onNavigation() {
    final nav = NavigationService.instance;
    final state = nav.navigationStateNotifier.value;
    if (!state.rideState.isActive) {
      _lastManeuver = null;
      return;
    }
    final key = '${nav.routeRevision}:${state.maneuverId}:${state.maneuver}';
    if (!enabled.value ||
        !eligible(state) ||
        key == _lastManeuver ||
        !LocationService.instance.hasFreshNavigationFix) return;
    _lastManeuver = key;
    unawaited(HapticFeedback.heavyImpact().catchError((Object error) {
      debugPrint('[TurnAlerts] Phone haptics unavailable: $error');
    }));
  }
}
