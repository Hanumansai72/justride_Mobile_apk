import '../../../core/models/ride_state.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../../core/constants/google_maps_config.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/navigation_state.dart';
import '../../../core/services/navigation_service.dart';
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
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(center.dx, 8.0)
      ..lineTo(center.dx - 14.0, 36.0)
      ..lineTo(center.dx + 14.0, 36.0)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);

    // 2. Outer pulse / glow halo
    final glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 48.0, glowPaint);

    // 3. Dark Disc Body
    final discPaint = Paint()
      ..color = AppColors.backgroundInset
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 38.0, discPaint);

    // 4. Emerald Accent Border
    final borderPaint = Paint()
      ..color = AppColors.primary
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
          color: AppColors.textPrimary,
        ),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes);
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
        if (!didPop) _confirmExitNavigation();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        body: ValueListenableBuilder<NavigationState>(
          valueListenable: NavigationService.instance.navigationStateNotifier,
          builder: (context, state, _) {
            if (state.rideState == RideState.arrived) {
              return SafeArea(
                  child: Center(
                      child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flag_rounded,
                      color: AppColors.primary, size: 64),
                  const SizedBox(height: 24),
                  const Text("You've Reached Your Destination",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28, color: AppColors.textPrimary)),
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
            final polylines = <Polyline>{};

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

            // Active route uses the customer site's navigation accent.
            if (route != null && route.polylinePoints.isNotEmpty) {
              polylines.add(
                Polyline(
                  polylineId: const PolylineId('active_route'),
                  points: route.polylinePoints,
                  color: AppColors.primary,
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
                if (!GoogleMapsConfig.hasApiKey ||
                    (kIsWeb && !GoogleMapsConfig.webMapsLoaded))
                  const Center(
                      child: Text(
                          'Map unavailable. Check your internet connection and try again.'))
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
                      polylines: polylines,
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
                              'Loading Map & Route...',
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
                              'Initializing GPS lock and route telemetry',
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
                  bottom: 240,
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
                          borderRadius: BorderRadius.circular(12),
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
                        foregroundColor: AppColors.textPrimary,
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Incoming / Active Call HUD Overlay at the bottom
                      ValueListenableBuilder<IncomingCallInfo>(
                        valueListenable:
                            TelephonyService.instance.callInfoNotifier,
                        builder: (context, callInfo, _) {
                          if (!callInfo.hasActiveCall) {
                            return const SizedBox.shrink();
                          }
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
              const Icon(Icons.gps_off_rounded,
                  color: AppColors.errorText, size: 20),
              const SizedBox(width: 8),
              Text(
                'GPS SIGNAL LOST',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.errorText,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· Speed: --',
                style: GoogleFonts.jetBrainsMono(
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
                      isRerouting
                          ? 'REROUTING...'
                          : state.maneuverDistanceFormatted,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
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
                  isRerouting
                      ? 'Recalculating best motorcycle route'
                      : state.maneuverText,
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
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
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textSecondary, size: 22),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBleConnected
                        ? _C.blueAccent.withValues(alpha: 0.12)
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
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
                        isBleConnected ? 'TFT HUD SYNCED' : 'HUD DISCONNECTED',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
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
          style: GoogleFonts.jetBrainsMono(
              color: _C.onSurface, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to stop active motorcycle navigation?',
          style: TextStyle(fontFamily: 'Stack Sans Text', color: _C.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CONTINUE RIDE',
                style: GoogleFonts.jetBrainsMono(color: _C.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.textPrimary),
            child: Text('STOP',
                style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      await NavigationService.instance.stopNavigation();
      if (mounted) Navigator.of(context).pop();
    }
  }
}
