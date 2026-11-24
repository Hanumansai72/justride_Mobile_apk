import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/utils/user_facing_error.dart';

class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key});
  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _label = TextEditingController(text: 'Home'),
      _address = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  String _query = '';
  String? _sessionToken;
  Destination? _selected;
  List<Destination> _results = [];
  bool _searching = false, _saving = false, _locating = false;
  String? _error;
  @override
  void dispose() {
    _debounce?.cancel();
    _label.dispose();
    _address.dispose();
    super.dispose();
  }

  void _search(String value, {bool submit = false}) {
    final query = value.trim();
    if (!submit && query.isNotEmpty && query == _query) return;
    _debounce?.cancel();
    if (submit || query.length < 2) _sessionToken = null;
    final generation = ++_generation;
    setState(() {
      _query = query;
      _selected = null;
      _results = [];
      _error = null;
      _searching = query.length >= 2;
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
          setState(() {
            _results = results;
            if (results.isEmpty)
              _error =
                  'No places found. Try another address or check your connection.';
          });
      } catch (_) {
        if (mounted && generation == _generation)
          setState(() => _error =
              'Search is unavailable. Check your connection and try again.');
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

  void _choose(Destination place) {
    _debounce?.cancel();
    ++_generation;
    setState(() {
      _selected = place;
      _query = '';
      _address.text = place.displayTitle;
      _results = [];
      _searching = false;
      _error = null;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _currentLocation() async {
    if (_locating || _saving) return;
    _debounce?.cancel();
    _sessionToken = null;
    final generation = ++_generation;
    setState(() {
      _locating = true;
      _error = null;
      _searching = false;
    });
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (!mounted || generation != _generation) return;
      if (position == null) {
        setState(() => _error =
            'Your location is unavailable. Turn on location access and try again.');
        return;
      }
      _choose(Destination(
          name: 'Current location',
          address: 'Current location',
          latitude: position.latitude,
          longitude: position.longitude));
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Your location is unavailable. Turn on location access and try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for this place.');
      return;
    }
    if (_selected == null) {
      setState(() =>
          _error = 'Choose a search result or use your current location.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var place = _selected!;
      if (place.latitude == 0 && place.longitude == 0) {
        final token = _sessionToken;
        _sessionToken = null;
        final resolved = await GoogleMapsService.instance
            .resolveDestination(place, sessionToken: token);
        if (resolved == null ||
            (resolved.latitude == 0 && resolved.longitude == 0)) {
          if (mounted)
            setState(() => _error =
                'We couldn’t find this place. Choose another search result.');
          return;
        }
        place = resolved;
        _selected = resolved;
      }
      final result = await BackendService.instance.createSavedAddress(
          label: _label.text.trim(),
          address: place.address?.isNotEmpty == true &&
                  place.address != place.displayTitle
              ? place.address!
              : place.displayTitle,
          latitude: place.latitude,
          longitude: place.longitude);
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = userFacingError(result.message,
            fallback: 'This place couldn’t be saved. Please try again.'));
      }
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'This place couldn’t be saved. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Add saved place')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final name in ['Home', 'Work', 'Gym', 'Cafe', 'Other'])
                  ChoiceChip(
                      label: Text(name),
                      selected: _label.text == name,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _label.text = name))
              ]),
              const SizedBox(height: 24),
              TextField(
                  controller: _label,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Place name'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 20),
              TextField(
                  controller: _address,
                  enabled: !_saving && !_locating,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                      labelText: 'Address',
                      hintText: 'Search for a place',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : _selected == null
                              ? null
                              : const Icon(Icons.check_circle_outline,
                                  color: AppColors.primary)),
                  onChanged: (value) {
                    if (_selected != null) _sessionToken = null;
                    _search(value);
                  },
                  onSubmitted: (value) {
                    if (_selected == null) _search(value, submit: true);
                  }),
              for (final place in _results)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(place.displayTitle,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: place.address?.isNotEmpty == true &&
                            place.address != place.displayTitle
                        ? Text(place.address!,
                            maxLines: 2, overflow: TextOverflow.ellipsis)
                        : null,
                    onTap: () => _choose(place)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  onPressed: _saving || _locating ? null : _currentLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_outlined, size: 18),
                  label: Text(_locating
                      ? 'Finding your location…'
                      : 'Use current location')),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                    liveRegion: true,
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.errorLight, height: 1.45)))
              ],
              const SizedBox(height: 28),
              FilledButton(
                  onPressed: _saving || _locating ? null : _save,
                  child: Text(_saving ? 'Saving place…' : 'Save place')),
            ]),
      );
}
