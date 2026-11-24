import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/models/destination.dart';
import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../app/theme/app_colors.dart';
import '../navigation/widgets/destination_confirm_sheet.dart';

typedef _Json = Map<String, dynamic>;
const _base = '/community/assistance';
const _types = <String, String>{
  'fuel': 'Out of fuel',
  'puncture': 'Tyre puncture',
  'breakdown': 'Motorcycle breakdown',
  'battery': 'Battery problem',
  'ev_battery': 'EV battery depleted',
  'lost': 'Lost route',
  'mechanic': 'Need a mechanic',
  'towing': 'Need towing',
  'accident': 'Accident',
  'other': 'Other assistance',
};

class CommunityRiderAssistScreen extends StatefulWidget {
  const CommunityRiderAssistScreen({super.key});

  @override
  State<CommunityRiderAssistScreen> createState() =>
      _CommunityRiderAssistScreenState();
}

class _CommunityRiderAssistScreenState
    extends State<CommunityRiderAssistScreen> {
  final _api = ApiClient.instance;
  final _description = TextEditingController();
  final _motorcycle = TextEditingController();
  List<_Json> _mine = [], _nearby = [], _helping = [];
  String _type = 'breakdown';
  bool _enabled = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _motorcycle.dispose();
    super.dispose();
  }

  Future<Position?> _position() async {
    try {
      return await LocationService.instance.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _callEmergency112() async {
    try {
      await const MethodChannel('com.justride.app/diagnostics')
          .invokeMethod<bool>('dialEmergency112');
    } on PlatformException {
      _showEmergencyFallback();
    } on MissingPluginException {
      _showEmergencyFallback();
    }
  }

  void _showEmergencyFallback() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open your phone dialer and call 112.')));
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!_enabled) {
      final presence = await _api.get<_Json>('$_base/presence');
      if (presence.success && presence.data != null) {
        _enabled = presence.data!['enabled'] == true;
      }
    }
    final mineFuture = _api.get<_Json>('$_base/mine');
    final helpingFuture = _api.get<_Json>('$_base/helping');
    final nearFuture = _enabled ? _api.get<_Json>('$_base/nearby') : null;
    final mine = await mineFuture;
    final helping = await helpingFuture;
    final near = nearFuture == null ? null : await nearFuture;
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (mine.success && mine.data != null) {
        _mine = (mine.data!['items'] as List).cast<_Json>();
      } else {
        _error = mine.message;
      }
      if (helping.success && helping.data != null) {
        _helping = (helping.data!['items'] as List).cast<_Json>();
      }
      if (near?.success == true && near?.data != null) {
        _nearby = (near!.data!['items'] as List).cast<_Json>();
      } else if (_enabled && near?.statusCode == 409) {
        _enabled = false;
        _nearby = [];
      } else if (_enabled && near != null) {
        _error ??= near.message;
      }
    });
  }

  Future<void> _setAvailable(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final position = value ? await _position() : null;
    if (value && position == null) {
      if (mounted)
        setState(() {
          _busy = false;
          _error =
              'Turn on location and allow access to become available to nearby riders.';
        });
      return;
    }
    final result = await _api.put<_Json>('$_base/presence',
        body: value
            ? {
                'enabled': true,
                'location': {
                  'lat': position!.latitude,
                  'lng': position.longitude
                }
              }
            : {'enabled': false});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success)
        _enabled = value;
      else
        _error = result.message;
    });
    if (result.success && value) await _load();
  }

  Future<void> _requestHelp() async {
    if (_type == 'accident') {
      final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Accident or immediate danger?'),
                content: const Text(
                    'Call India emergency services at 112 first. JUSTRIDE community assistance is not an emergency response service.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton.icon(
                      onPressed: _callEmergency112,
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call 112')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue'))
                ],
              ));
      if (proceed != true || !mounted) return;
    }
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Send assistance request?'),
              content: Text(
                  'Nearby opted-in riders will receive your issue type and approximate proximity. Your precise location is shared only after you accept a helper.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Review')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Send request'))
              ],
            ));
    if (confirm != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final fix = await _position();
    if (fix == null) {
      if (mounted)
        setState(() {
          _busy = false;
          _error =
              'Unable to get your current location. Try again when GPS is available.';
        });
      return;
    }
    final response = await _api.post<_Json>('$_base/requests', body: {
      'type': _type,
      'location': {'lat': fix.latitude, 'lng': fix.longitude},
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
      if (_motorcycle.text.trim().isNotEmpty)
        'motorcycle': _motorcycle.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!response.success) _error = response.message;
    });
    if (response.success) {
      _description.clear();
      await _load();
    }
  }

  Future<void> _offer(String id) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await _api.post<_Json>('$_base/requests/$id/offers', body: const {});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.success) _error = result.message;
    });
    await _load();
  }

  Future<void> _offerDecision(String id, _Json offer, String action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _api.patch<_Json>(
        '$_base/requests/$id/offers/${offer['id']}',
        body: {'action': action});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.success) _error = result.message;
    });
    await _load();
  }

  Future<void> _status(String id, String action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _api
        .patch<_Json>('$_base/requests/$id/status', body: {'action': action});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.success) _error = result.message;
    });
    await _load();
  }

  Future<void> _reportRequest(String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Report rider assistance'),
              content: TextField(
                  controller: controller,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'What should moderators review?')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Send report'))
              ],
            ));
    controller.dispose();
    if (!mounted || reason == null || reason.length < 3) return;
    final result = await _api
        .post<void>('$_base/requests/$id/report', body: {'reason': reason});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(result.success ? 'Report sent for review.' : result.message)));
  }

  Widget _requestCard(_Json item, {required bool own}) {
    final state = item['state'] as String? ?? 'open';
    final id = item['id'] as String;
    final offers = (item['offers'] as List? ?? const []).cast<_Json>();
    final location = item['location'] as _Json?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_types[item['type']] ?? 'Rider needs help',
              style: Theme.of(context).textTheme.titleMedium),
          if ((item['motorcycle'] as String? ?? '').isNotEmpty)
            Text(item['motorcycle'] as String),
          if ((item['description'] as String? ?? '').isNotEmpty)
            Text(item['description'] as String),
          Text('Status: ${state[0].toUpperCase()}${state.substring(1)}'),
          if (item['approximateDistanceKm'] is num)
            Text(
                'About ${(item['approximateDistanceKm'] as num).toStringAsFixed(1)} km away'),
          if (location != null)
            Text(
                'Shared location: ${(location['lat'] as num).toStringAsFixed(4)}, ${(location['lng'] as num).toStringAsFixed(4)}'),
          if (own && offers.isNotEmpty) ...[
            const Divider(),
            const Text('Rider offers'),
            for (final offer
                in offers.where((row) => row['state'] == 'pending'))
              Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Rider ${('${offer['helperId']}').substring(0, 6)}…'),
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () => _offerDecision(id, offer, 'decline'),
                        child: const Text('Decline')),
                    FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _offerDecision(id, offer, 'accept'),
                        child: const Text('Accept')),
                  ]),
          ],
          if (own && (state == 'open' || state == 'assigned'))
            OutlinedButton(
                onPressed: _busy
                    ? null
                    : () =>
                        _status(id, state == 'assigned' ? 'resolve' : 'cancel'),
                child: Text(
                    state == 'assigned' ? 'Mark resolved' : 'Cancel request')),
          if (!own && state == 'open')
            FilledButton.tonal(
                onPressed: _busy ? null : () => _offer(id),
                child: const Text('Offer help')),
          if (!own && state == 'assigned' && location != null)
            OutlinedButton.icon(
              onPressed: () => DestinationConfirmSheet.show(
                  context,
                  Destination(
                    name: 'Rider assistance meeting point',
                    latitude: (location['lat'] as num).toDouble(),
                    longitude: (location['lng'] as num).toDouble(),
                  )),
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Navigate to rider'),
            ),
          if ((own && state == 'assigned') ||
              (!own && state == 'open') ||
              (!own && state == 'assigned'))
            TextButton.icon(
                onPressed: _busy ? null : () => _reportRequest(id),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report')),
        ]),
      ),
    );
  }

  Widget _sectionHeading(String title, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleLarge)),
          Text('$count', style: Theme.of(context).textTheme.labelLarge),
        ]),
      );

  Widget _emptyNotice(IconData icon, String title, String message) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                ])),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rider Assist'), actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Card(
                    color: AppColors.errorSurface,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.emergency_outlined,
                                color: AppColors.errorLight),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('Immediate danger?',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                              color: AppColors.errorLight)),
                                  const SizedBox(height: 4),
                                  Text(
                                      'Community help is from volunteers and is not an emergency response service.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: _callEmergency112,
                                    icon: const Icon(Icons.call_outlined),
                                    label: const Text('Call 112'),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.errorLight),
                                  ),
                                ])),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      title: Text(_enabled
                          ? 'Available to help'
                          : 'Offer help to nearby riders'),
                      subtitle: const Text(
                          'Your opted-in location expires after 15 minutes.'),
                      value: _enabled,
                      onChanged: _busy ? null : _setAvailable,
                      secondary: Icon(
                          _enabled
                              ? Icons.location_on_outlined
                              : Icons.location_off_outlined,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Request help',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Tell nearby opted-in riders what you need.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              value: _type,
                              decoration: const InputDecoration(
                                  labelText: 'Type of help'),
                              items: [
                                for (final item in _types.entries)
                                  DropdownMenuItem(
                                      value: item.key, child: Text(item.value))
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      if (value != null)
                                        setState(() => _type = value);
                                    },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _motorcycle,
                              maxLength: 80,
                              decoration: const InputDecoration(
                                  labelText: 'Motorcycle (optional)',
                                  prefixIcon: Icon(Icons.two_wheeler_outlined)),
                            ),
                            TextField(
                              controller: _description,
                              maxLength: 500,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText: 'Add details (optional)',
                                  alignLabelWithHint: true),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _busy ? null : _requestHelp,
                              icon: const Icon(Icons.sos_outlined),
                              label: const Text('Review request'),
                            ),
                          ]),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 18),
                  _sectionHeading('My requests', _mine.length),
                  if (_mine.isEmpty)
                    _emptyNotice(Icons.support_outlined, 'No requests yet',
                        'Your active and past requests will appear here.'),
                  for (final item in _mine) _requestCard(item, own: true),
                  const SizedBox(height: 18),
                  _sectionHeading('Nearby requests', _nearby.length),
                  if (_helping.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Helping now',
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final item in _helping) _requestCard(item, own: false),
                  ],
                  if (!_enabled)
                    _emptyNotice(
                        Icons.location_searching,
                        'Turn on availability to browse',
                        'Your location is shared only while the opt-in is fresh.'),
                  if (_enabled && _nearby.isEmpty)
                    _emptyNotice(Icons.explore_outlined, 'No nearby requests',
                        'We’ll show requests from opted-in riders when they are available.'),
                  for (final item in _nearby) _requestCard(item, own: false),
                ])),
        floatingActionButton: _busy
            ? const FloatingActionButton(
                onPressed: null, child: CircularProgressIndicator())
            : null,
      );
}
