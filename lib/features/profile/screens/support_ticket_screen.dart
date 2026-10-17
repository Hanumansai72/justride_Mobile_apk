import '../../../app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const surfCont = AppColors.surface;
  static const surfContLowest = AppColors.background;
  static const surfContLow = AppColors.backgroundInset;
  static const surfContHigh = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const primaryCont = AppColors.primary;
  static const onPrimaryCont = AppColors.primaryContainer;
  static const secondary = AppColors.primary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const outlineVariant = AppColors.border;
  static const tertiary = AppColors.primary;
}

class SupportTicketScreen extends StatefulWidget {
  final String? initialCategory;
  final String? ticketId;

  const SupportTicketScreen({
    super.key,
    this.initialCategory,
    this.ticketId,
  });

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();

  SupportTicketModel? _ticket;
  bool _isLoading = true;
  bool _isSending = false;

  // Bot guided questionnaire state (when creating a new ticket)
  int _questionStep = 0; // 0: Asking main problem summary, 1: Asking details, 2: Ticket created
  String _selectedCategory = 'contact_support';
  String _problemTitle = '';
  final List<_ChatMessageItem> _chatItems = [];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'contact_support';
    _initChat();
  }

  Future<void> _initChat() async {
    if (widget.ticketId != null && widget.ticketId!.isNotEmpty) {
      // Existing Ticket Mode: Load from backend
      setState(() => _isLoading = true);
      final res = await BackendService.instance.getTicketDetails(widget.ticketId!);
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (res.success && res.data != null) {
            _ticket = res.data;
            _chatItems.clear();
            for (final msg in _ticket!.messages) {
              _chatItems.add(
                _ChatMessageItem(
                  isUser: msg.senderRole == 'USER',
                  sender: msg.senderName,
                  time: _formatTime(msg.createdAt),
                  text: msg.body,
                ),
              );
            }
          }
        });
      }
    } else {
      // Guided Interactive Assistant Mode: Start conversational ticket creation
      setState(() {
        _isLoading = false;
        _chatItems.add(
          _ChatMessageItem(
            isUser: false,
            sender: 'JustRide Assistant',
            time: 'Just now',
            text: _getWelcomeQuestion(_selectedCategory),
          ),
        );
      });
    }
  }

  String _getWelcomeQuestion(String category) {
    if (category == 'device_problem') {
      return "Hello! I am your JustRide Support Assistant 🤖.\n\nCould you briefly tell me what issue you are experiencing with your JustRide hardware device?";
    } else if (category == 'connection_issue') {
      return "Hello! I am your JustRide Support Assistant 🤖.\n\nCould you describe what happens when attempting to pair or connect with Bluetooth/Cloud?";
    } else if (category == 'firmware_problem') {
      return "Hello! I am your JustRide Support Assistant 🤖.\n\nAre you having issues updating firmware or seeing a version mismatch error?";
    } else {
      return "Hello! I am your JustRide Support Assistant 🤖.\n\nHow can we assist you today? Please describe the problem or question you have.";
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  Future<void> _handleSendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    _msgController.clear();

    // 1. If in existing ticket mode -> Call backend /api/support/tickets/:id/messages
    if (_ticket != null) {
      setState(() {
        _isSending = true;
        _chatItems.add(
          _ChatMessageItem(
            isUser: true,
            sender: 'You',
            time: 'Just now',
            text: text,
          ),
        );
      });
      _scrollToBottom();

      final res = await BackendService.instance.sendTicketMessage(
        ticketId: _ticket!.id,
        message: text,
      );

      if (mounted) {
        setState(() => _isSending = false);
        if (!res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
      return;
    }

    // 2. Interactive Guided Flow: Collect answers and create ticket in backend
    setState(() {
      _chatItems.add(
        _ChatMessageItem(
          isUser: true,
          sender: 'You',
          time: 'Just now',
          text: text,
        ),
      );
      _isSending = true;
    });
    _scrollToBottom();

    if (_questionStep == 0) {
      _problemTitle = text;
      _questionStep = 1;
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _isSending = false;
          _chatItems.add(
            const _ChatMessageItem(
              isUser: false,
              sender: 'JustRide Assistant',
              time: 'Just now',
              text: "Got it. Can you provide any extra details or steps you've already tried? Once you reply, I will generate a formal support ticket for our engineering team.",
            ),
          );

        });
        _scrollToBottom();
      }
    } else if (_questionStep == 1) {
      final description = 'Summary: $_problemTitle\nDetails: $text';

      // Call Backend API to create official ticket
      final res = await BackendService.instance.createSupportTicket(
        subject: _problemTitle,
        message: description,
        category: _selectedCategory,
        priority: 'high',
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          if (res.success && res.data != null) {
            _ticket = res.data;
            _questionStep = 2;
            _chatItems.add(
              _ChatMessageItem(
                isUser: false,
                sender: 'JustRide Support',
                time: 'Just now',
                text: "✅ Support Ticket #${_ticket!.ticketNumber} created successfully!\n\nOur team has received your logs and is investigating. You can reply directly in this chat anytime for updates.",
              ),
            );
          } else {
            _chatItems.add(
              _ChatMessageItem(
                isUser: false,
                sender: 'JustRide Assistant',
                time: 'Just now',
                text: "Failed to create ticket: ${res.message}. Please try typing your message again.",
              ),
            );
          }
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : Stack(
              children: [
                // ── Messages ─────────────────────────────────────────────────
                ListView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingMd,
                    AppConstants.spacingMd,
                    AppConstants.spacingMd,
                    120, // room for sticky input
                  ),
                  children: [
                    // Diagnostic context card
                    _DiagnosticCard(
                      category: _selectedCategory,
                      ticketNumber: _ticket?.ticketNumber ?? 'PENDING',
                    ),
                    const SizedBox(height: AppConstants.spacingLg),

                    // Date divider
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingMd,
                          vertical: AppConstants.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: _C.surfContLow,
                          border: Border.all(color: _C.outlineVariant),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusCircle),
                        ),
                        child: Text(
                          'Today',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: _C.textSec,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingLg),

                    // Chat messages
                    ..._chatItems.map((msg) => Padding(
                          padding: const EdgeInsets.only(
                              bottom: AppConstants.spacingLg),
                          child: _ChatBubble(message: msg),
                        )),
                  ],
                ),

                // ── Sticky input bar ─────────────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _StickyInputBar(
                    controller: _msgController,
                    isSending: _isSending,
                    onSend: _handleSendMessage,
                  ),
                ),
              ],
            ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final ticketNum = _ticket != null ? '#${_ticket!.ticketNumber}' : 'New Ticket';
    final status = _ticket != null ? _ticket!.status : 'CHATBOT ACTIVE';

    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 64,
          color: _C.surfContLowest,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: _C.onSurface),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Ticket $ticketNum',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _C.onSurface,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _C.secondary.withValues(alpha: 0.1),
                        border: Border.all(
                            color: _C.secondary.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusCircle),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: _C.secondary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            status,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: _C.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pushNamed('/my-tickets'),
                icon: const Icon(Icons.confirmation_number_outlined, color: _C.textSec),
                tooltip: 'My Tickets',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Diagnostic Context Card ────────────────────────────────────────────────────
class _DiagnosticCard extends StatelessWidget {
  final String category;
  final String ticketNumber;

  const _DiagnosticCard({
    required this.category,
    required this.ticketNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: _C.surfCont.withValues(alpha: 0.6),
        border: Border.all(color: _C.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE SUPPORT CHAT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _C.primary,
                ),
              ),
              Text(
                ticketNumber,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _C.textSec,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: _C.textSec, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.replaceAll('_', ' ').toUpperCase(),
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: _C.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Service Channel',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: _C.textSec, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real-time Chat',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: _C.tertiary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Chat Bubble ────────────────────────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final _ChatMessageItem message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender + time
            Padding(
              padding: EdgeInsets.only(
                left: isUser ? 0 : 4,
                right: isUser ? 4 : 0,
                bottom: 4,
              ),
              child: Text(
                '${message.sender} • ${message.time}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _C.textSec,
                ),
              ),
            ),
            // Bubble
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: isUser ? _C.primaryCont : _C.surfCont,
                border: Border.all(
                  color: isUser
                      ? _C.primary.withValues(alpha: 0.3)
                      : _C.outlineVariant,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: isUser
                    ? [
                        BoxShadow(
                          color: _C.primary.withValues(alpha: 0.12),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                message.text,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isUser ? _C.onPrimaryCont : _C.onSurface,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky Input Bar ──────────────────────────────────────────────────────────
class _StickyInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _StickyInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  State<_StickyInputBar> createState() => _StickyInputBarState();
}

class _StickyInputBarState extends State<_StickyInputBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        decoration: BoxDecoration(
          color: _C.surfCont.withValues(alpha: 0.95),
          border: const Border(
            top: BorderSide(color: _C.outlineVariant, width: 1),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppConstants.spacingMd,
          AppConstants.spacingMd,
          AppConstants.spacingMd,
          MediaQuery.of(context).padding.bottom + AppConstants.spacingMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Text input
            Expanded(
              child: Focus(
                onFocusChange: (v) => setState(() => _focused = v),
                child: AnimatedContainer(
                  duration: AppConstants.animFast,
                  constraints:
                      const BoxConstraints(minHeight: 48, maxHeight: 120),
                  decoration: BoxDecoration(
                    color: _C.surfContHigh,
                    border: Border.all(
                      color: _focused ? _C.primary : _C.outlineVariant,
                      width: _focused ? 1.5 : 1,
                    ),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusLg),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: _C.onSurface, fontSize: 15),
                    cursorColor: _C.primary,
                    decoration: InputDecoration(
                      hintText: 'Answer questions or type message...',
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: _C.textSec.withValues(alpha: 0.5),
                          fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingMd,
                        vertical: AppConstants.spacingMd,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),

            // Send button
            GestureDetector(
              onTap: widget.isSending ? null : widget.onSend,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.primary,
                  boxShadow: [
                    BoxShadow(
                      color: _C.primary.withValues(alpha: 0.3),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: widget.isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: _C.onPrimary,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: _C.onPrimary, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class _ChatMessageItem {
  final bool isUser;
  final String sender;
  final String time;
  final String text;

  const _ChatMessageItem({
    required this.isUser,
    required this.sender,
    required this.time,
    required this.text,
  });
}
