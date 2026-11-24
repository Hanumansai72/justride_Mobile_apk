import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';

typedef _Json = Map<String, dynamic>;

class CommunitySettingsScreen extends StatefulWidget {
  const CommunitySettingsScreen({super.key});
  @override
  State<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  static const _path = '/community/settings/notifications';
  final _api = ApiClient.instance;
  _Json _values = {
    'rideInvitations': true,
    'rideRequests': true,
    'assistanceNearby': true,
    'assistanceOffers': true
  };
  List<_Json> _blocks = [];
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _api.get<_Json>(_path);
    final blocks = await _api.get<_Json>('/community/settings/blocks');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success && result.data != null)
        _values = result.data!;
      else
        _error = result.message;
      if (blocks.success && blocks.data != null) {
        _blocks = (blocks.data!['items'] as List).cast<_Json>();
      }
    });
  }

  Future<void> _unblock(String id) async {
    setState(() => _saving = true);
    final result = await _api.delete<_Json>('/community/settings/blocks/$id');
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.success) {
        _blocks.removeWhere((item) => item['id'] == id);
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _set(String key, bool value) async {
    final old = Map<String, dynamic>.of(_values);
    final next = {..._values, key: value};
    setState(() {
      _values = next;
      _saving = true;
      _error = null;
    });
    final result = await _api.put<_Json>(_path, body: next);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!result.success) {
        _values = old;
        _error = result.message;
      } else if (result.data != null) _values = result.data!;
    });
  }

  Widget _toggle(String key, String title, String subtitle) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: _values[key] == true,
      onChanged: _loading || _saving ? null : (value) => _set(key, value));

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Community settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              const Text(
                  'Choose which Community events can notify you. Location sharing for Rider Assist is controlled separately.'),
              const SizedBox(height: 12),
              _toggle('rideInvitations', 'Ride invitations',
                  'When another rider invites you to a private ride.'),
              _toggle('rideRequests', 'Ride requests and decisions',
                  'When someone requests your ride or a host responds.'),
              _toggle('assistanceNearby', 'Nearby assistance requests',
                  'When an opted-in rider nearby requests help.'),
              _toggle('assistanceOffers', 'Assistance offer updates',
                  'When a rider offers help or accepts your offer.'),
              const SizedBox(height: 20),
              Text('Blocked riders',
                  style: Theme.of(context).textTheme.titleLarge),
              if (_blocks.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No riders blocked.')),
              for (final rider in _blocks)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.block_outlined),
                    title: Text(rider['name'] as String? ?? 'Rider'),
                    trailing: TextButton(
                        onPressed: _saving
                            ? null
                            : () => _unblock(rider['id'] as String),
                        child: const Text('Unblock'))),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ]));
}
