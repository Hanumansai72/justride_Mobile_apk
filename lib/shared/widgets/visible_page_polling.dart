import 'dart:async';
import 'package:flutter/material.dart';

final visiblePageObserver = RouteObserver<ModalRoute<dynamic>>();

/// Poll only the visible route while the phone app is foregrounded.
mixin VisiblePagePolling<T extends StatefulWidget> on State<T> implements RouteAware {
  Timer? _visibleTimer;
  AppLifecycleListener? _lifecycle;
  ModalRoute<dynamic>? _observedRoute;
  bool _foreground = true, _polling = false;
  Duration get visiblePollInterval => const Duration(seconds: 20);
  Future<void> pollVisiblePage();

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      _updatePolling(immediate: _foreground);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _observedRoute) {
      visiblePageObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) visiblePageObserver.subscribe(this, route);
    }
  }

  Future<void> _poll() async {
    if (!mounted || !_foreground || _observedRoute?.isCurrent != true || _polling) return;
    _polling = true;
    try { await pollVisiblePage(); } finally { _polling = false; }
  }

  void _updatePolling({bool immediate = false}) {
    _visibleTimer?.cancel();
    _visibleTimer = null;
    if (!mounted || !_foreground || _observedRoute?.isCurrent != true) return;
    if (immediate) unawaited(_poll());
    _visibleTimer = Timer.periodic(visiblePollInterval, (_) => unawaited(_poll()));
  }

  @override
  void didPush() => _updatePolling();
  @override
  void didPopNext() => _updatePolling(immediate: true);
  @override
  void didPushNext() => _updatePolling();
  @override
  void didPop() { _visibleTimer?.cancel(); }

  @override
  void dispose() {
    _visibleTimer?.cancel();
    _lifecycle?.dispose();
    visiblePageObserver.unsubscribe(this);
    super.dispose();
  }
}
