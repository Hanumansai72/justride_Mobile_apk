import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../shared/widgets/require_device_connection.dart';

// ── Colour tokens matching JustRide HUD theme ──────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const blueAccent = AppColors.primary;
  static const amber = AppColors.warning;
}

/// Confirmation sheet shown when user selects or shares a destination before starting ride.
class DestinationConfirmSheet extends StatefulWidget {
  final Destination destination;
  final Destination? startLocation;

  const DestinationConfirmSheet({
    super.key,
    required this.destination,
    this.startLocation,
  });

  static BuildContext? _activeSheetContext;

  static Future<bool?> show(
    BuildContext context,
    Destination destination, {
    Destination? startLocation,
  }) {
    if (_activeSheetContext != null) {
      try {
        Navigator.of(_activeSheetContext!).pop();
      } catch (_) {}
      _activeSheetContext = null;
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        _activeSheetContext = ctx;
        return DestinationConfirmSheet(
          destination: destination,
          startLocation: startLocation,
        );
      },
    ).whenComplete(() {
      _activeSheetContext = null;
    });
  }

  @override
  State<DestinationConfirmSheet> createState() =>
      _DestinationConfirmSheetState();
}

class _DestinationConfirmSheetState extends State<DestinationConfirmSheet> {
  bool _isLoadingPreview = true;
  NavigationRoute? _previewRoute;
  Destination? _resolvedDest;
  Destination? _resolvedStart;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-reconnect BLE if currently disconnected so HUD is ready
    if (!JustRideBleService.instance.isDeviceConnected) {
      JustRideBleService.instance.reconnect();
    }
    _loadRoutePreview();
  }

  Future<void> _loadRoutePreview() async {
    setState(() {
      _isLoadingPreview = true;
      _errorMessage = null;
    });

    try {
      var dest = widget.destination;
      if (dest.latitude == 0.0 && dest.longitude == 0.0) {
        debugPrint(
            '[DestinationSheet] Resolving coordinates for "${dest.displayTitle}"...');
        final resolved =
            await GoogleMapsService.instance.resolveDestination(dest);
        if (resolved != null && resolved.latitude != 0.0) {
          dest = resolved;
          debugPrint(
              '[DestinationSheet] Successfully resolved: ${dest.latitude}, ${dest.longitude}');
        } else {
          _errorMessage =
              'Could not locate address coordinates. Tap "Retry Lookup" or check internet.';
        }
      }
      _resolvedDest = dest;

      var start = widget.startLocation;
      if (start != null && start.latitude == 0.0 && start.longitude == 0.0) {
        start = await GoogleMapsService.instance.resolveDestination(start);
        if (start == null ||
            (start.latitude == 0.0 && start.longitude == 0.0)) {
          _errorMessage = 'Could not locate the entered start address.';
        }
      }
      _resolvedStart = start;

      if (dest.latitude != 0.0 &&
          dest.longitude != 0.0 &&
          (widget.startLocation == null || start != null)) {
        final currentPos = await LocationService.instance.getCurrentPosition();
        final effectiveOrigin =
            (start != null && start.latitude != 0.0 && start.longitude != 0.0)
                ? LatLng(start.latitude, start.longitude)
                : (currentPos != null
                    ? LatLng(currentPos.latitude, currentPos.longitude)
                    : null);

        if (effectiveOrigin != null) {
          final route = await GoogleMapsService.instance.calculateRoute(
            origin: effectiveOrigin,
            destination: LatLng(dest.latitude, dest.longitude),
          );
          _previewRoute = route;
        } else {
          _errorMessage =
              'Could not acquire phone GPS location. Enable Location permissions.';
        }
      }
    } catch (e) {
      _errorMessage = 'Unable to load the route preview. Please try again.';
    } finally {
      if (mounted) {
        setState(() => _isLoadingPreview = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: JustRideBleService.instance.connectionStateNotifier,
      builder: (context, connState, _) {
        final dest = _resolvedDest ?? widget.destination;
        final isBleConnected = JustRideBleService.instance.isDeviceConnected;
        final hasZeroCoords = dest.latitude == 0.0 && dest.longitude == 0.0;

        return Container(
          decoration: const BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: _C.cardBorder, width: 1.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header title row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _C.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.two_wheeler_rounded,
                              color: _C.primary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'MOTORCYCLE ROUTE',
                            style: TextStyle(
                              fontFamily: 'Stack Sans Text',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _C.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // BLE HUD status badge with tap-to-reconnect action
                    InkWell(
                      onTap: isBleConnected
                          ? null
                          : () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Reconnecting to JustRide HUD device...'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              await JustRideBleService.instance.reconnect();
                            },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBleConnected
                              ? _C.blueAccent.withValues(alpha: 0.15)
                              : AppColors.errorText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isBleConnected
                                ? _C.blueAccent.withValues(alpha: 0.4)
                                : AppColors.errorText.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBleConnected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth_searching,
                              size: 13,
                              color: isBleConnected
                                  ? _C.blueAccent
                                  : AppColors.errorText,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isBleConnected
                                  ? 'DEVICE READY'
                                  : 'NO HUD (TAP RECONNECT)',
                              style: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isBleConnected
                                    ? _C.blueAccent
                                    : AppColors.errorText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Live BLE Error / Disconnect warning banner
                ValueListenableBuilder<String?>(
                  valueListenable:
                      JustRideBleService.instance.lastBleErrorNotifier,
                  builder: (context, bleErr, _) {
                    if (bleErr == null || isBleConnected)
                      return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.errorText.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.errorText.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.errorText, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'BLE Notice: $bleErr',
                              style: TextStyle(
                                  fontFamily: 'Stack Sans Text',
                                  fontSize: 12,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Destination card
                if (_resolvedStart != null) ...[
                  _buildEndpointRow(
                    icon: Icons.trip_origin_rounded,
                    label: 'START',
                    value: _resolvedStart!.displayTitle,
                    color: _C.blueAccent,
                  ),
                ] else ...[
                  _buildEndpointRow(
                    icon: Icons.my_location_rounded,
                    label: 'START',
                    value: 'Current phone location',
                    color: _C.blueAccent,
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  decoration: BoxDecoration(
                    color: _C.cardBg,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: hasZeroCoords
                          ? AppColors.errorText.withValues(alpha: 0.5)
                          : _C.cardBorder,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: hasZeroCoords
                              ? AppColors.errorText.withValues(alpha: 0.15)
                              : _C.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasZeroCoords
                              ? Icons.location_off_rounded
                              : Icons.location_on_rounded,
                          color:
                              hasZeroCoords ? AppColors.errorText : _C.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dest.displayTitle,
                              style: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _C.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            if (hasZeroCoords) ...[
                              Text(
                                'Resolving location coordinates...',
                                style: TextStyle(
                                  fontFamily: 'Stack Sans Text',
                                  fontSize: 13,
                                  color: _C.amber,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: _isLoadingPreview
                                    ? null
                                    : _loadRoutePreview,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.refresh_rounded,
                                        size: 14, color: _C.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Tap here to retry lookup',
                                      style: TextStyle(
                                        fontFamily: 'Stack Sans Text',
                                        fontSize: 12,
                                        color: _C.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              Text(
                                dest.displaySubtitle,
                                style: TextStyle(
                                  fontFamily: 'Stack Sans Text',
                                  fontSize: 13,
                                  color: _C.textSec,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'GPS: ${dest.latitude.toStringAsFixed(5)}, ${dest.longitude.toStringAsFixed(5)}',
                                style: TextStyle(
                                  fontFamily: 'Stack Sans Text',
                                  fontSize: 11,
                                  color: _C.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Route metrics preview (Distance + ETA)
                if (_isLoadingPreview) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: _C.primary, strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Finding route & resolving coordinates...',
                            style: TextStyle(color: _C.textSec, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (_previewRoute != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.timer_outlined,
                          label: 'ESTIMATED TIME',
                          value: _formatDuration(
                              _previewRoute!.totalDurationSeconds),
                          color: _C.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.route_rounded,
                          label: 'DISTANCE',
                          value: _formatDistance(
                              _previewRoute!.totalDistanceMeters),
                          color: _C.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ] else if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _C.amber.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          fontSize: 12,
                          color: _C.amber),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Action Buttons
                ElevatedButton(
                  onPressed: _isLoadingPreview ||
                          (dest.latitude == 0.0 && dest.longitude == 0.0) ||
                          (widget.startLocation != null &&
                              _resolvedStart == null)
                      ? null
                      : () async {
                          if (!await requireDeviceConnection(context) ||
                              !context.mounted) return;
                          // Start Ride Safety Check (Master Prompt §29)
                          final hasGps =
                              LocationService.instance.isGpsAvailable;
                          final currentPos =
                              LocationService.instance.currentPosition;
                          if (!hasGps && currentPos == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Waiting for initial GPS fix... Please ensure Location is ON.'),
                                backgroundColor: AppColors.warning,
                              ),
                            );
                            return;
                          }
                          if (currentPos != null &&
                              currentPos.accuracy > 120.0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'GPS accuracy is low (±${currentPos.accuracy.round()}m). Waiting for better lock...'),
                                backgroundColor: AppColors.warning,
                              ),
                            );
                            return;
                          }

                          final target = _resolvedDest ?? widget.destination;
                          Navigator.of(context).pop(true);

                          // Start active navigation
                          final ok =
                              await NavigationService.instance.startNavigation(
                            target,
                            startLocation: _resolvedStart,
                          );
                          if (ok && context.mounted) {
                            Navigator.of(context)
                                .pushNamed('/active-navigation');
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Unable to calculate motorcycle route or obtain GPS. Check permissions.'),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primary,
                    foregroundColor: _C.onPrimary,
                    disabledBackgroundColor: _C.primary.withValues(alpha: 0.3),
                    disabledForegroundColor:
                        _C.onSurface.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.navigation_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _isLoadingPreview
                            ? 'CALCULATING ROUTE...'
                            : 'START RIDE',
                        style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      fontSize: 13,
                      color: _C.textSec,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _C.cardBg,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: _C.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _C.textSec,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _C.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 60) return '1 min';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final rem = mins % 60;
    return rem == 0 ? '$hrs hr' : '$hrs hr $rem m';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  Widget _buildEndpointRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _C.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Text('$label  ',
              style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 10,
                  color: _C.textSec,
                  fontWeight: FontWeight.w700)),
          Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      fontSize: 13,
                      color: _C.onSurface))),
        ],
      ),
    );
  }
}
