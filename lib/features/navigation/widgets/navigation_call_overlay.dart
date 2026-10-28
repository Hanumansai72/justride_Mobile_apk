import '../../../app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../core/services/telephony_service.dart';

/// Floating call overlay card displayed at the bottom of the navigation screen
/// when an incoming phone call is ringing or active during a ride.
///
/// Features:
/// - Distinct caller avatar with animated ringing pulse
/// - Caller ID / Name display
/// - "Lift Call" (Answer) button in emerald green
/// - "Reject Call" (Hang Up) button in vivid red
/// - Automatic state sync with native Android telephony
class NavigationCallOverlay extends StatefulWidget {
  final IncomingCallInfo callInfo;

  const NavigationCallOverlay({
    super.key,
    required this.callInfo,
  });

  @override
  State<NavigationCallOverlay> createState() => _NavigationCallOverlayState();
}

class _NavigationCallOverlayState extends State<NavigationCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  bool _isActionInProgress = false;

  // Obsidian HUD Palette
  static const Color _cardBg = AppColors.backgroundInset;
  static const Color _border = AppColors.border;
  static const Color _primary = AppColors.primary;
  static const Color _onPrimary = AppColors.onPrimary;
  static const Color _red = AppColors.error;
  static const Color _textPrimary = AppColors.textPrimary;
  static const Color _textSecondary = AppColors.textSecondary;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleAnswer() async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);
    await TelephonyService.instance.answerCall();
    if (mounted) setState(() => _isActionInProgress = false);
  }

  Future<void> _handleReject() async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);
    await TelephonyService.instance.rejectCall();
    if (mounted) setState(() => _isActionInProgress = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.callInfo;
    final isRinging = info.isRinging;
    final isOffhook = info.isOffhook;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRinging ? _primary : _border,
          width: isRinging ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          if (isRinging)
            BoxShadow(
              color: _primary.withValues(alpha: 0.25),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Caller Icon, Name, and Status Badge
          Row(
            children: [
              // Ringing Animated Phone Icon
              AnimatedBuilder(
                animation: _pulseScale,
                builder: (context, child) {
                  return Transform.scale(
                    scale: isRinging ? _pulseScale.value : 1.0,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isOffhook
                            ? _primary.withValues(alpha: 0.2)
                            : _primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _primary,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        isOffhook
                            ? Icons.phone_in_talk_rounded
                            : Icons.phone_callback_rounded,
                        color: _primary,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),

              // Caller Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            info.displayName,
                            style: TextStyle(
                              fontFamily: 'Stack Sans Text',
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOffhook
                                ? _primary.withValues(alpha: 0.15)
                                : AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isOffhook ? 'IN CALL' : 'INCOMING',
                            style: TextStyle(
                              fontFamily: 'Stack Sans Text',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isOffhook ? _primary : AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.callerNumber.isNotEmpty
                          ? info.callerNumber
                          : (isOffhook
                              ? 'Call in progress'
                              : 'Incoming phone call...'),
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: _textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Row 2: Reject Button and Lift Call Button
          Row(
            children: [
              // Reject Button (Red)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isActionInProgress ? null : _handleReject,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.call_end_rounded, size: 20),
                  label: Text(
                    isOffhook ? 'END CALL' : 'REJECT',
                    style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),

              if (isRinging) ...[
                const SizedBox(width: 12),
                // Lift Call Button (Green)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isActionInProgress ? null : _handleAnswer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: _onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.call_rounded, size: 20),
                    label: Text(
                      'LIFT CALL',
                      style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
