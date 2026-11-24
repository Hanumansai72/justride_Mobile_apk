import '../widgets/route_preview_map.dart';
import '../../../core/services/notification_listener_service.dart';
import '../../../core/models/ride_state.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/google_maps_service.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../../core/constants/google_maps_config.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/navigation_state.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/ride_history_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/telephony_service.dart';
import '../widgets/navigation_call_overlay.dart';
import '../../../core/utils/maneuver_mapper.dart';

// ── Obsidian & Emerald HUD palette ──────────────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const primary = AppColors.primary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const blueAccent = AppColors.primary;
  static const amber = AppColors.warning;
  static const red = AppColors.errorText;
}

/// Full-screen active motorcycle turn-by-turn navigation screen with Google Maps.
class ActiveNavigationScreen extends StatefulWidget {
  const ActiveNavigationScreen({super.key});

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  GoogleMapController? _mapController;
  NavigationRoute? _drawnRoute;
  Set<Polyline> _routePolylines = const {};
  bool _isFollowingUser = true;
  bool _isMapReady = false;
  BitmapDescriptor? _bikeMarkerIcon;
  final _ridePanelKey = GlobalKey();
  double _ridePanelHeight = 260;

  void _measureRidePanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _ridePanelKey.currentContext?.size?.height;
      if (height != null && (height - _ridePanelHeight).abs() > 1) {
        setState(() => _ridePanelHeight = height);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initBikeMarkerIcon();
  }

  Future<void> _initBikeMarkerIcon() async {
    try {
      final icon = await _createBikeMarkerBitmap();
      if (mounted) {
        setState(() {
          _bikeMarkerIcon = icon;
        });
      }
    } catch (e) {}
  }

  /// Generates a high-contrast, directional motorcycle icon for Google Maps.
  static Future<BitmapDescriptor> _createBikeMarkerBitmap() async {
    const size = 140.0;
    const center = Offset(size / 2, size / 2);
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);

    final chevron = Path()
      ..moveTo(center.dx, 10)
      ..lineTo(119, 120)
      ..lineTo(center.dx, 96)
      ..lineTo(21, 120)
      ..close();
    canvas.drawPath(chevron, Paint()..color = AppColors.primary);
    canvas.drawPath(
        chevron,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    picture.dispose();
    image.dispose();
    return BitmapDescriptor.bytes(bytes, width: 48, height: 48);
  }

  // Dark navigation map style
  static const String _darkMapStyle = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#0b100d"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#aab5ad"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#0b100d"}]},
    {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#34d399"}]},
    {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#141a16"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#1a211c"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#27382b"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#101812"}]}
  ]
  ''';

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _centerOnUser();
    if (mounted) {
      setState(() {
        _isMapReady = true;
      });
    }
  }

  void _centerOnUser() {
    final pos = LocationService.instance.currentPosition;
    if (pos != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 17.5,
            tilt: 45.0,
            bearing: pos.heading,
          ),
        ),
      );
      setState(() => _isFollowingUser = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _returnHome();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        body: ValueListenableBuilder<NavigationState>(
          valueListenable: NavigationService.instance.navigationStateNotifier,
          builder: (context, state, _) {
            _measureRidePanel();
            if (state.rideState == RideState.idle ||
                state.rideState == RideState.cancelled) {
              return SafeArea(
                  child: Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.route_outlined,
                                size: 40, color: AppColors.primary),
                            const SizedBox(height: 20),
                            const Text('Plan your next ride',
                                style: TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 24),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pushNamed('/go'),
                                child: const Text('Choose a destination')),
                          ]))));
            }
            if (state.rideState == RideState.arrived) {
              return SafeArea(
                  child: Center(
                      child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flag_rounded,
                      color: AppColors.primary, size: 64),
                  const SizedBox(height: 24),
                  const Text("You've arrived",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28, color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  if (NavigationService.instance.lastCompletedSession != null)
                    Text(
                        NavigationService
                            .instance.lastCompletedSession!.summary,
                        textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed('/dashboard'),
                      child: const Text('Done')),
                ]),
              )));
            }
            final route = NavigationService.instance.activeRoute;
            final isBleConnected =
                JustRideBleService.instance.isDeviceConnected;

            // Update camera smoothly if following user (use moveCamera to avoid animation cancel/restart stutter during real-time GPS stream)
            if (_isFollowingUser &&
                _mapController != null &&
                state.currentLatitude != 0) {
              _mapController!.moveCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target:
                        LatLng(state.currentLatitude, state.currentLongitude),
                    zoom: 17.5,
                    tilt: 45.0,
                    bearing: state.heading,
                  ),
                ),
              );
            }

            final markers = <Marker>{};
            if (!identical(_drawnRoute, route)) {
              _drawnRoute = route;
              _routePolylines = route == null || route.polylinePoints.isEmpty
                  ? const {}
                  : selectedRoutePolylines(route, width: 7);
            }

            // Rider GPS Marker
            if (state.currentLatitude != 0) {
              markers.add(
                Marker(
                  markerId: const MarkerId('rider'),
                  position:
                      LatLng(state.currentLatitude, state.currentLongitude),
                  rotation: state.heading,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                  icon: _bikeMarkerIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueGreen),
                ),
              );
            }

            // Destination Marker (RED per Master Design System)
            final dest = NavigationService.instance.currentDestination;
            if (dest != null && dest.latitude != 0) {
              markers.add(
                Marker(
                  markerId: const MarkerId('destination'),
                  position: LatLng(dest.latitude, dest.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed),
                  infoWindow: InfoWindow(title: dest.displayTitle),
                ),
              );
            }

            return Stack(
              children: [
                // 1. Google Map View
                if (route != null && NavigationService.instance.hasOfflineTour)
                  Positioned.fill(
                    bottom: 210,
                    top: 100,
                    child: RecordedTrackMap(
                        route: route,
                        rider: LatLng(
                            state.currentLatitude, state.currentLongitude)),
                  )
                else if (!GoogleMapsConfig.hasApiKey ||
                    (kIsWeb && !GoogleMapsConfig.webMapsLoaded))
                  const Center(
                      child: Text(
                          'The map is unavailable. Turn instructions will remain visible during your ride.'))
                else
                  Listener(
                    onPointerMove: (_) {
                      if (_isFollowingUser) {
                        setState(() => _isFollowingUser = false);
                      }
                    },
                    child: GoogleMap(
                      onMapCreated: _onMapCreated,
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          state.currentLatitude != 0
                              ? state.currentLatitude
                              : (route?.polylinePoints.isNotEmpty == true
                                  ? route!.polylinePoints.first.latitude
                                  : 0),
                          state.currentLongitude != 0
                              ? state.currentLongitude
                              : (route?.polylinePoints.isNotEmpty == true
                                  ? route!.polylinePoints.first.longitude
                                  : 0),
                        ),
                        zoom: 17.0,
                      ),
                      style: _darkMapStyle,
                      markers: markers,
                      polylines: _routePolylines,
                      myLocationEnabled:
                          false, // Using custom directional rider marker
                      myLocationButtonEnabled: false,
                      compassEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                  ),

                // Map Loading Screen Overlay until Google Map tiles and camera are ready
                if (GoogleMapsConfig.hasApiKey &&
                    !_isMapReady &&
                    (!kIsWeb || GoogleMapsConfig.webMapsLoaded))
                  Positioned.fill(
                    child: Container(
                      color: _C.bg,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _C.cardBg,
                                border: Border.all(
                                  color: _C.primary.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _C.primary.withValues(alpha: 0.25),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: _C.primary,
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Loading your route…',
                              style: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                color: _C.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Finding your location',
                              style: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                color: _C.textSec,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 2. Top Maneuver Banner (HUD Arrow + Distance + Next Street)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: _buildManeuverBanner(state),
                    ),
                  ),
                ),

                // 3. GPS LOST banner — shown prominently when satellite fix is lost
                if (!state.gpsAvailable) _buildGpsLostBanner(),

                // 4. Floating HUD Map Controls (Recenter, Zoom In, Zoom Out, Route Overview)
                Positioned(
                  right: 16,
                  bottom: _ridePanelHeight + 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Compass / Recenter Button
                      FloatingActionButton.small(
                        heroTag: 'recenter_btn',
                        backgroundColor: _C.cardBg,
                        foregroundColor: _isFollowingUser
                            ? _C.primary
                            : AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color:
                                _isFollowingUser ? _C.primary : _C.cardBorder,
                          ),
                        ),
                        onPressed: _centerOnUser,
                        child: const Icon(Icons.my_location_rounded, size: 20),
                      ),
                      const SizedBox(height: 8),

                      // Zoom In Button
                      FloatingActionButton.small(
                        heroTag: 'zoom_in_btn',
                        backgroundColor: _C.cardBg,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(color: _C.cardBorder),
                        ),
                        onPressed: () {
                          _mapController?.animateCamera(CameraUpdate.zoomIn());
                        },
                        child: const Icon(Icons.add_rounded, size: 22),
                      ),
                      const SizedBox(height: 8),

                      // Zoom Out Button
                      FloatingActionButton.small(
                        heroTag: 'zoom_out_btn',
                        backgroundColor: _C.cardBg,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(color: _C.cardBorder),
                        ),
                        onPressed: () {
                          _mapController?.animateCamera(CameraUpdate.zoomOut());
                        },
                        child: const Icon(Icons.remove_rounded, size: 22),
                      ),
                      const SizedBox(height: 8),

                      // Route Overview Button (Fit whole route)
                      FloatingActionButton.small(
                        heroTag: 'overview_btn',
                        backgroundColor: _C.cardBg,
                        foregroundColor: _C.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(color: _C.cardBorder),
                        ),
                        onPressed: () {
                          final r = NavigationService.instance.activeRoute;
                          if (r != null &&
                              r.polylinePoints.isNotEmpty &&
                              _mapController != null) {
                            setState(() => _isFollowingUser = false);
                            double minLat = 90.0,
                                maxLat = -90.0,
                                minLng = 180.0,
                                maxLng = -180.0;
                            for (final pt in r.polylinePoints) {
                              if (pt.latitude < minLat) minLat = pt.latitude;
                              if (pt.latitude > maxLat) maxLat = pt.latitude;
                              if (pt.longitude < minLng) minLng = pt.longitude;
                              if (pt.longitude > maxLng) maxLng = pt.longitude;
                            }
                            _mapController!.animateCamera(
                              CameraUpdate.newLatLngBounds(
                                LatLngBounds(
                                  southwest: LatLng(minLat, minLng),
                                  northeast: LatLng(maxLat, maxLng),
                                ),
                                48.0,
                              ),
                            );
                          }
                        },
                        child: const Icon(Icons.route_rounded, size: 20),
                      ),
                    ],
                  ),
                ),

                // 5. Bottom Motorcycle Telemetry HUD (Speed, Distance, ETA, Controls)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    key: _ridePanelKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Incoming / Active Call HUD Overlay at the bottom
                      ValueListenableBuilder<RideNotificationMode>(
                        valueListenable:
                            NotificationListenerService.instance.rideMode,
                        builder: (context, mode, child) =>
                            mode == RideNotificationMode.off
                                ? const SizedBox.shrink()
                                : child!,
                        child: ValueListenableBuilder<IncomingCallInfo>(
                          valueListenable:
                              TelephonyService.instance.callInfoNotifier,
                          builder: (context, callInfo, _) =>
                              callInfo.hasActiveCall
                                  ? NavigationCallOverlay(callInfo: callInfo)
                                  : const SizedBox.shrink(),
                        ),
                      ),
                      _buildBottomHud(state, isBleConnected),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Full-screen GPS LOST warning banner (shown over the map)
  Widget _buildGpsLostBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.gps_off_rounded,
                  color: AppColors.errorText, size: 20),
              const SizedBox(width: 8),
              Text(
                'Location unavailable',
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.errorText,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· Speed: --',
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// High-contrast top banner displaying next turn instruction
  Widget _buildManeuverBanner(NavigationState state) {
    final maneuver = state.maneuver;
    final isRerouting = state.rerouting;

    return Container(
      decoration: BoxDecoration(
        color: isRerouting ? _C.cardBg : _C.cardBg.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isRerouting ? _C.amber : _C.primary.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          // Maneuver Turn Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isRerouting
                  ? _C.amber.withValues(alpha: 0.15)
                  : _C.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: isRerouting
                ? const Icon(Icons.sync_rounded, color: _C.amber, size: 30)
                : Icon(
                    ManeuverMapper.toIcon(maneuver),
                    color: _C.primary,
                    size: 40,
                  ),
          ),
          const SizedBox(width: 14),

          // Maneuver Distance & Street Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      isRerouting
                          ? 'Updating route'
                          : state.maneuverDistanceFormatted,
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                        color: isRerouting ? _C.amber : _C.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  state.maneuverText,
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: _C.textSec,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined,
                color: AppColors.textSecondary, size: 22),
            onPressed: _returnHome,
          ),
        ],
      ),
    );
  }

  /// Bottom HUD panel: Speedometer, Total Distance, ETA, BLE Status, and Exit
  Future<void> _manageStops() async {
    final nav = NavigationService.instance;
    final query = TextEditingController();
    List<Destination> results = [];
    bool searching = false;
    String? error;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => SafeArea(
                  child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16,
                          16 + MediaQuery.viewInsetsOf(context).bottom),
                      child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * .65,
                        child: ValueListenableBuilder<int>(
                            valueListenable: nav.stopsChanged,
                            builder: (context, _, child) => Column(children: [
                                  const Text('Ride stops',
                                      style: TextStyle(fontSize: 22)),
                                  const Text(
                                      'Active stop stays first. Use Skip to change it.'),
                                  TextField(
                                      controller: query,
                                      decoration: const InputDecoration(
                                          labelText: 'Search for a stop'),
                                      onSubmitted: (_) async {
                                        if (searching ||
                                            query.text.trim().length < 2)
                                          return;
                                        update(() {
                                          searching = true;
                                          error = null;
                                        });
                                        try {
                                          results = await GoogleMapsService
                                              .instance
                                              .searchPlaces(query.text);
                                        } catch (_) {
                                          error =
                                              'Search unavailable. Try again when connected.';
                                        }
                                        if (context.mounted)
                                          update(() => searching = false);
                                      }),
                                  if (searching)
                                    const LinearProgressIndicator(),
                                  if (error != null) Text(error!),
                                  Expanded(
                                      child: ListView(children: [
                                    for (final result in results)
                                      ListTile(
                                          leading: const Icon(Icons.add),
                                          title: Text(result.displayTitle),
                                          onTap: () async {
                                            try {
                                              await nav.addStop(result);
                                            } catch (_) {
                                              if (context.mounted)
                                                update(() => error =
                                                    'Could not add this stop. Select a location with valid coordinates.');
                                              return;
                                            }
                                            if (context.mounted)
                                              update(() {
                                                results = [];
                                                query.clear();
                                              });
                                          }),
                                    for (var i = 0;
                                        i < nav.remainingStops.length;
                                        i++)
                                      ListTile(
                                          title: Text(
                                              '${i + 1}. ${nav.remainingStops[i].displayTitle}'),
                                          subtitle: i == 0
                                              ? const Text('Active destination')
                                              : null,
                                          trailing: i == 0
                                              ? null
                                              : Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                      IconButton(
                                                          tooltip:
                                                              'Move earlier',
                                                          onPressed: i > 1
                                                              ? () =>
                                                                  nav.moveStop(
                                                                      i, i - 1)
                                                              : null,
                                                          icon: const Icon(Icons
                                                              .arrow_upward)),
                                                      IconButton(
                                                          tooltip: 'Move later',
                                                          onPressed: i + 1 <
                                                                  nav.remainingStops
                                                                      .length
                                                              ? () =>
                                                                  nav.moveStop(
                                                                      i, i + 1)
                                                              : null,
                                                          icon: const Icon(Icons
                                                              .arrow_downward)),
                                                      IconButton(
                                                          tooltip:
                                                              'Remove stop',
                                                          onPressed: () =>
                                                              nav.removeStop(i),
                                                          icon: const Icon(
                                                              Icons.close)),
                                                    ])),
                                  ])),
                                  FilledButton(
                                      onPressed: nav.remainingStops.length >
                                                  1 &&
                                              stateAllowsSkip(nav.currentState)
                                          ? () async {
                                              Navigator.pop(context);
                                              await nav.skipStop();
                                            }
                                          : null,
                                      child: const Text('Skip active stop')),
                                ])),
                      )),
                )));
    query.dispose();
  }

  bool stateAllowsSkip(NavigationState state) =>
      state.rideState != RideState.paused && !state.rerouting;

  Widget _buildBottomHud(NavigationState state, bool isBleConnected) {
    return Container(
      decoration: const BoxDecoration(
        color: _C.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: _C.cardBorder, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                  child: TextButton.icon(
                      onPressed: NavigationService.instance.hasOfflineTour
                          ? null
                          : _manageStops,
                      style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 10)),
                      icon: const Icon(Icons.location_on_outlined, size: 20),
                      label: Text(
                          NavigationService
                                  .instance.currentDestination?.displayTitle ??
                              'Destination',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis))),
              if (state.rideState == RideState.paused)
                TextButton(
                  onPressed: NavigationService.instance.resumeNavigation,
                  child: const Text('Resume ride'),
                ),
            ]),
            const Divider(height: 24),
            ValueListenableBuilder<String?>(
                valueListenable: RideHistoryService.instance.storageError,
                builder: (context, message, _) => message == null
                    ? const SizedBox.shrink()
                    : Text(message,
                        style: const TextStyle(color: AppColors.warning))),
            // Row 1: Speed, Remaining Distance, ETA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 1. Live Speedometer — uses speedDisplay which returns '--' on GPS loss
                _buildTelemetryColumn(
                  label: 'Speed',
                  value: state.speedDisplay,
                  unit: state.gpsAvailable ? 'KM/H' : '',
                  valueColor: state.gpsAvailable ? _C.primary : _C.textSec,
                ),
                Container(width: 1, height: 40, color: _C.cardBorder),

                // 2. Remaining Distance
                _buildTelemetryColumn(
                  label: 'Remaining',
                  value: state.remainingDistanceFormatted,
                  unit: '',
                  valueColor: _C.onSurface,
                ),
                Container(width: 1, height: 40, color: _C.cardBorder),

                // 3. ETA
                _buildTelemetryColumn(
                  label: 'Arrival',
                  value: state.arrivalTimeFormatted,
                  unit: '(${state.remainingDurationFormatted})',
                  valueColor: _C.blueAccent,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Row 2: BLE Device Indicator & Stop Ride Button
            Row(
              children: [
                // BLE HUD status pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBleConnected
                        ? _C.blueAccent.withValues(alpha: 0.12)
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isBleConnected
                          ? _C.blueAccent.withValues(alpha: 0.3)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isBleConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        size: 14,
                        color: isBleConnected
                            ? _C.blueAccent
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isBleConnected ? 'Device connected' : 'Device offline',
                        style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isBleConnected
                              ? _C.blueAccent
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // End Ride CTA Button
                ElevatedButton.icon(
                  onPressed: _confirmExitNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error.withValues(alpha: 0.15),
                    foregroundColor: _C.red,
                    elevation: 0,
                    side: const BorderSide(color: _C.red, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(
                    'End ride',
                    style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryColumn({
    required String label,
    required String value,
    required String unit,
    required Color valueColor,
  }) {
    return Expanded(
        child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Stack Sans Text',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _C.textSec,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: valueColor,
                ),
              ),
            )),
        const SizedBox(height: 4),
        Text(
          unit.isEmpty ? ' ' : unit,
          style: TextStyle(
            fontFamily: 'Stack Sans Text',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _C.textSec,
          ),
        ),
      ],
    ));
  }

  void _returnHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
  }

  Future<void> _confirmExitNavigation() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'End this ride?',
          style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: _C.onSurface,
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Your progress will be saved in ride history.',
          style: TextStyle(fontFamily: 'Stack Sans Text', color: _C.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Continue ride',
                style: TextStyle(
                    fontFamily: 'Stack Sans Text', color: _C.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.textPrimary),
            child: Text('End ride',
                style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      await NavigationService.instance.stopNavigation();
      if (mounted) _returnHome();
    }
  }
}
