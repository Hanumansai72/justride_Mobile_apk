import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/navigation_state.dart';
import '../../../core/models/simulated_location_packet.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/simulator_location_service.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/telephony_service.dart';
import '../widgets/navigation_call_overlay.dart';
import '../../../core/utils/maneuver_mapper.dart';

// ── Obsidian & Emerald HUD palette ──────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const cardBg = Color(0xFF101E22);
  static const cardBorder = Color(0xFF22353A);
  static const primary = Color(0xFF4BE277);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFF9EACB1);
  static const blueAccent = Color(0xFF38BDF8);
  static const amber = Color(0xFFFDA026);
  static const red = Color(0xFFFF5252);
}

/// Full-screen active motorcycle turn-by-turn navigation screen with Google Maps.
class ActiveNavigationScreen extends StatefulWidget {
  const ActiveNavigationScreen({super.key});

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  GoogleMapController? _mapController;
  bool _isFollowingUser = true;
  bool _isMapReady = false;
  BitmapDescriptor? _bikeMarkerIcon;

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
    } catch (e) {
      debugPrint('[ActiveNav] Error generating bike marker icon: $e');
    }
  }

  /// Generates a high-contrast, directional motorcycle icon for Google Maps.
  static Future<BitmapDescriptor> _createBikeMarkerBitmap() async {
    const size = 140.0;
    const center = Offset(size / 2, size / 2);
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);

    // 1. Forward directional indicator tip (pointing UP / North in direction of travel)
    final arrowPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(center.dx, 8.0)
      ..lineTo(center.dx - 14.0, 36.0)
      ..lineTo(center.dx + 14.0, 36.0)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);

    // 2. Outer pulse / glow halo
    final glowPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 48.0, glowPaint);

    // 3. Dark Disc Body
    final discPaint = Paint()
      ..color = const Color(0xFF0A1B1E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 38.0, discPaint);

    // 4. Emerald Accent Border
    final borderPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, 38.0, borderPaint);

    // 5. White Motorcycle / Two-Wheeler Icon in Center
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(Icons.two_wheeler_rounded.codePoint),
        style: TextStyle(
          fontSize: 42.0,
          fontFamily: Icons.two_wheeler_rounded.fontFamily,
          package: Icons.two_wheeler_rounded.fontPackage,
          color: Colors.white,
        ),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }

  // Dark navigation map style
  static const String _darkMapStyle = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#091316"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#74868c"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#091316"}]},
    {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#bccbb9"}]},
    {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#4be277"}]},
    {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#0d221c"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#182a30"}]},
    {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#0c181b"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#223b42"}]},
    {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#14252a"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#05161a"}]}
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
        if (!didPop) _confirmExitNavigation();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        body: ValueListenableBuilder<NavigationState>(
          valueListenable: NavigationService.instance.navigationStateNotifier,
          builder: (context, state, _) {
            final route = NavigationService.instance.activeRoute;
            final isBleConnected = JustRideBleService.instance.isDeviceConnected;

            // Update camera smoothly if following user (use moveCamera to avoid animation cancel/restart stutter during real-time GPS stream)
            if (_isFollowingUser && _mapController != null && state.currentLatitude != 0) {
              _mapController!.moveCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(state.currentLatitude, state.currentLongitude),
                    zoom: 17.5,
                    tilt: 45.0,
                    bearing: state.heading,
                  ),
                ),
              );
            }

            final markers = <Marker>{};
            final polylines = <Polyline>{};

            // Rider GPS Marker
            if (state.currentLatitude != 0) {
              markers.add(
                Marker(
                  markerId: const MarkerId('rider'),
                  position: LatLng(state.currentLatitude, state.currentLongitude),
                  rotation: state.heading,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                  icon: _bikeMarkerIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  infoWindow: InfoWindow(title: dest.displayTitle),
                ),
              );
            }

            // Route Polyline (VIBRANT ROYAL BLUE — 0x2979FF per Master Design System)
            if (route != null && route.polylinePoints.isNotEmpty) {
              polylines.add(
                Polyline(
                  polylineId: const PolylineId('active_route'),
                  points: route.polylinePoints,
                  color: const Color(0xFF2979FF),
                  width: 7,
                  jointType: JointType.round,
                  endCap: Cap.roundCap,
                  startCap: Cap.roundCap,
                ),
              );
            }

            return Stack(
              children: [
                // 1. Google Map View
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      state.currentLatitude != 0 ? state.currentLatitude : 12.9716,
                      state.currentLongitude != 0 ? state.currentLongitude : 77.5946,
                    ),
                    zoom: 17.0,
                  ),
                  style: _darkMapStyle,
                  markers: markers,
                  polylines: polylines,
                  myLocationEnabled: false, // Using custom directional rider marker
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onCameraMoveStarted: () {
                    // Rider touched the map, temporarily stop auto-centering
                    if (_isFollowingUser) {
                      setState(() => _isFollowingUser = false);
                    }
                  },
                ),

                // Map Loading Screen Overlay until Google Map tiles and camera are ready
                if (!_isMapReady)
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
                              'Loading Map & Route...',
                              style: GoogleFonts.inter(
                                color: _C.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Initializing GPS lock and route telemetry',
                              style: GoogleFonts.inter(
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _buildManeuverBanner(state),
                    ),
                  ),
                ),

                // 3. GPS LOST banner — shown prominently when satellite fix is lost
                if (!state.gpsAvailable)
                  _buildGpsLostBanner(),

                // Simulator Mode indicator pill
                ValueListenableBuilder<LocationSource>(
                  valueListenable: LocationService.instance.locationSourceNotifier,
                  builder: (context, source, _) {
                    if (source != LocationSource.simulator) return const SizedBox.shrink();
                    return SafeArea(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, top: 120),
                          child: GestureDetector(
                            onTap: _showSimulatorConfigSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.sports_esports_rounded, color: Colors.white, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    'SIMULATOR ACTIVE',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.settings_rounded, color: Colors.white70, size: 12),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // 4. Floating HUD Map Controls (Recenter, Zoom In, Zoom Out, Route Overview)
                Positioned(
                  right: 16,
                  bottom: 240,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Compass / Recenter Button
                      FloatingActionButton.small(
                        heroTag: 'recenter_btn',
                        backgroundColor: _C.cardBg,
                        foregroundColor: _isFollowingUser ? _C.primary : Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _isFollowingUser ? _C.primary : _C.cardBorder,
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
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: _C.cardBorder),
                        ),
                        onPressed: () {
                          final r = NavigationService.instance.activeRoute;
                          if (r != null && r.polylinePoints.isNotEmpty && _mapController != null) {
                            setState(() => _isFollowingUser = false);
                            double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
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
                      const SizedBox(height: 8),

                      // Simulator / Real GPS Mode Toggle Button (Tap to toggle, Long-press for config)
                      ValueListenableBuilder<LocationSource>(
                        valueListenable: LocationService.instance.locationSourceNotifier,
                        builder: (context, source, _) {
                          final isSim = source == LocationSource.simulator;
                          return GestureDetector(
                            onLongPress: _showSimulatorConfigSheet,
                            child: FloatingActionButton.small(
                              heroTag: 'sim_toggle_btn',
                              backgroundColor: isSim ? Colors.deepPurpleAccent : _C.cardBg,
                              foregroundColor: isSim ? Colors.white : Colors.white70,
                              tooltip: isSim ? 'Simulation Active (Long press to config)' : 'Switch to Simulator',
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSim ? Colors.deepPurpleAccent : _C.cardBorder,
                                ),
                              ),
                              onPressed: () {
                                final nextSource = isSim ? LocationSource.realGps : LocationSource.simulator;
                                LocationService.instance.setLocationSource(nextSource);
                                final isConnected = SimulatorLocationService.instance.isConnected;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 3),
                                    backgroundColor: _C.cardBg,
                                    content: Text(
                                      nextSource == LocationSource.simulator
                                          ? (isConnected
                                              ? '🎮 Simulation Active (Connected to Web Simulator)'
                                              : '🎮 Simulation Active (Connecting to ${SimulatorLocationService.instance.host}...)')
                                          : '🛰️ Real Phone GPS Active',
                                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                    action: nextSource == LocationSource.simulator && !isConnected
                                        ? SnackBarAction(
                                            label: 'CONFIG',
                                            textColor: _C.primary,
                                            onPressed: _showSimulatorConfigSheet,
                                          )
                                        : null,
                                  ),
                                );
                              },
                              child: Icon(
                                isSim ? Icons.sports_esports_rounded : Icons.satellite_alt_rounded,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // 5. Bottom Motorcycle Telemetry HUD (Speed, Distance, ETA, Controls)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Incoming / Active Call HUD Overlay at the bottom
                      ValueListenableBuilder<IncomingCallInfo>(
                        valueListenable: TelephonyService.instance.callInfoNotifier,
                        builder: (context, callInfo, _) {
                          if (!callInfo.hasActiveCall) return const SizedBox.shrink();
                          return NavigationCallOverlay(callInfo: callInfo);
                        },
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
              const Icon(Icons.gps_off_rounded, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'GPS SIGNAL LOST',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.redAccent,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· Speed: --',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: Colors.white54,
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
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: isRerouting ? _C.amber : _C.primary.withValues(alpha: 0.5),
          width: 2,
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
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isRerouting ? _C.amber.withValues(alpha: 0.15) : _C.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: isRerouting
                ? const Icon(Icons.sync_rounded, color: _C.amber, size: 30)
                : Icon(
                    ManeuverMapper.toIcon(maneuver),
                    color: _C.primary,
                    size: 32,
                  ),
          ),
          const SizedBox(width: 14),

          // Maneuver Distance & Street Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isRerouting ? 'REROUTING...' : state.maneuverDistanceFormatted,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isRerouting ? _C.amber : _C.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isRerouting)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _C.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _C.primary.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ManeuverMapper.toArrowSymbol(maneuver),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: _C.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ManeuverMapper.toRiderActionText(maneuver),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _C.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isRerouting ? 'Recalculating best motorcycle route' : state.maneuverText,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _C.textSec,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Exit button
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            onPressed: _confirmExitNavigation,
          ),
        ],
      ),
    );
  }

  /// Bottom HUD panel: Speedometer, Total Distance, ETA, BLE Status, and Exit
  Widget _buildBottomHud(NavigationState state, bool isBleConnected) {
    return Container(
      decoration: const BoxDecoration(
        color: _C.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _C.cardBorder, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Speed, Remaining Distance, ETA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 1. Live Speedometer — uses speedDisplay which returns '--' on GPS loss
                _buildTelemetryColumn(
                  label: 'SPEED',
                  value: state.speedDisplay,
                  unit: state.gpsAvailable ? 'KM/H' : '',
                  valueColor: state.gpsAvailable ? _C.primary : _C.textSec,
                ),
                Container(width: 1, height: 40, color: _C.cardBorder),

                // 2. Remaining Distance
                _buildTelemetryColumn(
                  label: 'REMAINING',
                  value: state.remainingDistanceFormatted,
                  unit: '',
                  valueColor: _C.onSurface,
                ),
                Container(width: 1, height: 40, color: _C.cardBorder),

                // 3. ETA
                _buildTelemetryColumn(
                  label: 'ARRIVAL',
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBleConnected ? _C.blueAccent.withValues(alpha: 0.12) : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isBleConnected ? _C.blueAccent.withValues(alpha: 0.3) : Colors.white24,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        size: 14,
                        color: isBleConnected ? _C.blueAccent : Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isBleConnected ? 'TFT HUD SYNCED' : 'HUD DISCONNECTED',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isBleConnected ? _C.blueAccent : Colors.white54,
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
                    backgroundColor: _C.red.withValues(alpha: 0.15),
                    foregroundColor: _C.red,
                    elevation: 0,
                    side: const BorderSide(color: _C.red, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(
                    'END RIDE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
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
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _C.textSec,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _C.textSec,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _confirmExitNavigation() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'End Navigation?',
          style: GoogleFonts.jetBrainsMono(color: _C.onSurface, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to stop active motorcycle navigation?',
          style: GoogleFonts.inter(color: _C.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CONTINUE RIDE', style: GoogleFonts.jetBrainsMono(color: _C.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: _C.red, foregroundColor: Colors.white),
            child: Text('STOP', style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      await NavigationService.instance.stopNavigation();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _showSimulatorConfigSheet() {
    final hostController = TextEditingController(
      text: SimulatorLocationService.instance.host,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: _C.cardBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: _C.cardBorder, width: 1.5)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _C.cardBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.sports_esports_rounded,
                            color: Colors.deepPurpleAccent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GPS Ride Simulator',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _C.onSurface,
                                ),
                              ),
                              Text(
                                'Indoor testing & physical TFT synchronization',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: _C.textSec,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Live connection pill
                        ValueListenableBuilder<bool>(
                          valueListenable: SimulatorLocationService.instance.isConnectedNotifier,
                          builder: (_, connected, __) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: connected
                                  ? _C.primary.withValues(alpha: 0.15)
                                  : _C.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: connected
                                    ? _C.primary.withValues(alpha: 0.5)
                                    : _C.red.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: connected ? _C.primary : _C.red,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  connected ? 'CONNECTED' : 'OFFLINE',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: connected ? _C.primary : _C.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Active Mode Switcher
                    Text(
                      'ACTIVE LOCATION SOURCE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _C.textSec,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<LocationSource>(
                      valueListenable: LocationService.instance.locationSourceNotifier,
                      builder: (_, source, __) {
                        final isSim = source == LocationSource.simulator;
                        return Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  LocationService.instance.setLocationSource(LocationSource.realGps);
                                  setSheetState(() {});
                                },
                                icon: Icon(
                                  Icons.satellite_alt_rounded,
                                  size: 16,
                                  color: !isSim ? _C.primary : _C.textSec,
                                ),
                                label: Text(
                                  'Real Phone GPS',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: !isSim ? FontWeight.w700 : FontWeight.normal,
                                    color: !isSim ? _C.onSurface : _C.textSec,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: !isSim ? _C.primary.withValues(alpha: 0.1) : Colors.transparent,
                                  side: BorderSide(
                                    color: !isSim ? _C.primary : _C.cardBorder,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  LocationService.instance.setLocationSource(LocationSource.simulator);
                                  setSheetState(() {});
                                },
                                icon: Icon(
                                  Icons.sports_esports_rounded,
                                  size: 16,
                                  color: isSim ? Colors.deepPurpleAccent : _C.textSec,
                                ),
                                label: Text(
                                  'Web Simulator',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: isSim ? FontWeight.w700 : FontWeight.normal,
                                    color: isSim ? _C.onSurface : _C.textSec,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isSim ? Colors.deepPurpleAccent.withValues(alpha: 0.15) : Colors.transparent,
                                  side: BorderSide(
                                    color: isSim ? Colors.deepPurpleAccent : _C.cardBorder,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Host Address Input
                    Text(
                      'SIMULATOR SERVER IP:PORT',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _C.textSec,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hostController,
                      style: GoogleFonts.jetBrainsMono(
                        color: _C.onSurface,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _C.bg,
                        prefixIcon: const Icon(
                          Icons.dns_rounded,
                          color: _C.textSec,
                          size: 18,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            color: _C.primary,
                          ),
                          onPressed: () async {
                            final text = hostController.text.trim();
                            if (text.isNotEmpty) {
                              await SimulatorLocationService.instance.setHost(text);
                              await SimulatorLocationService.instance.connect();
                              setSheetState(() {});
                            }
                          },
                        ),
                        hintText: '127.0.0.1:8080 or 192.168.x.x:8080',
                        hintStyle: GoogleFonts.jetBrainsMono(
                          color: _C.textSec.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _C.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _C.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Presets
                    Row(
                      children: [
                        Text(
                          'Presets: ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: _C.textSec,
                          ),
                        ),
                        ActionChip(
                          label: Text(
                            '127.0.0.1:8080',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: _C.onSurface,
                            ),
                          ),
                          backgroundColor: _C.bg,
                          side: const BorderSide(color: _C.cardBorder),
                          onPressed: () async {
                            hostController.text = '127.0.0.1:8080';
                            await SimulatorLocationService.instance.setHost('127.0.0.1:8080');
                            await SimulatorLocationService.instance.connect();
                            setSheetState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          label: Text(
                            '10.0.2.2:8080',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: _C.onSurface,
                            ),
                          ),
                          backgroundColor: _C.bg,
                          side: const BorderSide(color: _C.cardBorder),
                          onPressed: () async {
                            hostController.text = '10.0.2.2:8080';
                            await SimulatorLocationService.instance.setHost('10.0.2.2:8080');
                            await SimulatorLocationService.instance.connect();
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Telemetry Status Row
                    ValueListenableBuilder<SimulatedLocationPacket?>(
                      valueListenable: SimulatorLocationService.instance.latestPacketNotifier,
                      builder: (_, packet, __) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _C.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _C.cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LATENCY',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: _C.textSec,
                                    ),
                                  ),
                                  ValueListenableBuilder<int>(
                                    valueListenable: SimulatorLocationService.instance.latencyMsNotifier,
                                    builder: (_, lat, __) => Text(
                                      '$lat ms',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: lat < 50
                                            ? _C.primary
                                            : (lat < 150 ? _C.amber : _C.red),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SPEED',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: _C.textSec,
                                    ),
                                  ),
                                  Text(
                                    packet != null ? '${packet.speedKmh.toStringAsFixed(1)} km/h' : '--',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _C.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PROGRESS',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: _C.textSec,
                                    ),
                                  ),
                                  Text(
                                    packet != null ? '${(packet.routeProgress * 100).toStringAsFixed(1)}%' : '--',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _C.blueAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
