import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';

typedef _Json = Map<String, dynamic>;
const _path = '/community/rides';

class CommunityRidesScreen extends StatefulWidget {
  const CommunityRidesScreen({super.key});
  @override
  State<CommunityRidesScreen> createState() => _CommunityRidesScreenState();
}

class _CommunityRidesScreenState extends State<CommunityRidesScreen> {
  final _api = ApiClient.instance;
  List<_Json> _rides = [];
  int _tab = 0;
  bool _loading = false;
  String? _error;
  String? _matchReason;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final path = switch (_tab) {
      1 => '$_path/mine',
      2 => '$_path/invitations',
      _ => _path
    };
    final result = await _api.get<_Json>(path);
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        _rides = (result.data!['items'] as List).cast<_Json>();
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _action(String route,
      {String method = 'post', _Json? body}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = switch (method) {
      'delete' => await _api.delete<_Json>(route, body: body),
      'patch' => await _api.patch<_Json>(route, body: body),
      _ => await _api.post<_Json>(route, body: body ?? const {}),
    };
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.success) _error = result.message;
    });
    await _load();
  }

  Future<void> _create() async {
    final form = await showDialog<_Json>(
        context: context, builder: (_) => const _CreateCommunityRideDialog());
    if (form == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _api.post<_Json>(_path, body: form);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.success)
        _error = result.message;
      else
        _tab = 1;
    });
    await _load();
  }

  Future<void> _findMatches() async {
    final destination = TextEditingController();
    var departure = DateTime.now().add(const Duration(days: 1));
    final query = await showDialog<_Json>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: const Text('Find rides near your plan'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: destination,
                        decoration:
                            const InputDecoration(labelText: 'Destination')),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Planned departure'),
                        subtitle: Text(MaterialLocalizations.of(context)
                            .formatMediumDate(departure)),
                        trailing: const Icon(Icons.calendar_month),
                        onTap: () async {
                          final picked = await showDatePicker(
                              context: context,
                              initialDate: departure,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 180)));
                          if (picked != null)
                            update(() => departure = DateTime(picked.year,
                                picked.month, picked.day, departure.hour));
                        }),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, {
                              'destination': destination.text.trim(),
                              'departureAt': departure.toUtc().toIso8601String()
                            }),
                        child: const Text('Find rides'))
                  ],
                )));
    destination.dispose();
    if (query == null ||
        (query['destination'] as String).length < 2 ||
        !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _matchReason = null;
      _tab = 0;
    });
    final params =
        Uri(queryParameters: query.map((key, value) => MapEntry(key, '$value')))
            .query;
    final result = await _api.get<_Json>('$_path/matches?$params');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        _rides = (result.data!['items'] as List).cast<_Json>();
        _matchReason = result.data!['reason'] as String?;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _invite(String id) async {
    final identifier = await showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return AlertDialog(
              title: const Text('Invite a rider'),
              content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Rider email or username')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Send invite'))
              ]);
        });
    if (identifier == null || identifier.isEmpty) return;
    await _action('$_path/$id/invite', body: {'identifier': identifier});
  }

  Future<void> _reportRide(String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Report ride'),
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
    final result =
        await _api.post<void>('$_path/$id/report', body: {'reason': reason});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(result.success ? 'Report sent for review.' : result.message)));
  }

  Widget _card(_Json ride) {
    final id = ride['id'] as String;
    final date =
        DateTime.tryParse(ride['departureAt'] as String? ?? '')?.toLocal();
    final requests = (ride['requests'] as List? ?? const []).cast<_Json>();
    final myRequest = ride['myRequest'] as String?;
    final isHost = ride['isHost'] == true;
    final isMember = ride['isMember'] == true;
    final state = ride['state'] as String? ?? 'planned';
    final departureAt = DateTime.tryParse(ride['departureAt'] as String? ?? '');
    final canComplete =
        departureAt != null && !departureAt.isAfter(DateTime.now());
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(ride['title'] as String? ?? 'Upcoming ride',
                        style: Theme.of(context).textTheme.titleMedium)),
                if (ride['visibility'] == 'private')
                  const Icon(Icons.lock_outline, size: 18)
              ]),
              Text('${ride['origin']} → ${ride['destination']}'),
              Text(
                  '${date == null ? 'Date not set' : MaterialLocalizations.of(context).formatMediumDate(date)} · ${ride['pace']} pace'),
              Text(
                  'Host: ${(ride['host'] as _Json)['name']} · ${ride['slotsLeft']} places available'),
              if ((ride['meetingPoint'] as String? ?? '').isNotEmpty)
                Text('Meet: ${ride['meetingPoint']}'),
              if (ride['budget'] != null)
                Text(
                    'Estimated budget: ₹${ride['budget']} per rider (host estimate)'),
              if ((ride['description'] as String? ?? '').isNotEmpty)
                Text(ride['description'] as String),
              if (isHost && requests.isNotEmpty) ...[
                const Divider(),
                const Text('Pending requests and invitations'),
                for (final request in requests)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(request['rider']['name'] as String),
                      subtitle: Text(request['kind'] == 'invite'
                          ? 'Invitation pending'
                          : 'Join request'),
                      trailing: request['kind'] == 'invite'
                          ? IconButton(
                              tooltip: 'Cancel invite',
                              onPressed: _loading
                                  ? null
                                  : () => _action(
                                      '$_path/$id/requests/${request['id']}',
                                      method: 'delete'),
                              icon: const Icon(Icons.person_remove_outlined))
                          : Wrap(spacing: 0, children: [
                              IconButton(
                                  tooltip: 'Reject',
                                  onPressed: _loading
                                      ? null
                                      : () => _action(
                                          '$_path/$id/requests/${request['id']}',
                                          method: 'patch',
                                          body: {'action': 'reject'}),
                                  icon: const Icon(Icons.close)),
                              IconButton(
                                  tooltip: 'Accept',
                                  onPressed: _loading
                                      ? null
                                      : () => _action(
                                          '$_path/$id/requests/${request['id']}',
                                          method: 'patch',
                                          body: {'action': 'accept'}),
                                  icon: const Icon(Icons.check)),
                            ])),
              ],
              if (_tab == 2)
                Wrap(children: [
                  FilledButton(
                      onPressed: _loading
                          ? null
                          : () => _action('$_path/invitations/$id/respond',
                              body: {'action': 'accept'}),
                      child: const Text('Accept invite')),
                  TextButton(
                      onPressed: _loading
                          ? null
                          : () => _action('$_path/invitations/$id/respond',
                              body: {'action': 'decline'}),
                      child: const Text('Decline')),
                ])
              else if (!isHost &&
                  !isMember &&
                  myRequest == null &&
                  state == 'planned' &&
                  ride['visibility'] == 'public')
                FilledButton.tonal(
                    onPressed:
                        _loading ? null : () => _action('$_path/$id/join'),
                    child: const Text('Request to join'))
              else if (!isHost && myRequest == 'pending' && _tab == 0)
                TextButton(
                    onPressed: _loading
                        ? null
                        : () =>
                            _action('$_path/$id/requests/me', method: 'delete'),
                    child: const Text('Cancel request')),
              if (isHost &&
                  ride['visibility'] == 'private' &&
                  state == 'planned')
                OutlinedButton.icon(
                    onPressed: _loading ? null : () => _invite(id),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Invite rider')),
              if (isHost && state == 'planned' && canComplete)
                TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _action('$_path/$id/state',
                            method: 'patch', body: {'state': 'completed'}),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Mark completed')),
              if (isHost && state == 'planned')
                TextButton(
                    onPressed: _loading
                        ? null
                        : () => _action('$_path/$id/state',
                            method: 'patch', body: {'state': 'cancelled'}),
                    child: const Text('Cancel ride'))
              else if (!isHost && isMember && state == 'planned')
                TextButton(
                    onPressed: _loading
                        ? null
                        : () => _action('$_path/$id/participants/me',
                            method: 'delete'),
                    child: const Text('Leave ride')),
              if (!isHost &&
                  ride['visibility'] == 'public' &&
                  state == 'planned')
                TextButton.icon(
                    onPressed: _loading ? null : () => _reportRide(id),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Report ride')),
            ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ride Together'), actions: [
          IconButton(
              tooltip: 'Find a compatible ride',
              onPressed: _loading ? null : _findMatches,
              icon: const Icon(Icons.travel_explore)),
          IconButton(
              tooltip: 'Create a ride',
              onPressed: _loading ? null : _create,
              icon: const Icon(Icons.add)),
        ]),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Upcoming')),
                    ButtonSegment(value: 1, label: Text('My rides')),
                    ButtonSegment(value: 2, label: Text('Invites'))
                  ],
                  selected: {
                    _tab
                  },
                  onSelectionChanged: _loading
                      ? null
                      : (value) {
                          setState(() => _tab = value.first);
                          _load();
                        }),
              const SizedBox(height: 12),
              if (_matchReason != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Suggested using: $_matchReason')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              for (final ride in _rides) _card(ride),
              if (_loading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator())),
              if (!_loading && _rides.isEmpty && _error == null)
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_tab == 2
                        ? 'No ride invitations.'
                        : 'No rides found. Start one for your next trip.')),
            ])),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _loading ? null : _create,
            icon: const Icon(Icons.add_road),
            label: const Text('Plan a ride')),
      );
}

class _CreateCommunityRideDialog extends StatefulWidget {
  const _CreateCommunityRideDialog();
  @override
  State<_CreateCommunityRideDialog> createState() =>
      _CreateCommunityRideDialogState();
}

class _CreateCommunityRideDialogState
    extends State<_CreateCommunityRideDialog> {
  final _title = TextEditingController(),
      _origin = TextEditingController(),
      _destination = TextEditingController(),
      _meeting = TextEditingController(),
      _description = TextEditingController();
  DateTime _departure = DateTime.now().add(const Duration(days: 1));
  String _pace = 'steady', _experience = 'any', _visibility = 'public';
  int _capacity = 6;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _origin.dispose();
    _destination.dispose();
    _meeting.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
        context: context,
        initialDate: _departure,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 180)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_departure));
    if (time == null || !mounted) return;
    setState(() => _departure =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    if ([_title.text, _origin.text, _destination.text]
            .any((item) => item.trim().length < 2) ||
        _departure.isBefore(DateTime.now())) return;
    Navigator.pop(context, {
      'title': _title.text.trim(),
      'origin': _origin.text.trim(),
      'destination': _destination.text.trim(),
      'departureAt': _departure.toUtc().toIso8601String(),
      'capacity': _capacity,
      'pace': _pace,
      'experienceLevel': _experience,
      'visibility': _visibility,
      if (_meeting.text.trim().isNotEmpty) 'meetingPoint': _meeting.text.trim(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim()
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Plan a group ride'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _title,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Ride title')),
              TextField(
                  controller: _origin,
                  maxLength: 100,
                  decoration:
                      const InputDecoration(labelText: 'Starting place')),
              TextField(
                  controller: _destination,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Destination')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Departure'),
                  subtitle: Text(MaterialLocalizations.of(context)
                      .formatFullDate(_departure)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: _pickDate),
              TextField(
                  controller: _meeting,
                  maxLength: 120,
                  decoration: const InputDecoration(
                      labelText: 'Meeting point (optional)')),
              DropdownButtonFormField<String>(
                  value: _pace,
                  decoration: const InputDecoration(labelText: 'Riding pace'),
                  items: const [
                    DropdownMenuItem(value: 'relaxed', child: Text('Relaxed')),
                    DropdownMenuItem(value: 'steady', child: Text('Steady')),
                    DropdownMenuItem(value: 'brisk', child: Text('Brisk'))
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _pace = value);
                  }),
              DropdownButtonFormField<String>(
                  value: _experience,
                  decoration:
                      const InputDecoration(labelText: 'Experience level'),
                  items: const [
                    DropdownMenuItem(value: 'any', child: Text('Any')),
                    DropdownMenuItem(
                        value: 'beginner', child: Text('Beginner friendly')),
                    DropdownMenuItem(
                        value: 'intermediate', child: Text('Intermediate')),
                    DropdownMenuItem(
                        value: 'experienced', child: Text('Experienced'))
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _experience = value);
                  }),
              DropdownButtonFormField<String>(
                  value: _visibility,
                  decoration: const InputDecoration(labelText: 'Visibility'),
                  items: const [
                    DropdownMenuItem(
                        value: 'public',
                        child: Text('Public · riders can request to join')),
                    DropdownMenuItem(
                        value: 'private',
                        child: Text('Private · invite riders'))
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _visibility = value);
                  }),
              DropdownButtonFormField<int>(
                  value: _capacity,
                  decoration:
                      const InputDecoration(labelText: 'Maximum riders'),
                  items: [
                    for (var value = 2; value <= 15; value++)
                      DropdownMenuItem(
                          value: value, child: Text('$value riders'))
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _capacity = value);
                  }),
              TextField(
                  controller: _description,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Ride details (optional)')),
              const Text(
                  'Only share a public meeting place. Precise live locations stay limited to a rider’s explicit sharing setting.'),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Create ride'))
        ],
      );
}
