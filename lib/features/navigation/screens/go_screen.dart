import 'ride_tools_screen.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/ride_history_service.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/google_maps_service.dart';
import '../widgets/destination_confirm_sheet.dart';

class GoScreen extends StatefulWidget {
  const GoScreen({super.key, this.initialDestination});
  final Destination? initialDestination;
  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen> {
  static const _current = 'Current location';
  final _from = TextEditingController(text: _current),
      _to = TextEditingController();
  final _fromFocus = FocusNode(), _toFocus = FocusNode();
  Destination? _origin, _destination;
  List<Destination> _results = [];
  List<Destination> _recent = [];
  SharedPreferences? _prefs;
  String? _historyKey;
  Future<void> _loadHistory() async {
    final user = await RideHistoryService.instance.currentUserId();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || user == null) return;
    _prefs = prefs;
    _historyKey = 'recent_search_places_$user';
    final places = <Destination>[];
    for (final entry in prefs.getStringList(_historyKey!) ?? <String>[]) {
      try {
        places.add(Destination.fromJson(entry));
      } catch (_) {}
    }
    setState(() => _recent = places);
  }

  void _remember(Destination place) {
    if (_historyKey == null) return;
    _recent = [
      place,
      ..._recent.where((item) => item.toJson() != place.toJson())
    ].take(15).toList();
    _persistHistory();
  }

  void _removeRecent(Destination place) {
    if (_historyKey == null) return;
    setState(
        () => _recent.removeWhere((item) => item.toJson() == place.toJson()));
    _persistHistory();
  }

  void _clearRecent() {
    if (_historyKey == null || _recent.isEmpty) return;
    setState(_recent.clear);
    _persistHistory();
  }

  void _persistHistory() {
    final key = _historyKey;
    final prefs = _prefs;
    if (key == null || prefs == null) return;
    unawaited(prefs.setStringList(
        key, _recent.map((place) => place.toJson()).toList()));
  }

  Timer? _debounce;
  int _generation = 0;
  int? _selectionGeneration;
  String? _sessionToken;
  bool _searching = false, _searchFrom = false, _opening = false;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _destination = widget.initialDestination;
    _to.text = _destination?.displayTitle ?? '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _from.dispose();
    _to.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _focusField(bool from) {
    if (_searchFrom == from) return;
    _debounce?.cancel();
    ++_generation;
    _sessionToken = null;
    setState(() {
      _searchFrom = from;
      _query = '';
      _results = [];
      _searching = false;
    });
  }

  void _search(String value, {required bool from, bool submit = false}) {
    final query = value.trim();
    if (!submit && query.isNotEmpty && _searchFrom == from && _query == query) {
      return;
    }
    _debounce?.cancel();
    if (_searchFrom != from || query.length < 2 || submit) {
      _sessionToken = null;
    }
    final generation = ++_generation;
    setState(() {
      _searchFrom = from;
      _query = query;
      _results = [];
      _searching = _query.length >= 2;
      if (from)
        _origin = null;
      else
        _destination = null;
    });
    if (query.length < 2) return;
    final token = submit
        ? null
        : (_sessionToken ??= GoogleMapsService.newPlacesSessionToken());
    Future<void> load() async {
      try {
        final results = await GoogleMapsService.instance.searchPlaces(
          query,
          autocomplete: !submit,
          sessionToken: token,
        );
        if (mounted && generation == _generation)
          setState(() => _results = results);
      } catch (_) {
        if (mounted && generation == _generation) setState(() => _results = []);
      } finally {
        if (mounted && generation == _generation)
          setState(() => _searching = false);
      }
    }

    if (submit) {
      unawaited(load());
    } else {
      _debounce = Timer(const Duration(milliseconds: 300), load);
    }
  }

  Future<void> _choose(Destination place) async {
    if (_selectionGeneration == _generation) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final token = _sessionToken;
    _sessionToken = null;
    if (place.placeId?.isNotEmpty == true &&
        (place.latitude == 0 || place.longitude == 0)) {
      _selectionGeneration = generation;
      setState(() => _searching = true);
      Destination? resolved;
      try {
        resolved = await GoogleMapsService.instance
            .resolveDestination(place, sessionToken: token);
      } catch (_) {}
      if (!mounted || generation != _generation) return;
      _selectionGeneration = null;
      if (resolved == null) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not load this place. Try again.')));
        return;
      }
      place = resolved;
    }
    _remember(place);
    setState(() {
      if (_searchFrom) {
        _origin = place;
        _from.text = place.displayTitle;
      } else {
        _destination = place;
        _to.text = place.displayTitle;
      }
      _results = [];
      _query = '';
      _searching = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _currentOrigin() {
    _debounce?.cancel();
    ++_generation;
    _sessionToken = null;
    setState(() {
      _origin = null;
      _from.text = _current;
      _results = [];
      _query = '';
      _searching = false;
      _searchFrom = false;
    });
    _toFocus.requestFocus();
  }

  Destination _typed(String text) => Destination(
      name: text, address: text, rawQuery: text, latitude: 0, longitude: 0);
  Future<void> _preview() async {
    if (_opening || _selectionGeneration == _generation) return;
    final query = _to.text.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    ++_generation;
    _sessionToken = null;
    FocusScope.of(context).unfocus();
    final from = _from.text.trim();
    setState(() {
      _opening = true;
      _searching = false;
    });
    try {
      _remember(_destination ?? _typed(query));
      await DestinationConfirmSheet.show(context, _destination ?? _typed(query),
          startLocation: _origin ??
              (from.isEmpty || from == _current ? null : _typed(from)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plan a ride'), actions: [
          IconButton(
              tooltip: 'Ride tools',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const RideToolsScreen()))),
        ]),
        body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Expanded(
                              child: Column(children: [
                            TextField(
                                controller: _from,
                                focusNode: _fromFocus,
                                textInputAction: TextInputAction.next,
                                style: AppTextStyles.bodyLarge,
                                decoration: InputDecoration(
                                    labelText: 'From',
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    prefixIcon:
                                        const Icon(Icons.trip_origin, size: 20),
                                    suffixIcon: IconButton(
                                        tooltip: 'Use current location',
                                        onPressed: _currentOrigin,
                                        icon: const Icon(
                                            Icons.my_location_outlined,
                                            size: 20))),
                                onTap: () {
                                  _focusField(true);
                                  if (_from.text == _current)
                                    _from.selection = TextSelection(
                                        baseOffset: 0,
                                        extentOffset: _from.text.length);
                                },
                                onChanged: (value) =>
                                    _search(value, from: true),
                                onSubmitted: (value) {
                                  if (_origin != null ||
                                      value.trim() == _current ||
                                      value.trim().isEmpty) {
                                    _focusField(false);
                                    _toFocus.requestFocus();
                                  } else {
                                    _search(value, from: true, submit: true);
                                  }
                                }),
                            const Divider(indent: 48),
                            TextField(
                                controller: _to,
                                onTap: () => _focusField(false),
                                focusNode: _toFocus,
                                textInputAction: TextInputAction.search,
                                style: AppTextStyles.bodyLarge,
                                decoration: InputDecoration(
                                    labelText: 'Destination',
                                    hintText: 'Search for a place',
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    prefixIcon: const Icon(
                                        Icons.location_on_outlined,
                                        size: 22),
                                    suffixIcon: _to.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear destination',
                                            onPressed: () {
                                              _to.clear();
                                              _search('', from: false);
                                            },
                                            icon: const Icon(
                                                Icons.close_rounded,
                                                size: 20))),
                                onChanged: (value) =>
                                    _search(value, from: false),
                                onSubmitted: (value) {
                                  if (_destination != null ||
                                      value.contains('://')) {
                                    _preview();
                                  } else {
                                    _search(value, from: false, submit: true);
                                  }
                                }),
                          ])),
                          IconButton(
                              tooltip: 'Swap starting point and destination',
                              icon: const Icon(Icons.swap_vert_rounded),
                              onPressed: _to.text.trim().isEmpty
                                  ? null
                                  : () {
                                      _debounce?.cancel();
                                      ++_generation;
                                      _sessionToken = null;
                                      setState(() {
                                        final text = _from.text;
                                        final location = _origin;
                                        _from.text = _to.text;
                                        _origin = _destination;
                                        _to.text = text == _current ? '' : text;
                                        _destination = location;
                                        _results = [];
                                        _query = '';
                                        _searching = false;
                                      });
                                    }),
                        ])),
                  )),
              Expanded(
                  child: _searching
                      ? const Center(child: CircularProgressIndicator())
                      : _results.isNotEmpty
                          ? ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _results.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(indent: 52),
                              itemBuilder: (context, index) {
                                final place = _results[index];
                                return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    leading:
                                        const Icon(Icons.location_on_outlined),
                                    title: Text(place.displayTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: place.address?.isNotEmpty ==
                                                true &&
                                            place.address != place.displayTitle
                                        ? Text(place.address!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis)
                                        : null,
                                    onTap: () => _choose(place));
                              })
                          : _query.isEmpty && _recent.isNotEmpty
                              ? ListView(children: [
                                  ListTile(
                                      title: const Text('Recent searches'),
                                      trailing: TextButton(
                                        onPressed: _clearRecent,
                                        child: const Text('Clear all'),
                                      )),
                                  for (final place in _recent)
                                    ListTile(
                                        leading: const Icon(Icons.history),
                                        title: Text(place.displayTitle),
                                        trailing: IconButton(
                                          tooltip: 'Delete recent search',
                                          icon: const Icon(Icons.close),
                                          onPressed: () => _removeRecent(place),
                                        ),
                                        onTap: () => _choose(place)),
                                ])
                              : Center(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                _query.length >= 2
                                                    ? Icons.search_off_rounded
                                                    : Icons.route_outlined,
                                                size: 36,
                                                color: AppColors.textMuted),
                                            const SizedBox(height: 16),
                                            Text(
                                                _query.length >= 2
                                                    ? 'No places found'
                                                    : 'Choose your destination',
                                                style:
                                                    AppTextStyles.headingMedium,
                                                textAlign: TextAlign.center),
                                            const SizedBox(height: 8),
                                            Text(
                                                _query.length >= 2
                                                    ? 'Try another address or check your connection.'
                                                    : 'Preview the route before starting your ride.',
                                                style: AppTextStyles.bodyMedium,
                                                textAlign: TextAlign.center),
                                          ])))),
              Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20,
                      MediaQuery.viewInsetsOf(context).bottom > 0 ? 12 : 20),
                  child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed: _opening ||
                                  _selectionGeneration == _generation ||
                                  _to.text.trim().isEmpty
                              ? null
                              : _preview,
                          icon: _opening
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.route_outlined, size: 20),
                          label: Text(_opening
                              ? 'Opening preview…'
                              : 'Preview route')))),
            ])),
      );
}
