import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../app/app.dart';
import '../../core/routes/app_routes.dart';
import '../../features/navigation/widgets/destination_confirm_sheet.dart';
import '../models/destination.dart';
import '../utils/maps_url_parser.dart';
import 'google_maps_service.dart';

/// Handles incoming shares from Google Maps and other applications.
/// Features dual-channel native intent capture, deduplication, and
/// high-accuracy coordinate resolution.
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  static const MethodChannel _nativeShareChannel =
      MethodChannel('com.justride.app/share_intent');

  StreamSubscription<List<SharedMediaFile>>? _intentSub;
  final ValueNotifier<Destination?> destinationSharedNotifier =
      ValueNotifier<Destination?>(null);

  Destination? currentSharedStartLocation;

  String? _lastProcessedPayload;
  DateTime? _lastProcessedTime;
  bool _isConfirmSheetOpen = false;

  /// Initializes the share intent listener for both running app and cold-start.
  void init() {
    _intentSub?.cancel();

    // 1. Listen via receive_sharing_intent plugin stream while app is in memory
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _processSharedFile(value.first);
        }
      },
      onError: (err) {
        debugPrint('[ShareService] getMediaStream error: $err');
      },
    );

    // 2. Process initial share from receive_sharing_intent (cold-start)
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _processSharedFile(value.first);
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((err) {
      debugPrint('[ShareService] getInitialMedia error: $err');
    });

    // 3. Fail-safe Native MethodChannel bridge for Android onNewIntent / cold start
    _initNativeShareChannel();
  }

  void _initNativeShareChannel() {
    _nativeShareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedTextReceived') {
        final text = call.arguments?.toString();
        if (text != null && text.trim().isNotEmpty) {
          debugPrint('[ShareService] Received shared text from native channel: $text');
          await handleSharedText(text.trim());
        }
      }
    });

    // Check for cold-start initial payload from native MainActivity
    _nativeShareChannel
        .invokeMethod<String>('getInitialSharedText')
        .then((payload) {
      if (payload != null && payload.trim().isNotEmpty) {
        debugPrint('[ShareService] Retrieved initial text from native channel: $payload');
        handleSharedText(payload.trim());
      }
    }).catchError((err) {
      debugPrint('[ShareService] getInitialSharedText error: $err');
    });
  }

  Future<void> _processSharedFile(SharedMediaFile file) async {
    final text = file.path.trim();
    if (text.isEmpty) return;

    debugPrint('[ShareService] Received shared content: $text');
    await handleSharedText(text);
  }

  /// Parses shared text/URL, resolves coordinates, and emits to listeners.
  Future<Destination?> handleSharedText(String text) async {
    final now = DateTime.now();
    if (_lastProcessedPayload == text &&
        _lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inSeconds < 4) {
      debugPrint('[ShareService] Ignoring duplicate share payload within 4s.');
      return destinationSharedNotifier.value;
    }
    _lastProcessedPayload = text;
    _lastProcessedTime = now;

    try {
      final parsed = await MapsUrlParser.parseSharedContent(text);
      if (parsed == null) {
        debugPrint('[ShareService] Could not parse destination from text.');
        return null;
      }

      var dest = parsed.destination;
      var start = parsed.startLocation;

      // If coordinates are missing (0,0), resolve them using Google Maps Places/Geocoding
      if (dest.latitude == 0.0 && dest.longitude == 0.0) {
        final resolved = await GoogleMapsService.instance.resolveDestination(dest);
        if (resolved != null && resolved.latitude != 0.0) {
          dest = resolved;
        }
      }

      // If start coordinates are missing (0,0), resolve them as well
      if (start != null && start.latitude == 0.0 && start.longitude == 0.0) {
        final resolvedStart = await GoogleMapsService.instance.resolveDestination(start);
        if (resolvedStart != null && resolvedStart.latitude != 0.0) {
          start = resolvedStart;
        }
      }

      currentSharedStartLocation = start;
      destinationSharedNotifier.value = dest;
      debugPrint(
          '[ShareService] Successfully resolved shared destination: ${dest.displayTitle} (${dest.latitude}, ${dest.longitude})'
          '${start != null ? " with start: ${start.displayTitle} (${start.latitude}, ${start.longitude})" : ""}');

      // Attempt to immediately display confirmation sheet if navigator context is available
      tryPresentSharedDestination();

      return dest;
    } catch (e) {
      debugPrint('[ShareService] Error parsing shared text: $e');
      return null;
    }
  }

  /// Presents the destination confirmation sheet on top of whatever screen the user is on.
  /// If the app is currently on the splash screen, defers until navigation to dashboard occurs.
  void tryPresentSharedDestination([BuildContext? context]) {
    final dest = destinationSharedNotifier.value;
    if (dest == null) return;

    final targetContext = context ?? appNavigatorKey.currentContext;
    if (targetContext == null) return;

    // Do not show bottom sheet over splash screen; wait for dashboard to mount
    final route = ModalRoute.of(targetContext);
    if (route != null && route.settings.name == AppRoutes.splash) {
      debugPrint('[ShareService] App on splash screen, holding shared destination until dashboard.');
      return;
    }

    // If a confirm sheet is currently open from a previous share, pop it first to present fresh location
    if (_isConfirmSheetOpen) {
      try {
        Navigator.of(targetContext, rootNavigator: true).pop();
      } catch (_) {}
      _isConfirmSheetOpen = false;
    }

    _isConfirmSheetOpen = true;
    final startLoc = currentSharedStartLocation;
    clearSharedDestination();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await DestinationConfirmSheet.show(
          targetContext,
          dest,
          startLocation: startLoc,
        );
      } finally {
        _isConfirmSheetOpen = false;
      }
    });
  }

  /// Clears current shared destination after user has acted on it
  void clearSharedDestination() {
    destinationSharedNotifier.value = null;
    currentSharedStartLocation = null;
  }

  void dispose() {
    _intentSub?.cancel();
  }
}
