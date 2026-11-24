import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../app/app.dart';
import '../../core/routes/app_routes.dart';
import '../../features/navigation/widgets/destination_confirm_sheet.dart';
import '../models/destination.dart';
import '../utils/maps_url_parser.dart';

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
  int _shareGeneration = 0;

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
      onError: (err) {},
    );

    // 2. Process initial share from receive_sharing_intent (cold-start)
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _processSharedFile(value.first);
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((err) {});

    // 3. Fail-safe Native MethodChannel bridge for Android onNewIntent / cold start
    _initNativeShareChannel();
  }

  void _initNativeShareChannel() {
    _nativeShareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedTextReceived') {
        final text = call.arguments?.toString();
        if (text != null && text.trim().isNotEmpty) {
          await handleSharedText(text.trim());
        }
      }
    });

    // Check for cold-start initial payload from native MainActivity
    _nativeShareChannel
        .invokeMethod<String>('getInitialSharedText')
        .then((payload) {
      if (payload != null && payload.trim().isNotEmpty) {
        handleSharedText(payload.trim());
      }
    }).catchError((err) {});
  }

  Future<void> _processSharedFile(SharedMediaFile file) async {
    final text = file.path.trim();
    if (text.isEmpty) return;

    await handleSharedText(text);
  }

  /// Opens confirmation immediately; its sheet resolves the exact pin in view.
  Future<Destination?> handleSharedText(String text) async {
    final now = DateTime.now();
    if (_lastProcessedPayload == text &&
        _lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inSeconds < 4) {
      return destinationSharedNotifier.value;
    }
    _lastProcessedPayload = text;
    _lastProcessedTime = now;

    final generation = ++_shareGeneration;
    try {
      final parsed = await MapsUrlParser.parseSharedContent(text,
          resolveShortLinks: false);
      if (generation != _shareGeneration) return null;
      if (parsed == null) {
        _showShareError();
        return null;
      }

      final dest = parsed.destination;
      final start = parsed.startLocation;

      currentSharedStartLocation = start;
      destinationSharedNotifier.value = dest;

      // Attempt to immediately display confirmation sheet if navigator context is available
      tryPresentSharedDestination();

      return dest;
    } catch (_) {
      if (generation == _shareGeneration) _showShareError();
      return null;
    }
  }

  void _showShareError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appMessengerKey.currentState?.showSnackBar(const SnackBar(
        content: Text(
            'Couldn’t read the shared location. Share a place or pin from Maps again.'),
      ));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Presents the destination confirmation sheet on top of whatever screen the user is on.
  /// If the app is currently on the splash screen, defers until navigation to dashboard occurs.
  void tryPresentSharedDestination([BuildContext? context]) {
    final dest = destinationSharedNotifier.value;
    if (dest == null) return;

    final targetContext =
        context ?? appNavigatorKey.currentState?.overlay?.context;
    if (targetContext == null) return;

    // Do not show bottom sheet over splash screen; wait for dashboard to mount
    final route = ModalRoute.of(targetContext);
    if (route != null && route.settings.name == AppRoutes.splash) {
      return;
    }

    final startLoc = currentSharedStartLocation;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!targetContext.mounted ||
          !identical(destinationSharedNotifier.value, dest)) return;
      clearSharedDestination();
      await DestinationConfirmSheet.show(
        targetContext,
        dest,
        startLocation: startLoc,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
