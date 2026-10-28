import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/google_maps_service.dart';
import 'destination_confirm_sheet.dart';

/// Modal voice assistant sheet triggered from search bar mic or Devices tab.
class VoiceAssistantSheet extends StatefulWidget {
  const VoiceAssistantSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const VoiceAssistantSheet(),
    );
  }

  @override
  State<VoiceAssistantSheet> createState() => _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends State<VoiceAssistantSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final TextEditingController _textController = TextEditingController();
  bool _isProcessing = false;
  String _statusText = 'Listening for destination...';

  // Popular quick voice destinations
  static const List<String> _quickSuggestions = [
    'Uppal Bus Stop',
    'Uppal Metro Station',
    'Secunderabad Railway Station',
    'HITEC City Cyber Towers',
    'Gachibowli DLF Road',
    'Charminar Old City',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _handleDestinationSelected(String query) async {
    if (query.trim().isEmpty || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Finding "$query"...';
    });

    try {
      final results = await GoogleMapsService.instance.searchPlaces(query);
      if (!mounted) return;

      if (results.isNotEmpty) {
        final chosen = results.first;
        Navigator.of(context).pop(); // Close voice sheet
        // Open confirmation sheet to preview route and start ride
        DestinationConfirmSheet.show(context, chosen);
      } else {
        // Fallback: create raw destination and resolve
        final rawDest = Destination(
          name: query,
          address: query,
          latitude: 0.0,
          longitude: 0.0,
          rawQuery: query,
        );
        final resolved =
            await GoogleMapsService.instance.resolveDestination(rawDest);
        if (!mounted) return;

        if (resolved != null && resolved.latitude != 0.0) {
          Navigator.of(context).pop();
          DestinationConfirmSheet.show(context, resolved);
        } else {
          setState(() {
            _isProcessing = false;
            _statusText = 'Could not locate "$query". Please try again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = 'Error searching place. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.backgroundInset,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Voice Assistant',
                    style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon:
                    const Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Animated Pulsing Mic Visualizer
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow wave
                    Container(
                      width: 90 * _pulseAnimation.value,
                      height: 90 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(
                          alpha: _isProcessing
                              ? 0.08
                              : (0.25 / _pulseAnimation.value),
                        ),
                      ),
                    ),
                    // Inner glowing circle
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: _isProcessing
                          ? const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.onPrimary),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.mic_rounded,
                              color: AppColors.onPrimary,
                              size: 36,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Status / speech text
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color:
                  _isProcessing ? AppColors.primary : AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 20),

          // Quick Voice Suggestion Chips
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'OR TAP A FREQUENT DESTINATION',
              style: TextStyle(
                fontFamily: 'Stack Sans Text',
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.bold,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickSuggestions.map((place) {
              return ActionChip(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                avatar: const Icon(
                  Icons.near_me_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
                label: Text(
                  place,
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: _isProcessing
                    ? null
                    : () => _handleDestinationSelected(place),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Voice query text field alternative
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    color: AppColors.textMuted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textPrimary,
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type place (e.g. Uppal, Charminar)...',
                      hintStyle: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          color: AppColors.textMuted,
                          fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (val) => _handleDestinationSelected(val),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.primary, size: 20),
                  onPressed: () =>
                      _handleDestinationSelected(_textController.text),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
