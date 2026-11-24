import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/offline_touring_service.dart';
import '../../../core/services/ride_planning_store.dart';
import '../../../shared/widgets/require_device_connection.dart';
import '../widgets/destination_confirm_sheet.dart';
import '../widgets/route_preview_map.dart';
import 'group_ride_screen.dart';

class RideToolsScreen extends StatefulWidget {
  const RideToolsScreen({super.key});

  @override
  State<RideToolsScreen> createState() => _RideToolsScreenState();
}

class _RideToolsScreenState extends State<RideToolsScreen> {
  List<SavedCommute> _commutes = [];
  List<OfflineTouringPack> _packs = [];
  String? _owner, _error;
  bool _loading = true, _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final owner = await RidePlanningStore.owner();
      final commutes = await RidePlanningStore.commutes(owner);
      final packs = kIsWeb
          ? <OfflineTouringPack>[]
          : await OfflineTouringService.list(owner);
      if (!mounted || owner != await RidePlanningStore.owner() || !mounted)
        return;
      setState(() {
        _owner = owner;
        _commutes = commutes;
        _packs = packs;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load saved ride tools.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCommute(SavedCommute commute) async {
    if (_owner != await RidePlanningStore.owner() || !mounted) return;
    await DestinationConfirmSheet.show(context, commute.destination,
        startLocation: commute.start, commute: true);
    if (mounted) await _load();
  }

  Future<void> _removeCommute(SavedCommute commute) async {
    final owner = _owner;
    if (owner == null) return;
    final next = _commutes.where((item) => item != commute).toList();
    if (await RidePlanningStore.saveCommutes(owner, next) && mounted) {
      setState(() => _commutes = next);
    }
  }

  Future<void> _removePack(OfflineTouringPack pack) async {
    if (_owner == null || NavigationService.instance.hasOfflineTour) return;
    await OfflineTouringService.remove(_owner!, pack.id);
    if (mounted) await _load();
  }

  Future<void> _openPack(OfflineTouringPack pack) async {
    if (_starting || _owner != await RidePlanningStore.owner() || !mounted)
      return;
    final start = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(pack.title, style: Theme.of(context).textTheme.titleLarge),
                const Text(
                    'Follow the recorded line. Start near the original starting point. The pack does not calculate new roads.'),
                const SizedBox(height: 12),
                RoutePreviewMap(route: pack.toRoute()),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Start offline ride')),
              ]),
        ),
      ),
    );
    if (start != true ||
        !mounted ||
        _owner != await RidePlanningStore.owner() ||
        !mounted) return;
    setState(() => _starting = true);
    try {
      if (!await requireDeviceConnection(context) || !mounted) return;
      if (NavigationService.instance.isNavigating) {
        _showMessage('End the current ride before starting a touring pack.');
        return;
      }
      final position = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;
      if (!LocationService.navigationFixFresh(position, DateTime.now()) ||
          position == null) {
        _showMessage('Wait for an accurate GPS location, then try again.');
        return;
      }
      if (!pack.canStartAt(LatLng(position.latitude, position.longitude),
          resuming: false)) {
        _showMessage('Move within 50 m of the recorded start to begin.');
        return;
      }
      if (_owner != await RidePlanningStore.owner() || !mounted) return;
      final started = await NavigationService.instance
          .startNavigation(pack.destination, offlineTour: pack);
      if (!mounted) return;
      if (started) {
        Navigator.of(context).pushNamed('/active-navigation');
      } else {
        _showMessage(
            'Could not start the offline ride. Check GPS and display connection.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ride tools')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('Group Ride'),
                    subtitle: const Text('Premium · Ride with friends'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const GroupRideScreen())),
                  ),
                  const Divider(),
                  if (_error != null) Text(_error!),
                  Text('Commutes',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Text(
                      'Open a saved commute to compare bike routes using current traffic.'),
                  if (_commutes.isEmpty)
                    const ListTile(
                        title: Text('Save a commute from Route preview.')),
                  for (final commute in _commutes)
                    ListTile(
                      title: Text(commute.title),
                      subtitle: Text(commute.start?.displayTitle ??
                          'From current location'),
                      leading: const Icon(Icons.route_outlined),
                      onTap: _starting ? null : () => _openCommute(commute),
                      trailing: IconButton(
                          tooltip: 'Remove commute',
                          onPressed: () => _removeCommute(commute),
                          icon: const Icon(Icons.delete_outline)),
                    ),
                  if (!kIsWeb) ...[
                    const Divider(),
                    Text('Offline touring',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text(
                        'Recorded tracks saved on this phone. No mobile data is needed to follow the line.'),
                    if (_packs.isEmpty)
                      const ListTile(
                          title: Text(
                              'Open a local ride in Ride history and save it for offline use.')),
                    for (final pack in _packs)
                      ListTile(
                        title: Text(pack.title),
                        subtitle: Text(
                            '${(pack.distanceMeters / 1000).toStringAsFixed(1)} km · Recorded track'),
                        leading: const Icon(Icons.offline_pin_outlined),
                        onTap: _starting ? null : () => _openPack(pack),
                        trailing: IconButton(
                            tooltip: 'Remove touring pack',
                            onPressed: _starting ||
                                    NavigationService.instance.hasOfflineTour
                                ? null
                                : () => _removePack(pack),
                            icon: const Icon(Icons.delete_outline)),
                      ),
                  ],
                ],
              ),
      );
}
