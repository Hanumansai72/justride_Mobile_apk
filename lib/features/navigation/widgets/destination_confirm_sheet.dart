import '../../../core/services/fuel_stop_service.dart';
import '../../../core/services/ride_planning_store.dart';
import 'fuel_range_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/bike_route_preferences.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../shared/widgets/require_device_connection.dart';
import 'route_preview_map.dart';
import 'route_weather_panel.dart';

class DestinationConfirmSheet extends StatefulWidget {
  const DestinationConfirmSheet(
      {super.key,
      required this.destination,
      this.startLocation,
      this.commute = false});
  final Destination destination;
  final Destination? startLocation;
  final bool commute;
  static BuildContext? _activeSheetContext;

  static Future<bool?> show(BuildContext context, Destination destination,
      {Destination? startLocation, bool commute = false}) {
    if (_activeSheetContext?.mounted == true)
      Navigator.of(_activeSheetContext!).pop();
    BuildContext? shownContext;
    return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.transparent,
        builder: (context) {
          shownContext = context;
          _activeSheetContext = context;
          return DestinationConfirmSheet(
              destination: destination,
              startLocation: startLocation,
              commute: commute);
        }).whenComplete(() {
      if (identical(_activeSheetContext, shownContext))
        _activeSheetContext = null;
    });
  }

  @override
  State<DestinationConfirmSheet> createState() =>
      _DestinationConfirmSheetState();
}

class _DestinationConfirmSheetState extends State<DestinationConfirmSheet> {
  bool _loading = true, _starting = false;
  int _generation = 0;
  static const _preferencesKey = 'bike_route_preferences';
  BikeRoutePreferences _preferences = const BikeRoutePreferences();
  List<NavigationRoute> _options = [];
  NavigationRoute? _route;
  LatLng? _previewOrigin;
  Destination? _destination, _start;
  String? _error, _fuelMessage;
  bool _findingFuel = false, _savingCommute = false;
  FuelStopPlan? _fuelStop;
  double? _fuelRangeKm;
  static bool _located(Destination value) =>
      value.latitude.isFinite &&
      value.longitude.isFinite &&
      value.latitude.abs() <= 90 &&
      value.longitude.abs() <= 180 &&
      (value.latitude != 0 || value.longitude != 0);

  @override
  void initState() {
    super.initState();
    _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _preferences =
        BikeRoutePreferences.fromFlags(prefs.getInt(_preferencesKey) ?? 0);
    await _loadPreview();
  }

  Future<void> _editPreferences() async {
    var tolls = _preferences.avoidTolls;
    var highways = _preferences.avoidHighways;
    var ferries = _preferences.avoidFerries;
    final updated = await showDialog<BikeRoutePreferences>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDraft) {
        return AlertDialog(
          title: const Text('Bike route preferences'),
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                  title: const Text('Avoid tolls'),
                  value: tolls,
                  onChanged: (value) => setDraft(() => tolls = value)),
              SwitchListTile(
                  title: const Text('Avoid highways'),
                  value: highways,
                  onChanged: (value) => setDraft(() => highways = value)),
              SwitchListTile(
                  title: const Text('Avoid ferries'),
                  value: ferries,
                  onChanged: (value) => setDraft(() => ferries = value)),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Routes may still include these if there is no practical alternative.'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  BikeRoutePreferences(
                      avoidTolls: tolls,
                      avoidHighways: highways,
                      avoidFerries: ferries)),
              child: const Text('Apply'),
            ),
          ],
        );
      }),
    );
    if (!mounted || updated == null || updated.flags == _preferences.flags)
      return;
    _preferences = updated;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(_preferencesKey, updated.flags);
    if (mounted) await _loadPreview();
  }

  Future<Destination?> _resolve(Destination value) async {
    if (_located(value)) return value;
    return await GoogleMapsService.instance.resolveDestination(value);
  }

  Future<void> _loadPreview() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _route = null;
      _fuelStop = null;
      _fuelMessage = null;
    });
    try {
      final destination = await _resolve(widget.destination);
      if (destination == null || !_located(destination)) {
        throw StateError(
            'We couldn’t find this destination. Try again or choose it from search.');
      }
      final start = widget.startLocation == null
          ? null
          : await _resolve(widget.startLocation!);
      if (widget.startLocation != null && (start == null || !_located(start))) {
        throw StateError(
            'We couldn’t find the starting point. Choose it from search.');
      }
      final saved = LocationService.instance.currentPosition;
      final position = start != null
          ? null
          : LocationService.navigationFixFresh(saved, DateTime.now())
              ? saved
              : await LocationService.instance.getCurrentPosition();
      if (start == null && position == null) {
        throw StateError(
            'Your location is unavailable. Turn on location access and try again.');
      }
      final origin = start != null
          ? LatLng(start.latitude, start.longitude)
          : LatLng(position!.latitude, position.longitude);
      final options = await GoogleMapsService.instance.bikeRouteOptions(
          origin: origin,
          destination: LatLng(destination.latitude, destination.longitude),
          preferences: _preferences);
      final route = options.firstOrNull;
      if (route == null ||
          route.polylinePoints.isEmpty ||
          route.steps.isEmpty) {
        throw StateError(_preferences.hasAvoidances
            ? 'No bike route was returned. Check your connection or change your route preferences.'
            : 'We couldn’t find a route. Check your connection or choose another destination.');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _destination = destination;
        _start = start;
        _options = options;
        _previewOrigin = origin;
        _route = route;
      });
    } on StateError catch (error) {
      if (mounted && generation == _generation)
        setState(() => _error = userFacingError(error.message.toString()));
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() => _error =
            'We couldn’t load the route. Check your connection and try again.');
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _saveCommute() async {
    final destination = _destination;
    if (_savingCommute || destination == null) return;
    setState(() => _savingCommute = true);
    try {
      final owner = await RidePlanningStore.owner();
      final saved = await RidePlanningStore.commutes(owner);
      final entry = SavedCommute(destination: destination, start: _start);
      final rows = [
        entry,
        ...saved.where((item) => item.toJson() != entry.toJson())
      ];
      final success =
          await RidePlanningStore.saveCommutes(owner, rows.take(6).toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Saved in Ride tools → Commutes'
              : 'Could not save this commute.')));
    } finally {
      if (mounted) setState(() => _savingCommute = false);
    }
  }

  Future<void> _findFuel() async {
    if (_findingFuel ||
        _route == null ||
        _previewOrigin == null ||
        _destination == null) return;
    final planned = _route!;
    final range = await showFuelRangeDialog(context);
    if (!mounted || range == null || !identical(planned, _route)) return;
    final generation = _generation;
    final destination = _destination!;
    setState(() {
      _findingFuel = true;
      _fuelRangeKm = range;
      _fuelMessage = null;
      _fuelStop = null;
    });
    try {
      final result = await FuelStopService().find(
          route: planned,
          origin: _previewOrigin!,
          destination: LatLng(destination.latitude, destination.longitude),
          rangeKm: range,
          preferences: _preferences);
      if (!mounted || generation != _generation || !identical(planned, _route))
        return;
      setState(() {
        _fuelStop = result;
        if (result == null)
          _fuelMessage =
              'No reachable fuel stop found near this route. Refuel before departure if needed.';
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _fuelMessage =
            'Could not check fuel stops. Try again when connected.');
      }
    } finally {
      if (mounted) setState(() => _findingFuel = false);
    }
  }

  Future<void> _startRide() async {
    if (_starting ||
        _loading ||
        _findingFuel ||
        _route == null ||
        _destination == null) return;
    if (!await requireDeviceConnection(context) || !mounted) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (_start == null) {
        final location = LocationService.instance;
        final cached = location.currentPosition;
        final fix = LocationService.navigationFixFresh(cached, DateTime.now())
            ? cached
            : await location.getCurrentPosition();
        if (!mounted) return;
        if (fix == null ||
            !LocationService.navigationFixFresh(fix, DateTime.now())) {
          setState(() =>
              _error = 'Your current location is unavailable. Try again.');
          return;
        }
        final origin = _previewOrigin!;
        if (Geolocator.distanceBetween(origin.latitude, origin.longitude,
                fix.latitude, fix.longitude) >
            50) {
          setState(() {
            _route = null;
            _error =
                'Your location changed. Try again to refresh the bike routes.';
          });
          return;
        }
      }
      final fuel = _fuelStop;
      final started = await NavigationService.instance.startNavigation(
          fuel?.station ?? _destination!,
          startLocation: _start,
          selectedRoute: fuel?.toStation ?? _route,
          journeyStops: fuel == null ? null : [fuel.station, _destination!],
          preferences: _preferences);
      if (!mounted) return;
      if (!started) {
        setState(() => _error =
            'Your ride couldn’t start. Check your location and connection, then try again.');
        return;
      }
      final navigator = Navigator.of(context);
      navigator.pop(true);
      navigator.pushNamed('/active-navigation');
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Your ride couldn’t start. Please try again.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destination ?? widget.destination;
    final address = destination.address;
    final showAddress = address != null &&
        address.isNotEmpty &&
        address != destination.displayTitle &&
        !address.contains('://') &&
        !RegExp(r'^[-+]?\d+\.\d+[, ]').hasMatch(address);
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.9),
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                          child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: AppColors.textMuted,
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(
                            child: Text(
                                widget.commute
                                    ? 'Commute now'
                                    : 'Route preview',
                                style: AppTextStyles.headingLarge)),
                        IconButton(
                            tooltip: 'Close preview',
                            onPressed: _starting
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded))
                      ]),
                      const SizedBox(height: 16),
                      Text(destination.displayTitle,
                          style: AppTextStyles.headingMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (showAddress) ...[
                        const SizedBox(height: 6),
                        Text(address,
                            style: AppTextStyles.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)
                      ],
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.trip_origin, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                _start?.displayTitle ??
                                    widget.startLocation?.displayTitle ??
                                    'Your current location',
                                style: AppTextStyles.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis))
                      ]),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _loading || _starting || _findingFuel
                              ? null
                              : _editPreferences,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Route preferences'),
                        ),
                      ),
                      if (_preferences.hasAvoidances)
                        Text('Prefer to avoid: ${[
                          if (_preferences.avoidTolls) 'tolls',
                          if (_preferences.avoidHighways) 'highways',
                          if (_preferences.avoidFerries) 'ferries',
                        ].join(', ')}'),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()))
                      else if (_route != null) ...[
                        if (_options.length > 1) ...[
                          _routeChoices(),
                          const SizedBox(height: 12),
                        ],
                        if (widget.commute)
                          const Text(
                              'Current traffic estimates · choose the route before riding'),
                        RoutePreviewMap(
                          key: ObjectKey(_options),
                          route: _route!,
                          alternatives: _options,
                          height: (MediaQuery.sizeOf(context).height * 0.42)
                              .clamp(250.0, 380.0)
                              .toDouble(),
                        ),
                        RouteTrafficLegend(route: _route!),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                              child: _metric('Distance',
                                  _distance(_route!.totalDistanceMeters))),
                          Expanded(
                              child: _metric('Travel time',
                                  _duration(_route!.totalDurationSeconds)))
                        ]),
                      ],
                      if (_route != null) ...[
                        RouteWeatherPanel(
                          key: ObjectKey(_route),
                          route: _route!,
                        ),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, children: [
                          OutlinedButton.icon(
                            onPressed:
                                _starting || _findingFuel ? null : _findFuel,
                            icon: const Icon(Icons.local_gas_station_outlined),
                            label: Text(_findingFuel
                                ? 'Checking fuel stops…'
                                : 'Plan fuel stop'),
                          ),
                          if (!widget.commute)
                            TextButton.icon(
                              onPressed: _starting || _savingCommute
                                  ? null
                                  : _saveCommute,
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: const Text('Save commute'),
                            ),
                        ]),
                        if (_fuelStop != null || _fuelMessage != null)
                          Text(
                              'Estimated range before reserve: ${_fuelRangeKm!.floor()} km'),
                        if (_fuelMessage != null) Text(_fuelMessage!),
                        if (_fuelStop case final stop?)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.local_gas_station),
                            title: Text(
                                'First stop: ${stop.station.displayTitle}'),
                            subtitle: Text(
                                '${_distance(stop.toStation.totalDistanceMeters)} to fuel · about ${_duration(stop.detourSeconds)} extra'),
                            trailing: IconButton(
                              tooltip: 'Remove fuel stop',
                              onPressed: _starting
                                  ? null
                                  : () => setState(() => _fuelStop = null),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.errorLight,
                                    height: 1.45))),
                        if (!_starting)
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                  onPressed: _loading ? null : _loadPreview,
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Try again'))),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: _loading ||
                                  _starting ||
                                  _findingFuel ||
                                  _route == null
                              ? null
                              : _startRide,
                          icon: _starting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.navigation_outlined, size: 20),
                          label: Text(_starting
                              ? 'Starting ride…'
                              : _fuelStop == null
                                  ? 'Start ride'
                                  : 'Start ride via fuel')),
                      ValueListenableBuilder(
                          valueListenable: JustRideBleService
                              .instance.connectionStateNotifier,
                          builder: (context, _, child) => JustRideBleService
                                  .instance.isDeviceConnected
                              ? const SizedBox.shrink()
                              : const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                      'Connect your device to start the ride.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary)))),
                    ])),
          )),
    );
  }

  Widget _routeChoices() {
    final fastest = _options.reduce(
        (a, b) => a.totalDurationSeconds <= b.totalDurationSeconds ? a : b);
    final shortest = _options.reduce(
        (a, b) => a.totalDistanceMeters <= b.totalDistanceMeters ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, option) in _options.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            selected: identical(option, _route),
            leading: Icon(identical(option, _route)
                ? Icons.radio_button_checked
                : Icons.radio_button_off),
            title: Text(identical(option, fastest)
                ? (identical(option, shortest)
                    ? 'Fastest and shortest'
                    : 'Fastest')
                : (identical(option, shortest)
                    ? 'Shortest'
                    : 'Route ${index + 1}')),
            subtitle: Text(
                '${_duration(option.totalDurationSeconds)} · ${_distance(option.totalDistanceMeters)}${_comparison(option, fastest)}'),
            onTap: _starting || _findingFuel
                ? null
                : () => setState(() {
                      _route = option;
                      _fuelStop = null;
                      _fuelMessage = null;
                    }),
          ),
      ],
    );
  }

  String _comparison(NavigationRoute route, NavigationRoute fastest) {
    if (identical(route, fastest)) return '';
    final seconds = route.totalDurationSeconds - fastest.totalDurationSeconds;
    final metres = route.totalDistanceMeters - fastest.totalDistanceMeters;
    return [
      '',
      seconds == 0
          ? 'Same time'
          : '+${seconds >= 60 ? '${seconds ~/ 60} min ' : ''}${seconds % 60} sec',
      if (metres.abs() >= 1)
        '${_distance(metres.abs())} ${metres < 0 ? 'shorter' : 'longer'}'
      else
        'Same distance',
    ].join(' · ');
  }

  Widget _metric(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.headingLarge)
      ]);
  String _distance(double metres) => metres < 1000
      ? '${metres.round()} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';
  String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes >= 60
        ? '${minutes ~/ 60} hr ${minutes % 60} min'
        : '$minutes min';
  }
}
