import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive Time-Slider bar for the floor plan / team map screen.
/// Displays the current week's days (Monday to Friday, or with Saturday/Sunday
/// depending on [hideWeekends]), with an animated sliding cursor, short labels
/// ("Lun 19", "Mar 20"...), visual selection indicator, and discrete badges
/// for confirmed or pending desk reservations.
class TimeSliderBar extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool hideWeekends;
  final Set<String> bookedDates;
  final Set<String> pendingDates;
  final bool Function(DateTime date)? hasConfirmedReservation;
  final bool Function(DateTime date)? isPendingReservation;
  final VoidCallback? onPickDate;
  final VoidCallback? onPreviousDay;
  final VoidCallback? onNextDay;
  final VoidCallback? onToday;
  final bool isLoading;

  const TimeSliderBar({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.hideWeekends = true,
    this.bookedDates = const {},
    this.pendingDates = const {},
    this.hasConfirmedReservation,
    this.isPendingReservation,
    this.onPickDate,
    this.onPreviousDay,
    this.onNextDay,
    this.onToday,
    this.isLoading = false,
  });

  @override
  State<TimeSliderBar> createState() => _TimeSliderBarState();
}

class _TimeSliderBarState extends State<TimeSliderBar> {
  int? _lastDraggedIndex;

  DateTime get _monday {
    final d = widget.selectedDate;
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  List<DateTime> get _days {
    final monday = _monday;
    final count = (widget.hideWeekends && widget.selectedDate.weekday <= 5) ? 5 : 7;
    return List.generate(
      count,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  static String formatDateIso(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isConfirmed(DateTime d) {
    if (widget.hasConfirmedReservation != null) {
      return widget.hasConfirmedReservation!(d);
    }
    return widget.bookedDates.contains(formatDateIso(d));
  }

  bool _isPending(DateTime d) {
    if (widget.isPendingReservation != null) {
      return widget.isPendingReservation!(d);
    }
    if (_isConfirmed(d)) return false;
    return widget.pendingDates.contains(formatDateIso(d));
  }

  String _formatShortDay(DateTime d) {
    const shortNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final name = shortNames[d.weekday - 1];
    return '$name ${d.day}';
  }

  String _formatDateFrench(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    const weekdays = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche'
    ];
    const months = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.'
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];

    if (diff == 0) return "Aujourd'hui (${date.day} $month)";
    if (diff == 1) return "Demain (${date.day} $month)";
    if (diff == -1) return "Hier (${date.day} $month)";
    return "$weekday ${date.day} $month";
  }

  void _handleTouch(double dx, double width, List<DateTime> days) {
    if (days.isEmpty || width <= 0) return;
    final slotWidth = width / days.length;
    final rawIndex = (dx / slotWidth).floor();
    final index = rawIndex.clamp(0, days.length - 1);
    final targetDate = days[index];

    if (_lastDraggedIndex != index || !isSameDay(targetDate, widget.selectedDate)) {
      _lastDraggedIndex = index;
      HapticFeedback.selectionClick();
      widget.onDateSelected(targetDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final days = _days;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isTodaySelected = isSameDay(widget.selectedDate, today);

    final isCurrentSelectedConfirmed = _isConfirmed(widget.selectedDate);
    final isCurrentSelectedPending = _isPending(widget.selectedDate);

    final selectedIndex = days.indexWhere((d) => isSameDay(d, widget.selectedDate));
    final activeIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Top Navigation Bar (compatible with date navigation test specs)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: "Jour précédent",
                  onPressed: widget.onPreviousDay ??
                      () => widget.onDateSelected(
                            widget.selectedDate.subtract(const Duration(days: 1)),
                          ),
                ),
                Flexible(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onPickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _formatDateFrench(widget.selectedDate),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentSelectedConfirmed) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline, size: 11, color: Colors.green),
                                  SizedBox(width: 3),
                                  Text(
                                    "Votre bureau",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (isCurrentSelectedPending) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule, size: 11, color: Colors.blue),
                                  SizedBox(width: 3),
                                  Text(
                                    "En attente",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isTodaySelected)
                      TextButton(
                        onPressed: widget.onToday ??
                            () => widget.onDateSelected(DateTime.now()),
                        child: const Text("Aujourd'hui", style: TextStyle(fontSize: 12)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: "Jour suivant",
                      onPressed: widget.onNextDay ??
                          () => widget.onDateSelected(
                                widget.selectedDate.add(const Duration(days: 1)),
                              ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Interactive Week Time-Slider Track
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                final slotWidth = trackWidth / days.length;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _handleTouch(details.localPosition.dx, trackWidth, days),
                  onHorizontalDragStart: (details) =>
                      _handleTouch(details.localPosition.dx, trackWidth, days),
                  onHorizontalDragUpdate: (details) =>
                      _handleTouch(details.localPosition.dx, trackWidth, days),
                  onHorizontalDragEnd: (_) => _lastDraggedIndex = null,
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.25)
                          : Colors.grey.shade200.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Animated sliding indicator pill / cursor
                        if (selectedIndex >= 0)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            left: activeIndex * slotWidth + 3,
                            top: 3,
                            bottom: 3,
                            width: slotWidth - 6,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    theme.colorScheme.primary,
                                    theme.colorScheme.primary.withValues(alpha: 0.88),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Day slots
                        Row(
                          children: List.generate(days.length, (index) {
                            final day = days[index];
                            final isSelected = index == selectedIndex;
                            final isDayToday = isSameDay(day, today);
                            final hasConfirmed = _isConfirmed(day);
                            final hasPending = _isPending(day);

                            Color textColor;
                            if (isSelected) {
                              textColor = theme.colorScheme.onPrimary;
                            } else if (isDayToday) {
                              textColor = theme.colorScheme.primary;
                            } else {
                              textColor = theme.colorScheme.onSurface.withValues(alpha: 0.85);
                            }

                            return Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Short day label: "Lun 19", "Mar 20"...
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatShortDay(day),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: isSelected || isDayToday
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: textColor,
                                        ),
                                      ),
                                      if (isDayToday && !isSelected) ...[
                                        const SizedBox(width: 3),
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),

                                  const SizedBox(height: 3),

                                  // Discrete reservation badge
                                  if (hasConfirmed) ...[
                                    _buildDiscreteBadge(
                                      isConfirmed: true,
                                      isSelected: isSelected,
                                      slotWidth: slotWidth,
                                      theme: theme,
                                    ),
                                  ] else if (hasPending) ...[
                                    _buildDiscreteBadge(
                                      isConfirmed: false,
                                      isSelected: isSelected,
                                      slotWidth: slotWidth,
                                      theme: theme,
                                    ),
                                  ] else ...[
                                    // Subtle indicator rail tick
                                    Container(
                                      width: isSelected ? 12 : 4,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.6)
                                            : theme.dividerColor.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. Subtle background loading indicator line
          if (widget.isLoading)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscreteBadge({
    required bool isConfirmed,
    required bool isSelected,
    required double slotWidth,
    required ThemeData theme,
  }) {
    final baseColor = isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFF1976D2);
    final badgeColor = isSelected ? Colors.white : baseColor;

    if (slotWidth < 56) {
      // Compact dot badge for narrow screens
      return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: badgeColor,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
      );
    }

    // Pill badge with icon and concise label
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.25)
            : baseColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? Colors.white.withValues(alpha: 0.6) : baseColor.withValues(alpha: 0.35),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirmed ? Icons.check : Icons.schedule,
            size: 8.5,
            color: badgeColor,
          ),
          const SizedBox(width: 2),
          Text(
            isConfirmed ? "Bureau" : "Attente",
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: badgeColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
