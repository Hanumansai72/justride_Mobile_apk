import '../../../shared/widgets/contextual_help_button.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/require_device_connection.dart';
import '../widgets/voice_assistant_sheet.dart';

/// Dedicated "Go" Page allowing rider to set Start and Endpoint (Destination)
/// and seamlessly launch motorcycle navigation with rich local suggestions.
class GoScreen extends StatefulWidget {
  final Destination? initialDestination;

  const GoScreen({super.key, this.initialDestination});

  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  final FocusNode _startFocusNode = FocusNode();
  final FocusNode _destFocusNode = FocusNode();

  Destination? _startLocation;
  Destination? _destLocation;

  List<Destination> _suggestions = [];
  bool _isSearching = false;
  bool _isStartFocused = false;
  Timer? _debounceTimer;

  bool _isLoadingRoute = false;
  bool _isStartingRide = false;
  NavigationRoute? _previewRoute;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;

  // Quick frequent local destinations in India / Hyderabad
  static const List<String> _quickPlaces = [
    'Uppal Bus Stop',
    'Uppal Metro Station',
    'Secunderabad Station',
    'HITEC City Metro',
    'Gachibowli DLF',
    'Charminar',
  ];

  @override
  void initState() {
    super.initState();
    _startController.text = 'Current Location';

    if (widget.initialDestination != null) {
      _destLocation = widget.initialDestination;
      _destController.text = widget.initialDestination!.displayTitle;
      _fetchRoutePreview();
    }

    _startFocusNode.addListener(() {
      setState(() {
        _isStartFocused = _startFocusNode.hasFocus;
        if (_startFocusNode.hasFocus &&
            _startController.text == 'Current Location') {
          _startController.clear();
        } else if (!_startFocusNode.hasFocus &&
            _startController.text.trim().isEmpty &&
            _startLocation == null) {
          _startController.text = 'Current Location';
        }
      });
    });

    _destFocusNode.addListener(() {
      setState(() {
        if (_destFocusNode.hasFocus) {
          _isStartFocused = false;
        }
      });
    });

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _startController.dispose();
    _destController.dispose();
    _startFocusNode.dispose();
    _destFocusNode.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query, {required bool isStart}) {
    _debounceTimer?.cancel();
    final clean = query.trim();
    if (clean.length < 2) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await GoogleMapsService.instance.searchPlaces(clean);
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _isSearching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSearching = false);
      }
    });
  }

  void _selectSuggestion(Destination dest, {required bool isStart}) {
    setState(() {
      if (isStart) {
        _startLocation = dest;
        _startController.text = dest.displayTitle;
        _startFocusNode.unfocus();
      } else {
        _destLocation = dest;
        _destController.text = dest.displayTitle;
        _destFocusNode.unfocus();
      }
      _suggestions = [];
    });
    _fetchRoutePreview();
  }

  void _useCurrentLocationForStart() {
    setState(() {
      _startLocation = null;
      _startController.text = 'Current Location';
      _startFocusNode.unfocus();
      _suggestions = [];
    });
    _fetchRoutePreview();
  }

  void _swapEndpoints() {
    setState(() {
      final tempDest = _destLocation;
      final tempText = _destController.text;

      _destLocation = _startLocation;
      _destController.text = _startController.text == 'Current Location'
          ? ''
          : _startController.text;

      _startLocation = tempDest;
      _startController.text = tempText.isEmpty ? 'Current Location' : tempText;

      _suggestions = [];
    });
    _fetchRoutePreview();
  }

  Future<void> _fetchRoutePreview() async {
    if (_destLocation == null ||
        _destLocation!.latitude == 0.0 ||
        _destLocation!.longitude == 0.0) {
      setState(() => _previewRoute = null);
      return;
    }

    setState(() => _isLoadingRoute = true);

    try {
      final currentPos = LocationService.instance.currentPosition;
      final startLatLng = _startLocation != null
          ? LatLng(_startLocation!.latitude, _startLocation!.longitude)
          : LatLng(
              currentPos?.latitude ?? 17.3850,
              currentPos?.longitude ?? 78.4867,
            );
      final destLatLng =
          LatLng(_destLocation!.latitude, _destLocation!.longitude);

      final route = await GoogleMapsService.instance.calculateRoute(
        origin: startLatLng,
        destination: destLatLng,
      );

      if (mounted) {
        setState(() {
          _previewRoute = route;
          _isLoadingRoute = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _handleStartRide() async {
    if (_isStartingRide) return;
    if (!await requireDeviceConnection(context) || !mounted) return;
    setState(() => _isStartingRide = true);

    try {
      final destText = _destController.text.trim();

      // If no destination specified, user can navigate directly to inbuilt app maps
      if (destText.isEmpty && _destLocation == null) {
        Navigator.of(context).pushNamed('/active-navigation');
        return;
      }

      Destination? target = _destLocation;
      if (target == null || target.latitude == 0.0) {
        // Resolve destination query
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Locating destination coordinates...'),
            duration: Duration(seconds: 1),
          ),
        );

        target = await GoogleMapsService.instance.resolveDestination(
          Destination(
            name: destText,
            address: destText,
            latitude: 0.0,
            longitude: 0.0,
            rawQuery: destText,
          ),
        );
      }

      if (!mounted) return;

      if (target == null ||
          (target.latitude == 0.0 && target.longitude == 0.0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Could not find location. Please pick from suggestions.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // Start navigation
      final ok = await NavigationService.instance.startNavigation(
        target,
        startLocation: _startLocation,
      );

      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pushNamed('/active-navigation');
      } else {
        // Still allow viewing map if GPS lock takes a few seconds
        Navigator.of(context).pushNamed('/active-navigation');
      }
    } finally {
      if (mounted) setState(() => _isStartingRide = false);
    }
  }

  IconData _iconForPlace(Destination d) {
    final title = (d.name ?? '').toLowerCase();
    final addr = (d.address ?? '').toLowerCase();
    if (title.contains('bus') || addr.contains('bus')) {
      return Icons.directions_bus_rounded;
    }
    if (title.contains('metro') ||
        title.contains('station') ||
        title.contains('railway')) {
      return Icons.subway_rounded;
    }
    if (title.contains('airport') || addr.contains('airport')) {
      return Icons.local_airport_rounded;
    }
    return Icons.location_on_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Go',
          style: TextStyle(
            fontFamily: 'Stack Sans Text',
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          const ContextualHelpButton(category: 'Navigation'),
          IconButton(
            tooltip: 'Voice Assistant',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.primary, size: 20),
            ),
            onPressed: () => VoiceAssistantSheet.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Inputs Container (Start & Destination with swap) ──────────
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Left indicators (Origin dot -> dotted line -> Destination pin)
                  Column(
                    children: [
                      const Icon(Icons.radio_button_checked_rounded,
                          color: AppColors.primary, size: 18),
                      Container(
                        width: 2,
                        height: 36,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: AppColors.border,
                      ),
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.primary, size: 20),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Middle input fields
                  Expanded(
                    child: Column(
                      children: [
                        // Start point input
                        TextField(
                          controller: _startController,
                          focusNode: _startFocusNode,
                          style: TextStyle(
                              fontFamily: 'Stack Sans Text',
                              color: AppColors.textPrimary,
                              fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Choose starting point...',
                            hintStyle: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                color: AppColors.textMuted,
                                fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            suffixIcon: _startController.text.isNotEmpty &&
                                    _startController.text != 'Current Location'
                                ? GestureDetector(
                                    onTap: _useCurrentLocationForStart,
                                    child: const Icon(Icons.close_rounded,
                                        size: 16, color: AppColors.textMuted),
                                  )
                                : null,
                          ),
                          onChanged: (val) =>
                              _onQueryChanged(val, isStart: true),
                        ),

                        const Divider(
                            color: AppColors.border, height: 16, thickness: 1),

                        // Destination point input
                        TextField(
                          controller: _destController,
                          focusNode: _destFocusNode,
                          autofocus: widget.initialDestination == null,
                          style: TextStyle(
                            fontFamily: 'Stack Sans Text',
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Enter destination (e.g. Uppal Bus Stop)...',
                            hintStyle: TextStyle(
                                fontFamily: 'Stack Sans Text',
                                color: AppColors.textMuted,
                                fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            suffixIcon: _destController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _destController.clear();
                                      setState(() {
                                        _destLocation = null;
                                        _suggestions = [];
                                        _previewRoute = null;
                                      });
                                    },
                                    child: const Icon(Icons.close_rounded,
                                        size: 16, color: AppColors.textMuted),
                                  )
                                : null,
                          ),
                          onChanged: (val) =>
                              _onQueryChanged(val, isStart: false),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Swap button
                  IconButton(
                    tooltip: 'Swap start & destination',
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.swap_vert_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    onPressed: _swapEndpoints,
                  ),
                ],
              ),
            ),

            // ── Suggestions List OR Preview Content ────────────────────────
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2.5),
                    )
                  : _suggestions.isNotEmpty
                      ? _buildSuggestionsList()
                      : _buildDefaultContent(),
            ),

            // ── Bottom Start Ride Button Container ─────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.backgroundInset,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1.2),
                ),
              ),
              child: AnimatedBuilder(
                animation: _pulseScale,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _destLocation != null ? _pulseScale.value : 1.0,
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _handleStartRide,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isStartingRide
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: AppColors.onPrimary,
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'PREPARING MAP...',
                                    style: TextStyle(
                                      fontFamily: 'Stack Sans Text',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.navigation_rounded,
                                      size: 22, color: AppColors.onPrimary),
                                  const SizedBox(width: 10),
                                  Text(
                                    'START RIDE',
                                    style: TextStyle(
                                      fontFamily: 'Stack Sans Text',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.surfaceElevated, height: 1),
      itemBuilder: (context, index) {
        final item = _suggestions[index];
        final icon = _iconForPlace(item);

        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          title: Text(
            item.displayTitle,
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            item.displaySubtitle,
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: AppColors.textMuted,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _selectSuggestion(item, isStart: _isStartFocused),
        );
      },
    );
  }

  Widget _buildDefaultContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route preview card if destination is loaded
          if (_isLoadingRoute) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Calculating fastest motorcycle route...',
                    style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (_previewRoute != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.two_wheeler_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Motorcycle Route',
                        style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_previewRoute!.totalDistanceMeters / 1000).toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Approx. ${(_previewRoute!.totalDurationSeconds / 60).round()} mins • ${_previewRoute!.steps.length} turns',
                    style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Quick Frequent Places Section
          Text(
            'QUICK DESTINATIONS',
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickPlaces.map((name) {
              return ActionChip(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                avatar: const Icon(Icons.near_me_rounded,
                    color: AppColors.primary, size: 14),
                label: Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: () {
                  _destController.text = name;
                  _onQueryChanged(name, isStart: false);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Tip banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundInset,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceElevated),
            ),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tip: You can also tap the mic icon in the header to speak any destination.',
                    style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
