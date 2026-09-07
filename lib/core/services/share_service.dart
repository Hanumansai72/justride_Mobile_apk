import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/destination.dart';
import '../utils/maps_url_parser.dart';
import 'google_maps_service.dart';

/// Handles incoming shares from Google Maps and other applications.
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  StreamSubscription<List<SharedMediaFile>>? _intentSub;
  final ValueNotifier<Destination?> destinationSharedNotifier =
      ValueNotifier<Destination?>(null);

  /// Initializes the share intent listener for both running app and cold-start.
  void init() {
    _intentSub?.cancel();

    // 1. Listen for incoming shared text/media while the app is in memory
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

    // 2. Process initial share if the app was launched from a share action
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _processSharedFile(value.first);
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((err) {
      debugPrint('[ShareService] getInitialMedia error: $err');
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
    try {
      final rawDest = await MapsUrlParser.parseSharedText(text);
      if (rawDest == null) {
        debugPrint('[ShareService] Could not parse destination from text.');
        return null;
      }

      // If coordinates are missing (0,0), resolve them using Google Maps Places/Geocoding
      Destination? resolved = rawDest;
      if (rawDest.latitude == 0.0 && rawDest.longitude == 0.0) {
        resolved = await GoogleMapsService.instance.resolveDestination(rawDest);
      }

      final result = resolved ?? rawDest;
      destinationSharedNotifier.value = result;
      debugPrint('[ShareService] Successfully resolved shared destination: ${result.displayTitle} (${result.latitude}, ${result.longitude})');
      return result;
    } catch (e) {
      debugPrint('[ShareService] Error parsing shared text: $e');
      return null;
    }
  }

  /// Clears current shared destination after user has acted on it
  void clearSharedDestination() {
    destinationSharedNotifier.value = null;
  }

  void dispose() {
    _intentSub?.cancel();
  }
}
