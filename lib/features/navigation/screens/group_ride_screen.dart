import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/google_maps_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/group_ride_service.dart';
import '../../../core/services/ble_navigation_service.dart';
import '../../../core/services/location_service.dart';
import '../../profile/screens/subscription_screen.dart';

class GroupRideScreen extends StatefulWidget {
  const GroupRideScreen({super.key});

  @override
  State<GroupRideScreen> createState() => _GroupRideScreenState();
}

class _GroupRideScreenState extends State<GroupRideScreen>
    with WidgetsBindingObserver {
  final _invite = TextEditingController();
  GroupRide? _ride;
  GoogleMapController? _map;
  Timer? _timer;
  Future<void>? _poll;
  DateTime? _retryAt;
  String? _error;
  bool _busy = true, _locked = false, _sharing = false, _changingShare = false;
  bool _foreground = true;
  final Map<String, LatLng> _lastPositions = {};
  final Map<String, DateTime> _stationarySince = {};
  final Map<String, DateTime> _alertSentAt = {};
  final Map<String, DateTime> _alertAttemptAt = {};
  final Map<String, String> _pendingSafetyAlerts = {};
  final Set<String> _stoppedReported = {},
      _offlineReported = {},
      _distanceActive = {};
  final Map<String, String> _riderStatus = {};
  List<String> _safetyWarnings = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _refresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(_stopSharing());
    }
  }

  @override
  void dispose() {
    _foreground = false;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopSharing(updateUi: false));
    _invite.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await GroupRideService.current();
    if (!mounted) return;
    _accept(result);
    setState(() => _busy = false);
  }

  void _accept(ApiResponse<GroupRide> result) {
    setState(() {
      _error = result.success ? null : result.message;
      if (result.retryAfterSeconds case final seconds?) {
        _retryAt = DateTime.now().add(Duration(seconds: seconds));
      }
      _locked = result.statusCode == 403;
      if (result.success || _locked || result.statusCode == 404) {
        if (_ride?.id != result.data?.id) {
          _sharing = false;
          _map = null;
          _lastPositions.clear();
          _stationarySince.clear();
          _alertSentAt.clear();
          _alertAttemptAt.clear();
          _pendingSafetyAlerts.clear();
          _stoppedReported.clear();
          _offlineReported.clear();
          _distanceActive.clear();
          _riderStatus.clear();
          _safetyWarnings = const [];
        }
        _ride = result.data;
      }
    });
    if (result.success && result.data != null && _foreground) {
      _analyzeRiderPositions(result.data!);
    }
  }

  void _analyzeRiderPositions(GroupRide ride) {
    final now = DateTime.now();
    final alerts = <({String key, String message, String? riderId})>[];
    final points = <({String id, String name, LatLng point})>[];
    _riderStatus.clear();

    for (final rider in ride.members.where((member) => !member.isYou)) {
      final point = rider.location;
      if (point == null) {
        final updated = rider.locationUpdatedAt;
        if (updated != null &&
            now.difference(updated) > const Duration(seconds: 45)) {
          _riderStatus[rider.id] = 'No live location update';
          if (_offlineReported.add(rider.id)) {
            alerts.add((
              key: 'offline:${rider.id}',
              message: '${rider.name} has no live location',
              riderId: rider.id
            ));
          }
        }
        _lastPositions.remove(rider.id);
        _stationarySince.remove(rider.id);
        _stoppedReported.remove(rider.id);
        continue;
      }
      _offlineReported.remove(rider.id);
      points.add((id: rider.id, name: rider.name, point: point));
      final previous = _lastPositions[rider.id];
      if (previous == null ||
          Geolocator.distanceBetween(previous.latitude, previous.longitude,
                  point.latitude, point.longitude) >=
              25) {
        _stationarySince[rider.id] = now;
        _stoppedReported.remove(rider.id);
      } else {
        _stationarySince.putIfAbsent(rider.id, () => now);
      }
      _lastPositions[rider.id] = point;
      final since = _stationarySince[rider.id];
      if (since != null &&
          now.difference(since) >= const Duration(minutes: 2)) {
        _riderStatus[rider.id] = 'No movement for 2+ min';
        if (_stoppedReported.add(rider.id)) {
          alerts.add((
            key: 'stopped:${rider.id}',
            message: '${rider.name} has not moved for 2 min',
            riderId: rider.id
          ));
        }
      }
    }

    final ownFix = LocationService.instance.currentPosition;
    if (LocationService.navigationFixFresh(ownFix, now)) {
      final self = ride.members.where((member) => member.isYou).firstOrNull;
      if (self != null) {
        final current = LatLng(ownFix!.latitude, ownFix.longitude);
        final previous = _lastPositions[self.id];
        if (previous == null ||
            Geolocator.distanceBetween(previous.latitude, previous.longitude,
                    current.latitude, current.longitude) >=
                25) {
          _stationarySince[self.id] = now;
          _stoppedReported.remove(self.id);
        } else {
          _stationarySince.putIfAbsent(self.id, () => now);
        }
        _lastPositions[self.id] = current;
        final since = _stationarySince[self.id];
        if (since != null &&
            now.difference(since) >= const Duration(minutes: 2)) {
          _riderStatus[self.id] = 'No movement for 2+ min';
          if (_stoppedReported.add(self.id)) {
            alerts.add((
              key: 'stopped:${self.id}',
              message: 'You have not moved for 2 min',
              riderId: self.id
            ));
          }
        }
      }
      points.add((
        id: 'you',
        name: 'You',
        point: LatLng(ownFix!.latitude, ownFix.longitude)
      ));
    }
    var furthestGap = 5000.0;
    String? farMessage, farKey;
    final currentDistanceAlerts = <String>{};
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final gap = Geolocator.distanceBetween(
            points[i].point.latitude,
            points[i].point.longitude,
            points[j].point.latitude,
            points[j].point.longitude);
        if (gap > 5000) {
          final ids = [points[i].id, points[j].id]..sort();
          final key = 'far:${ids.join(':')}';
          currentDistanceAlerts.add(key);
          if (gap > furthestGap) {
            furthestGap = gap;
            farKey = key;
            farMessage =
                '${points[i].name} is ${(gap / 1000).toStringAsFixed(1)} km from ${points[j].name}';
          }
          if (points[i].id != 'you')
            _riderStatus[points[i].id] = 'More than 5 km from group';
          if (points[j].id != 'you')
            _riderStatus[points[j].id] = 'More than 5 km from group';
        }
      }
    }
    if (farKey != null && !_distanceActive.contains(farKey)) {
      alerts.add((key: farKey, message: farMessage!, riderId: null));
    }
    _distanceActive
      ..removeWhere((key) => !currentDistanceAlerts.contains(key))
      ..addAll(currentDistanceAlerts);

    final visible = _riderStatus.entries.map((entry) {
      final rider =
          ride.members.where((member) => member.id == entry.key).firstOrNull;
      return '${rider?.name ?? 'You'}: ${entry.value}';
    }).toList(growable: false);
    if (mounted) setState(() => _safetyWarnings = visible);
    if (alerts.isNotEmpty) {
      for (final alert in alerts) {
        _pendingSafetyAlerts.putIfAbsent(alert.key, () => alert.message);
      }
    }
    if (_pendingSafetyAlerts.isNotEmpty) {
      final next = _pendingSafetyAlerts.entries.first;
      unawaited(_sendGroupSafetyAlert(next.key, next.value));
    }
  }

  Future<void> _sendGroupSafetyAlert(String key, String message) async {
    final now = DateTime.now();
    final previous = _alertSentAt[key];
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 10)) return;
    final lastAttempt = _alertAttemptAt[key];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 15)) return;
    _alertAttemptAt[key] = now;
    final sent = await BleNavigationService.instance
        .sendRideSafetyAlert('Group Ride Warning', message);
    if (sent) {
      _alertSentAt[key] = DateTime.now();
      _pendingSafetyAlerts.remove(key);
    }
  }

  void _refresh() {
    final ride = _ride;
    if (!_foreground ||
        _busy ||
        _poll != null ||
        _changingShare ||
        ride == null ||
        (_retryAt?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    _poll = _refreshRide(ride).whenComplete(() => _poll = null);
  }

  Future<void> _refreshRide(GroupRide ride) async {
    final location = LocationService.instance;
    final token = ApiClient.instance.token;
    var fix = location.currentPosition;
    if (_sharing && !LocationService.navigationFixFresh(fix, DateTime.now())) {
      try {
        fix = await location.getCurrentPosition();
      } catch (_) {
        fix = null;
      }
    }
    if (!mounted ||
        !_foreground ||
        _ride?.id != ride.id ||
        token != ApiClient.instance.token) {
      return;
    }
    final result = _sharing &&
            fix != null &&
            LocationService.navigationFixFresh(fix, DateTime.now())
        ? await GroupRideService.updateLocation(
            ride.id, LatLng(fix.latitude, fix.longitude))
        : await GroupRideService.current();
    if (mounted &&
        _foreground &&
        _ride?.id == ride.id &&
        token == ApiClient.instance.token) {
      _accept(result);
    }
  }

  Future<void> _startSharing() async {
    setState(() => _changingShare = true);
    final allowed = await LocationService.instance.ensurePermissions();
    if (!mounted) return;
    setState(() {
      _changingShare = false;
      _sharing = allowed && _foreground && _ride != null;
      if (!allowed) _error = 'Enable location access to share your position.';
    });
    _refresh();
  }

  Future<void> _stopSharing({bool updateUi = true}) async {
    if (!_sharing) return;
    final ride = _ride;
    final token = ApiClient.instance.token;
    _sharing = false;
    _changingShare = true;
    if (updateUi && mounted) setState(() {});
    await _poll;
    if (ride != null && token == ApiClient.instance.token) {
      final result = await GroupRideService.updateLocation(ride.id, null);
      if (updateUi && mounted && _foreground && _ride?.id == ride.id) {
        _accept(result);
      }
    }
    _changingShare = false;
    if (updateUi && mounted) setState(() {});
  }

  Future<void> _enter({required bool join}) async {
    final code = _invite.text.trim();
    if (join && !RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 12-character invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = join
        ? await GroupRideService.join(code)
        : await GroupRideService.create();
    if (!mounted) return;
    if (result.statusCode == 409 || result.isTransientFailure) {
      final current = await GroupRideService.current();
      if (!mounted) return;
      _accept(current.data == null ? result : current);
    } else {
      _accept(result);
    }
    setState(() => _busy = false);
  }

  Future<void> _leave(GroupRide ride) async {
    if (ride.isHost) {
      final end = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('End group ride?'),
          content: const Text('This closes the group for all riders.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('End group')),
          ],
        ),
      );
      if (end != true || !mounted || _ride?.id != ride.id) return;
    }
    setState(() => _busy = true);
    await _stopSharing();
    final result = await GroupRideService.leave(ride.id);
    if (!mounted) return;
    if (result.success) {
      _accept(ApiResponse<GroupRide>.success());
      _invite.clear();
    } else {
      setState(() => _error = result.message);
    }
    setState(() => _busy = false);
  }

  Future<void> _openSubscription() async {
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()));
    if (!mounted) return;
    setState(() => _busy = true);
    await _load();
  }

  Widget _activeRide(GroupRide ride) {
    final live = <GroupRider>[
      if (_error == null)
        for (final member in ride.members)
          if (member.location != null && (!member.isYou || _sharing)) member,
    ];
    final expires = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(ride.expiresAt.toLocal()));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          title: Text(ride.code, style: Theme.of(context).textTheme.titleLarge),
          subtitle: Text('Invite code · Expires at $expires'),
          trailing: IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy invite code',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: ride.code));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite code copied')));
              }
            },
          ),
        ),
        SwitchListTile(
          title: const Text('Share my location'),
          subtitle:
              const Text('Only while this screen is open in the foreground'),
          value: _sharing,
          onChanged: _busy || _changingShare
              ? null
              : (share) => share ? _startSharing() : _stopSharing(),
        ),
        if (_error != null) Text(_error!),
        for (final warning in _safetyWarnings)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(warning),
            ),
          ),
        if (live.isNotEmpty && GoogleMapsConfig.hasApiKey)
          SizedBox(
            height: 270,
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: live.first.location!, zoom: 14),
              onMapCreated: (controller) => _map = controller,
              mapToolbarEnabled: false,
              markers: {
                for (final rider in live)
                  Marker(
                    markerId: MarkerId(rider.id),
                    position: rider.location!,
                    infoWindow: InfoWindow(title: rider.name),
                  ),
              },
            ),
          ),
        const SizedBox(height: 12),
        Text('Riders (${ride.members.length})',
            style: Theme.of(context).textTheme.titleMedium),
        for (final rider in ride.members)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(rider.isYou ? '${rider.name} (you)' : rider.name),
            subtitle: Text(_riderStatus[rider.id] ??
                (live.contains(rider)
                    ? 'Live location'
                    : 'Location unavailable')),
            onTap: live.contains(rider)
                ? () =>
                    _map?.animateCamera(CameraUpdate.newLatLng(rider.location!))
                : null,
          ),
        OutlinedButton(
          onPressed: _busy || _changingShare ? null : () => _leave(ride),
          child: Text(ride.isHost ? 'End group ride' : 'Leave group ride'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    return Scaffold(
      appBar: AppBar(title: const Text('Group Ride')),
      body: ride != null
          ? _activeRide(ride)
          : _busy
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_locked) ...[
                      Text('Included with Premium',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      const Text(
                          'Premium riders can create and join private groups.'),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _openSubscription,
                        child: const Text('View subscription'),
                      ),
                    ] else ...[
                      const Text(
                          'Share an invite code with your riding group. Riders choose whether to share their location.'),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => _enter(join: false),
                        child: const Text('Create group ride'),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _invite,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.go,
                        decoration:
                            const InputDecoration(labelText: 'Invite code'),
                        onSubmitted: (_) => _enter(join: true),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _enter(join: true),
                        child: const Text('Join group ride'),
                      ),
                      if (_error != null) Text(_error!),
                    ],
                  ],
                ),
    );
  }
}
