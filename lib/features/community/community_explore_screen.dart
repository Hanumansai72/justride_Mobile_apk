import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/destination.dart';
import '../../core/models/navigation_session.dart';
import '../../core/network/api_client.dart';
import '../navigation/widgets/destination_confirm_sheet.dart';
import 'community_rider_assist_screen.dart';
import 'community_rides_screen.dart';
import 'community_budget_screen.dart';
import 'community_settings_screen.dart';

typedef _Json = Map<String, dynamic>;
const _root = '/community';
const _posts = '$_root/experiences';
final _api = ApiClient.instance;
const _categories = [
  'Fuel',
  'Accommodation',
  'Food',
  'Tolls',
  'Maintenance',
  'Activities',
  'Other'
];

String _trip(_Json post) => '${post['origin']} → ${post['destination']}';
String _previewStory(_Json post) {
  final story = (post['story'] as String? ?? '').trim();
  return story.length <= 150 ? story : '${story.substring(0, 147)}…';
}

String _name(_Json post) =>
    (post['title'] as String?)?.trim().isNotEmpty == true
        ? post['title'] as String
        : 'Untitled draft';

String _money(_Json post) {
  final items = post['expenses'] as List? ?? const [];
  if (items.isEmpty) return '';
  final total = items.fold<num>(0, (sum, row) => sum + (row['amount'] as num));
  return '₹$total reported';
}

class CommunityExploreScreen extends StatefulWidget {
  const CommunityExploreScreen({super.key});

  @override
  State<CommunityExploreScreen> createState() => _CommunityExploreScreenState();
}

class _CommunityExploreScreenState extends State<CommunityExploreScreen> {
  final _search = TextEditingController();
  final _items = <_Json>[];
  final _filters = <String, String>{};
  String _section = 'Explore', _sort = 'relevance', _query = '';
  int? _next = 1;
  int _generation = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _next == null)) return;
    final generation = ++_generation;
    final page = reset ? 1 : _next!;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _next = 1;
      }
    });
    final path = switch (_section) {
      'My experiences' => '$_root/mine',
      'Saved' => '$_root/saved',
      _ => _posts,
    };
    final params = Uri(queryParameters: {
      'page': '$page',
      if (_section == 'Explore') ...{
        if (_query.isNotEmpty) 'q': _query,
        'sort': _sort,
        ..._filters,
      },
    }).query;
    final result = await _api.get<_Json>('$path?$params');
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      final data = result.data;
      if (result.success && data != null) {
        final known = _items.map((item) => item['id']).toSet();
        _items.addAll((data['items'] as List)
            .cast<_Json>()
            .where((item) => known.add(item['id'])));
        _next = data['nextPage'] as int?;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _showFilters() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ExploreFilters(values: _filters),
    );
    if (!mounted || result == null) return;
    setState(() => _filters
      ..clear()
      ..addAll(result));
    await _load(reset: true);
  }

  Future<void> _open(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (mounted && changed == true) await _load(reset: true);
  }

  Future<void> _toggleLike(_Json post) async {
    final result = await _api.put<void>('$_posts/${post['id']}/helpful',
        body: {'enabled': post['helpful'] != true});
    if (!mounted) return;
    if (result.success) {
      await _load(reset: true);
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Community'), actions: [
          IconButton.filledTonal(
            tooltip: 'Share a ride experience',
            onPressed: () => _open(const CommunityExperienceEditor()),
            icon: const Icon(Icons.add_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Community options',
            onSelected: (value) {
              if (value == 'budget') _open(const CommunityBudgetScreen());
              if (value == 'settings') _open(const CommunitySettingsScreen());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'budget', child: Text('Trip budget')),
              PopupMenuItem(
                  value: 'settings', child: Text('Community settings')),
            ],
          ),
        ]),
        body: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('Plan, share, and ride together',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Useful routes and advice from fellow riders.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 94,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _communityAction(
                        icon: Icons.groups_2_outlined,
                        title: 'Ride together',
                        subtitle: 'Plan with riders',
                        onTap: () => _open(const CommunityRidesScreen())),
                    _communityAction(
                        icon: Icons.sos_outlined,
                        title: 'Rider Assist',
                        subtitle: 'Find nearby help',
                        onTap: () => _open(const CommunityRiderAssistScreen())),
                    _communityAction(
                        icon: Icons.calculate_outlined,
                        title: 'Trip budget',
                        subtitle: 'Estimate your costs',
                        onTap: () => _open(const CommunityBudgetScreen())),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'Explore', label: Text('Explore')),
                  ButtonSegment(
                      value: 'My experiences', label: Text('My rides')),
                  ButtonSegment(value: 'Saved', label: Text('Saved')),
                ],
                selected: {_section},
                onSelectionChanged: (selection) {
                  final section = selection.first;
                  setState(() => _section = section);
                  _load(reset: true);
                },
              ),
              if (_section == 'Explore') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  maxLength: 120,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search destinations, routes or regions',
                    prefixIcon: const Icon(Icons.search),
                    counterText: '',
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              _submit('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onSubmitted: _submit,
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _showFilters,
                      icon: const Icon(Icons.tune),
                      label: Text(_filters.isEmpty
                          ? 'Filters'
                          : 'Filters (${_filters.length})'),
                    ),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _sort,
                      items: const [
                        DropdownMenuItem(
                            value: 'relevance', child: Text('Relevance')),
                        DropdownMenuItem(
                            value: 'recent', child: Text('Recent')),
                        DropdownMenuItem(
                            value: 'helpful', child: Text('Most helpful')),
                      ],
                      onChanged: (sort) {
                        if (sort == null || sort == _sort) return;
                        setState(() => _sort = sort);
                        _load(reset: true);
                      },
                    ),
                  ],
                ),
              ],
              for (final post in _items)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((post['images'] as List? ?? const []).isNotEmpty)
                          InkWell(
                            onTap: () => _open(
                                _ExperienceDetail(id: post['id'] as String)),
                            child: Image.network(
                              (post['images'] as List).first as String,
                              height: 170,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                  height: 100,
                                  child: Center(
                                      child:
                                          Icon(Icons.broken_image_outlined))),
                            ),
                          ),
                        ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title: Text(_name(post)),
                          subtitle: Text(
                              [
                                if (post['state'] == 'draft')
                                  'Private draft'
                                else
                                  _trip(post),
                                if (post['state'] != 'draft')
                                  post['authorName'],
                                if (_previewStory(post).isNotEmpty)
                                  _previewStory(post),
                                if (post['distanceKm'] != null)
                                  '${post['distanceKm']} km',
                                if (post['durationMinutes'] != null)
                                  '${post['durationMinutes']} min',
                                if (_money(post).isNotEmpty) _money(post),
                              ].join(' · '),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                          trailing: Icon(post['saved'] == true
                              ? Icons.bookmark
                              : Icons.chevron_right),
                          onTap: () => _open(
                              _ExperienceDetail(id: post['id'] as String)),
                        ),
                        if (post['state'] == 'published')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: post['isOwner'] == true
                                  ? null
                                  : () => _toggleLike(post),
                              icon: Icon(post['helpful'] == true
                                  ? Icons.thumb_up
                                  : Icons.thumb_up_outlined),
                              label:
                                  Text('${post['helpfulCount'] ?? 0} · Like'),
                            ),
                          ),
                      ]),
                ),
              if (_loading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator()))
              else if (_error != null) ...[
                Text(_error!),
                TextButton(
                    onPressed: () => _load(), child: const Text('Try again')),
              ] else if (_items.isEmpty)
                _emptyState()
              else if (_next != null)
                OutlinedButton(
                    onPressed: _load, child: const Text('Load more')),
            ],
          ),
        ),
      );

  Widget _communityAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 10),
        child: SizedBox(
          width: 168,
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 3),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _emptyState() {
    final isSaved = _section == 'Saved';
    final isMine = _section == 'My experiences';
    final searching = _query.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(children: [
          Icon(isSaved ? Icons.bookmark_border : Icons.route_outlined,
              size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            searching
                ? 'No matching ride stories'
                : isSaved
                    ? 'No saved rides yet'
                    : isMine
                        ? 'Your ride stories will appear here'
                        : 'No ride stories yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            searching
                ? 'Try a different destination or remove some filters.'
                : isSaved
                    ? 'Save a useful route or experience to find it here later.'
                    : 'Share a route, costs, and tips that could help another rider.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!isSaved && !searching) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _open(const CommunityExperienceEditor()),
              icon: const Icon(Icons.add),
              label: const Text('Share a ride experience'),
            ),
          ],
        ]),
      ),
    );
  }

  void _submit(String query) {
    _query = query.trim();
    _load(reset: true);
  }
}

const _filterLabels = {
  'region': 'Region',
  'motorcycle': 'Motorcycle',
  'season': 'Season',
  'distanceKm': 'Max distance (km)',
  'durationMinutes': 'Max duration (minutes)',
  'budget': 'Max reported cost (₹)',
};

class _ExploreFilters extends StatefulWidget {
  const _ExploreFilters({required this.values});
  final Map<String, String> values;

  @override
  State<_ExploreFilters> createState() => _ExploreFiltersState();
}

class _ExploreFiltersState extends State<_ExploreFilters> {
  late final _fields = {
    for (final key in _filterLabels.keys)
      key: TextEditingController(text: widget.values[key])
  };

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Filter ride experiences'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final entry in _filterLabels.entries)
              TextField(
                controller: _fields[entry.key],
                keyboardType: ['distanceKm', 'durationMinutes', 'budget']
                        .contains(entry.key)
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(labelText: entry.value),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, <String, String>{}),
              child: const Text('Clear')),
          FilledButton(
              onPressed: () => Navigator.pop(context, {
                    for (final entry in _fields.entries)
                      if (entry.value.text.trim().isNotEmpty)
                        entry.key: entry.value.text.trim(),
                  }),
              child: const Text('Apply')),
        ],
      );
}

class _ExperienceDetail extends StatefulWidget {
  const _ExperienceDetail({required this.id});
  final String id;

  @override
  State<_ExperienceDetail> createState() => _ExperienceDetailState();
}

class _ExperienceDetailState extends State<_ExperienceDetail> {
  late Future<ApiResponse<_Json>> _result =
      _api.get<_Json>('$_posts/${widget.id}');
  bool _busy = false, _dirty = false;

  void _reload() =>
      setState(() => _result = _api.get<_Json>('$_posts/${widget.id}'));

  Future<bool> _perform(Future<ApiResponse<void>> Function() run,
      {bool close = false}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final result = await run();
    if (!mounted) return false;
    setState(() => _busy = false);
    if (!result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      return false;
    }
    _dirty = true;
    if (close) {
      Navigator.of(context).pop(true);
    } else {
      _reload();
    }
    return true;
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
        context: context, builder: (_) => const _ReportDialog());
    if (!mounted || reason == null) return;
    final sent = await _perform(() => _api
        .post<void>('$_posts/${widget.id}/report', body: {'reason': reason}));
    if (mounted && sent) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report sent for review.')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this experience?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => _api.delete<void>('$_posts/${widget.id}'),
          close: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _dirty) Navigator.of(context).pop(true);
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Ride experience')),
          body: FutureBuilder<ApiResponse<_Json>>(
            future: _result,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final post = snapshot.data?.data;
              if (post == null) {
                return Center(
                    child: TextButton(
                        onPressed: _reload,
                        child: Text(snapshot.data?.message ?? 'Try again')));
              }
              final isOwner = post['isOwner'] == true;
              final published = post['state'] == 'published';
              return ListView(padding: const EdgeInsets.all(20), children: [
                Text(_name(post),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(published ? _trip(post) : 'Private draft'),
                Text(post['authorName'] as String),
                if ((post['images'] as List? ?? const []).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: (post['images'] as List).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) => ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          (post['images'] as List)[index] as String,
                          width: MediaQuery.sizeOf(context).width - 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              width: 220,
                              child: Center(
                                  child: Icon(Icons.broken_image_outlined))),
                        ),
                      ),
                    ),
                  ),
                ],
                if (published && !isOwner)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CommunityRiderProfileScreen(
                          id: post['authorId'] as String),
                    )),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Rider profile and reputation'),
                  ),
                if (post['linkedRide'] == true)
                  const Text(
                      'Linked to a ride history record. Details are rider reported.'),
                if (post['motorcycle'] case final String bike
                    when bike.isNotEmpty)
                  Text(bike),
                if (post['travelledOn'] != null)
                  Text('Travel date: ${post['travelledOn']}'),
                const SizedBox(height: 16),
                Text(post['story'] as String? ?? ''),
                if (post['roadNotes'] case final String notes
                    when notes.isNotEmpty)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Road notes'),
                      subtitle: Text(notes)),
                if (post['hotel'] case final String hotel when hotel.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(hotel),
                    subtitle: Text([
                      if (post['hotelCost'] != null)
                        '₹${post['hotelCost']} per night, reported',
                      if (post['hotelParking'] case final String parking
                          when parking.isNotEmpty)
                        parking,
                    ].join(' · ')),
                  ),
                if (_money(post).isNotEmpty) ...[
                  Text('Expenses · ${_money(post)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final expense in post['expenses'] as List)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(expense['category'] as String),
                        trailing: Text('₹${expense['amount']}')),
                ],
                if (published)
                  OutlinedButton.icon(
                    onPressed: () => DestinationConfirmSheet.show(
                        context, _place(post['destination']),
                        startLocation: _place(post['origin'])),
                    label: const Text('Plan this ride with current routes'),
                    icon: const Icon(Icons.route_outlined),
                  ),
                if (published)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: isOwner || _busy
                          ? null
                          : () => _perform(() => _api.put<void>(
                              '$_posts/${widget.id}/helpful',
                              body: {'enabled': post['helpful'] != true})),
                      icon: Icon(post['helpful'] == true
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined),
                      label: Text(
                          '${post['helpfulCount'] ?? 0} likes · ${post['helpful'] == true ? 'Liked' : 'Like'}'),
                    ),
                  ),
                Wrap(spacing: 8, children: [
                  if (published)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _perform(() => _api.put<void>(
                              '$_posts/${widget.id}/saved',
                              body: {'enabled': post['saved'] != true})),
                      icon: Icon(post['saved'] == true
                          ? Icons.bookmark
                          : Icons.bookmark_outline),
                      label: Text(post['saved'] == true ? 'Unsave' : 'Save'),
                    ),
                  if (published && !isOwner) ...[
                    TextButton(
                        onPressed: _busy ? null : _report,
                        child: const Text('Report')),
                  ],
                  if (isOwner) ...[
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final changed = await Navigator.of(context)
                                    .push<bool>(MaterialPageRoute(
                                        builder: (_) =>
                                            CommunityExperienceEditor(
                                                existing: post)));
                                if (mounted && changed == true) {
                                  _dirty = true;
                                  _reload();
                                }
                              },
                        child: const Text('Edit')),
                    TextButton(
                        onPressed: _busy ? null : _delete,
                        child: const Text('Delete')),
                  ],
                ]),
              ]);
            },
          ),
        ),
      );

  Destination _place(dynamic text) => Destination(
        name: text as String,
        rawQuery: text,
        address: text,
        latitude: 0,
        longitude: 0,
      );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _reason = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Report this experience'),
        content: TextField(
            maxLength: 500,
            maxLines: 3,
            onChanged: (value) => setState(() => _reason = value.trim()),
            decoration: const InputDecoration(labelText: 'Reason')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _reason.length < 3
                  ? null
                  : () => Navigator.pop(context, _reason),
              child: const Text('Send report')),
        ],
      );
}

const _labels = {
  'title': 'Experience title',
  'origin': 'Public starting town or landmark',
  'destination': 'Public destination',
  'region': 'Region',
  'motorcycle': 'Motorcycle',
  'story': 'Description',
  'roadNotes': 'Road conditions and riding notes',
  'season': 'Riding season',
  'travelledOn': 'Travel date (YYYY-MM-DD)',
  'distanceKm': 'Distance (km)',
  'durationMinutes': 'Ride time (minutes)',
  'hotel': 'Accommodation',
  'hotelCost': 'Cost per night (₹)',
  'hotelParking': 'Parking and security notes',
};
const _numbers = {'distanceKm', 'durationMinutes', 'hotelCost'};

class CommunityExperienceEditor extends StatefulWidget {
  const CommunityExperienceEditor({super.key, this.existing, this.ride});
  final Map<String, dynamic>? existing;
  final NavigationSession? ride;

  @override
  State<CommunityExperienceEditor> createState() =>
      _CommunityExperienceEditorState();
}

class CommunityRiderProfileScreen extends StatefulWidget {
  const CommunityRiderProfileScreen({super.key, required this.id});
  final String id;

  @override
  State<CommunityRiderProfileScreen> createState() =>
      _CommunityRiderProfileScreenState();
}

class _CommunityRiderProfileScreenState
    extends State<CommunityRiderProfileScreen> {
  bool _busy = false;
  Future<ApiResponse<_Json>> _load() =>
      _api.get<_Json>('$_root/profiles/${widget.id}');
  late Future<ApiResponse<_Json>> _result = _load();

  Future<void> _report() async {
    final reason = await showDialog<String>(
        context: context, builder: (_) => const _ReportDialog());
    if (!mounted || reason == null) return;
    setState(() => _busy = true);
    final result = await _api.post<void>('$_root/profiles/${widget.id}/report',
        body: {'reason': reason});
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(result.success ? 'Report sent for review.' : result.message)));
  }

  Future<void> _block() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Block this rider?'),
              content: const Text(
                  'Blocked riders will not appear in your Community ride suggestions or Rider Assist results.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Block rider')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await _api
        .post<void>('$_root/settings/blocks', body: {'userId': widget.id});
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.success ? 'Rider blocked.' : result.message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rider profile')),
        body: FutureBuilder<ApiResponse<_Json>>(
          future: _result,
          builder: (context, snapshot) {
            final data = snapshot.data?.data;
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            if (data == null)
              return Center(
                  child: Text(
                      snapshot.data?.message ?? 'Rider profile unavailable.'));
            return ListView(padding: const EdgeInsets.all(20), children: [
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(data['name'] as String? ?? 'Rider'),
                  subtitle: const Text('Community activity'),
                  trailing: IconButton(
                      tooltip: 'Report rider',
                      onPressed: _busy ? null : _report,
                      icon: const Icon(Icons.flag_outlined))),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _block,
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Block rider')),
              Card(
                  child: Column(children: [
                ListTile(
                    title: const Text('Completed ride records'),
                    trailing: Text('${data['completedRideRecords']}')),
                ListTile(
                    title: const Text('Published ride experiences'),
                    trailing: Text('${data['publishedExperiences']}')),
                ListTile(
                    title: const Text('Helpful votes received'),
                    trailing: Text('${data['helpfulRecommendations']}')),
                ListTile(
                    title: const Text('Completed group rides hosted'),
                    trailing: Text('${data['organizedRides']}')),
              ])),
              const Text(
                  'Ride records verify that a journey was recorded. Expenses and recommendations are rider reported.'),
            ]);
          },
        ),
      );
}

class _CommunityExperienceEditorState extends State<CommunityExperienceEditor> {
  late final _fields = {
    for (final key in _labels.keys)
      key: TextEditingController(
          text: (widget.existing?[key] ??
                  switch (key) {
                    'distanceKm' => widget.ride?.distanceKm.toStringAsFixed(1),
                    'durationMinutes' => widget.ride == null
                        ? null
                        : (widget.ride!.durationSeconds / 60).round(),
                    'travelledOn' => widget.ride?.startTime
                        .toLocal()
                        .toIso8601String()
                        .split('T')
                        .first,
                    _ => null,
                  })
              ?.toString()),
  };
  late final _expenses = {
    for (final category in _categories)
      category: TextEditingController(text: _existingExpense(category)),
  };
  late final List<String> _images =
      List<String>.from(widget.existing?['images'] as List? ?? const []);
  final Set<String> _newImages = {};
  final Set<String> _removedImages = {};
  bool _saving = false;
  bool _uploadingImages = false;
  bool _saved = false;
  String? _error;

  String? _existingExpense(String name) {
    final values = (widget.existing?['expenses'] as List? ?? const [])
        .where((entry) => entry['category'] == name)
        .toList();
    return values.isEmpty
        ? null
        : values
            .fold<num>(0, (sum, x) => sum + (x['amount'] as num))
            .toString();
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final url in _newImages) {
        unawaited(_deleteImage(url));
      }
    }
    for (final field in [..._fields.values, ..._expenses.values]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _deleteImage(String url) async {
    await _api.delete<void>('/upload/image', body: {'url': url});
  }

  Future<void> _pickImages() async {
    if (_uploadingImages || _saving || _images.length >= 4) return;
    try {
      final picked = await ImagePicker()
          .pickMultiImage(imageQuality: 84, maxWidth: 1600, maxHeight: 1200);
      if (!mounted || picked.isEmpty) return;
      setState(() => _uploadingImages = true);
      for (final image in picked.take(4 - _images.length)) {
        final bytes = await image.readAsBytes();
        final result = await _api.uploadMultipart<_Json>(
          '/upload/community-image',
          fileBytes: bytes,
          filename: image.name,
          fileContentType: image.mimeType,
          fromJson: (json) => Map<String, dynamic>.from(json as Map),
        );
        final url = result.data?['secure_url'] as String?;
        if (!result.success || url == null || url.isEmpty) {
          if (mounted) setState(() => _error = result.message);
          break;
        }
        _newImages.add(url);
        if (mounted) setState(() => _images.add(url));
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not add this photo. Try another image.');
    } finally {
      if (mounted) setState(() => _uploadingImages = false);
    }
  }

  void _removeImage(String url) {
    final isNew = _newImages.remove(url);
    setState(() {
      _images.remove(url);
      if (!isNew) _removedImages.add(url);
    });
    if (isNew) unawaited(_deleteImage(url));
  }

  Future<void> _save(bool publish) async {
    if (_saving || _uploadingImages) return;
    final values =
        _fields.map((key, field) => MapEntry(key, field.text.trim()));
    if (publish &&
        ['title', 'origin', 'destination', 'story']
            .any((key) => values[key]!.isEmpty)) {
      setState(() => _error =
          'Add a title, public start, destination, and your ride experience.');
      return;
    }
    final body = <String, dynamic>{
      'publish': publish,
      if (widget.ride != null) 'sourceSessionId': widget.ride!.sessionId,
    };
    for (final entry in values.entries) {
      if (_numbers.contains(entry.key)) {
        if (entry.value.isEmpty) continue;
        final number = entry.key == 'distanceKm'
            ? double.tryParse(entry.value)
            : int.tryParse(entry.value);
        if (number == null || !number.isFinite || number < 0) {
          setState(
              () => _error = 'Check the distance, duration, and cost fields.');
          return;
        }
        body[entry.key] = number;
      } else if (entry.key != 'travelledOn' || entry.value.isNotEmpty) {
        body[entry.key] = entry.value;
      }
    }
    final expenses = <_Json>[];
    for (final entry in _expenses.entries) {
      final value = entry.value.text.trim();
      if (value.isEmpty) continue;
      final amount = int.tryParse(value);
      if (amount == null || amount < 0) {
        setState(() => _error = 'Use whole rupee amounts for expenses.');
        return;
      }
      expenses.add({'category': entry.key, 'amount': amount});
    }
    body['expenses'] = expenses;
    body['images'] = _images;
    setState(() {
      _saving = true;
      _error = null;
    });
    final id = widget.existing?['id'];
    final result = id == null
        ? await _api.post<_Json>(_posts, body: body)
        : await _api.patch<_Json>('$_posts/$id', body: body);
    if (!mounted) return;
    if (result.success) {
      _saved = true;
      for (final url in _removedImages) {
        unawaited(_deleteImage(url));
      }
      _newImages.clear();
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Write a ride experience')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'Use public places for the start and destination. Review details before publishing.'),
          const SizedBox(height: 18),
          Text('Photos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Add up to four photos to your ride story.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          SizedBox(
            height: 112,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final url in _images)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          url,
                          width: 132,
                          height: 112,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              width: 132,
                              child: Center(
                                  child: Icon(Icons.broken_image_outlined))),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filledTonal(
                          tooltip: 'Remove photo',
                          onPressed: _saving ? null : () => _removeImage(url),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ),
                    ]),
                  ),
                if (_images.length < 4)
                  SizedBox(
                    width: 112,
                    child: OutlinedButton.icon(
                      onPressed:
                          _saving || _uploadingImages ? null : _pickImages,
                      icon: _uploadingImages
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(_uploadingImages ? 'Adding' : 'Add photo'),
                    ),
                  ),
              ],
            ),
          ),
          for (final entry in _labels.entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: _fields[entry.key],
                enabled: !_saving,
                maxLines: ['story', 'roadNotes'].contains(entry.key) ? 3 : 1,
                keyboardType: _numbers.contains(entry.key)
                    ? TextInputType.numberWithOptions(
                        decimal: entry.key == 'distanceKm')
                    : TextInputType.text,
                decoration: InputDecoration(labelText: entry.value),
              ),
            ),
          const SizedBox(height: 16),
          Text('Trip expenses', style: Theme.of(context).textTheme.titleMedium),
          for (final entry in _expenses.entries)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  controller: entry.value,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '${entry.key} (₹)'),
                )),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: _saving || _uploadingImages ? null : () => _save(true),
              child: const Text('Publish experience')),
          OutlinedButton(
              onPressed:
                  _saving || _uploadingImages ? null : () => _save(false),
              child: const Text('Save private draft')),
        ]),
      );
}
