import '../../../shared/widgets/device_connection_gate.dart';
import '../../../app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import 'support_ticket_screen.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const cardHover = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const tertiary = AppColors.primary;
  static const secondary = AppColors.primary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const outlineVariant = AppColors.border;
  static const error = AppColors.errorLight;
}

enum _TicketStatus { inProgress, open, closed }

class _Ticket {
  const _Ticket({
    required this.id,
    required this.createdDate,
    required this.title,
    required this.description,
    required this.status,
    required this.priorityLabel,
    required this.priorityColor,
    required this.priorityIcon,
    this.resolvedDate,
  });

  final String id;
  final String createdDate;
  final String title;
  final String description;
  final _TicketStatus status;
  final String priorityLabel;
  final Color priorityColor;
  final IconData priorityIcon;
  final String? resolvedDate;
}

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  int _selectedFilterIndex = 0;
  final int _navIndex = 3; // Profile tab active
  List<SupportTicketModel> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);
    final res = await BackendService.instance.getMyTickets();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res.success && res.data != null) {
          _tickets = res.data!;
        }
      });
    }
  }

  List<String> get _filterOptions {
    final openCount = _tickets
        .where((t) => t.status != 'CLOSED' && t.status != 'RESOLVED')
        .length;
    final closedCount = _tickets
        .where((t) => t.status == 'CLOSED' || t.status == 'RESOLVED')
        .length;
    return ['All Tickets', 'Open ($openCount)', 'Closed ($closedCount)'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : RefreshIndicator(
              onRefresh: _fetchTickets,
              color: _C.primary,
              backgroundColor: _C.cardBg,
              child: _buildBody(),
            ),
      floatingActionButton: _buildFab(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 3) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/places');
          } else if (i == 2) {
            Navigator.of(context).pushReplacementNamed('/device');
          }
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: _C.bg,
            border: Border(
              bottom: BorderSide(color: _C.outlineVariant, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.primary, size: 24),
              ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              IconButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: _C.primary, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pagePadding,
        AppConstants.spacingLg,
        AppConstants.pagePadding,
        100, // Fab and bottom bar breathing space
      ),
      children: [
        Text(
          'My Tickets',
          style: AppTextStyles.headingLarge.copyWith(
            fontSize: 24,
            color: _C.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Text(
          'Manage and track your support requests.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: _C.textSec,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: AppConstants.spacingLg),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_filterOptions.length, (index) {
              final isSelected = _selectedFilterIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: AppConstants.spacingSm),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedFilterIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _C.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? _C.primary : _C.outlineVariant,
                      ),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusCircle),
                    ),
                    child: Text(
                      _filterOptions[index],
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: isSelected ? _C.primary : _C.textSec,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: AppConstants.spacingLg),

        if (_tickets.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.confirmation_number_outlined,
                      color: _C.textSec, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No support tickets found',
                    style: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: _C.textSec,
                        fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // Tickets list
          ..._tickets.where((ticket) {
            if (_selectedFilterIndex == 1) {
              return ticket.status != 'CLOSED' && ticket.status != 'RESOLVED';
            } else if (_selectedFilterIndex == 2) {
              return ticket.status == 'CLOSED' || ticket.status == 'RESOLVED';
            }
            return true;
          }).map((ticket) {
            final isClosed =
                ticket.status == 'CLOSED' || ticket.status == 'RESOLVED';
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
              child: _TicketCard(
                ticket: _Ticket(
                  id: ticket.ticketNumber,
                  title: ticket.title,
                  description: ticket.category,
                  status: isClosed
                      ? _TicketStatus.closed
                      : _TicketStatus.inProgress,
                  createdDate: 'OCT 2023',
                  priorityLabel: ticket.status,
                  priorityColor: isClosed ? _C.textSec : _C.primary,
                  priorityIcon: isClosed
                      ? Icons.check_circle_rounded
                      : Icons.pending_actions_rounded,
                  resolvedDate: '',
                ),
                onTap: () {
                  Navigator.of(context).push(
                    DevicePageRoute(
                      builder: (context) => SupportTicketScreen(
                        ticketId: ticket.id,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushNamed('/help');
        },
        backgroundColor: _C.primary,
        foregroundColor: _C.onPrimary,
        shape: const CircleBorder(),
        elevation: 6,
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

class _TicketCard extends StatefulWidget {
  const _TicketCard({
    required this.ticket,
    required this.onTap,
  });

  final _Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<_TicketCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final isClosed = t.status == _TicketStatus.closed;

    Color topBarColor = Colors.transparent;
    if (t.status == _TicketStatus.inProgress) {
      topBarColor = _C.tertiary;
    } else if (t.status == _TicketStatus.open) {
      topBarColor = _C.primary;
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedOpacity(
        duration: AppConstants.animNormal,
        opacity: isClosed && !_hovered ? 0.75 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered ? _C.cardHover : _C.cardBg,
            border: Border.all(color: _C.cardBorder),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (topBarColor != Colors.transparent)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 3,
                  child: Container(color: topBarColor),
                ),
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: ID + Status badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.id,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: _C.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.createdDate,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: _C.textSec,
                              ),
                            ),
                          ],
                        ),
                        _buildStatusBadge(t.status),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // Title & Description
                    Text(
                      t.title,
                      style: AppTextStyles.headingSmall.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isClosed ? _C.textSec : _C.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.description,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 14,
                        color: _C.textSec,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // Bottom info & Chevron
                    Container(
                      padding:
                          const EdgeInsets.only(top: AppConstants.spacingSm),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _C.cardBorder, width: 1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                t.priorityIcon,
                                color: t.priorityColor,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.priorityLabel,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: t.priorityColor,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _hovered ? _C.primary : _C.textSec,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(_TicketStatus status) {
    if (status == _TicketStatus.inProgress) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _C.tertiary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'In Progress',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: _C.tertiary,
            ),
          ),
        ],
      );
    } else if (status == _TicketStatus.open) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _C.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Open',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: _C.primary,
            ),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: _C.textSec,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            'Closed',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: _C.textSec,
            ),
          ),
        ],
      );
    }
  }
}
