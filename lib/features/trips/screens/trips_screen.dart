import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/navigation_session.dart';
import '../../../core/services/ride_history_service.dart';
import '../widgets/ride_history_card.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});
  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final _history = RideHistoryService.instance;
  final List<NavigationSession> _rides = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _reloadAfterLoad = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _history.changed.addListener(_historyChanged);
    unawaited(_history.syncPending());
    _load(reset: true);
  }

  void _historyChanged() {
    if (_loading) {
      _reloadAfterLoad = true;
    } else {
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _history.changed.removeListener(_historyChanged);
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _history.getPage(page: reset ? 1 : _page + 1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        if (reset) _rides.clear();
        _rides.addAll(result.data!.items);
        _page = result.data!.page;
        _hasMore = result.data!.hasMore;
      } else {
        _error = 'Could not load ride history. Please try again.';
      }
    });
    if (_reloadAfterLoad) {
      _reloadAfterLoad = false;
      unawaited(_load(reset: true));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Ride history')),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            unawaited(_history.syncPending());
            await _load(reset: true);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('Your rides, newest first', style: AppTextStyles.bodyMedium),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(children: [
                    Text(_error!, style: AppTextStyles.bodyMedium),
                    TextButton(
                        onPressed: () => _load(reset: _rides.isEmpty),
                        child: const Text('Try again')),
                  ]),
                ),
              if (!_loading && _error == null && _rides.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(children: [
                    const Icon(Icons.route_outlined,
                        color: AppColors.textMuted, size: 40),
                    const SizedBox(height: 16),
                    Text('No rides yet', style: AppTextStyles.headingSmall),
                    const SizedBox(height: 8),
                    Text('Your rides appear here when navigation ends.',
                        style: AppTextStyles.bodyMedium,
                        textAlign: TextAlign.center),
                  ]),
                ),
              for (final ride in _rides)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RideHistoryCard(ride: ride)),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.primary),
                )),
              if (_hasMore && !_loading && _error == null)
                OutlinedButton(
                    onPressed: _load, child: const Text('Load more')),
            ],
          ),
        ),
      );
}
