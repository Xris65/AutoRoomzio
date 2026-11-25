import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../holiday_service.dart';
import '../../../utils/date_helpers.dart';
import '../../../utils/delegation_display_helper.dart';

/// Calendar tab displaying personal, elsewhere, delegated, pending, blocked,
/// and third-party occupancy states on a monthly [TableCalendar].
class CalendarTab extends StatelessWidget {
  final String? workspaceName;
  final bool isCalendarBusy;
  final bool pullToRefreshEnabled;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenFavoritesManager;
  final VoidCallback onOpenTeamMapFocused;
  final VoidCallback onManualSync;
  final bool showAllReservations;
  final ValueChanged<bool> onToggleShowAllReservations;
  final bool showDelegatedReservations;
  final ValueChanged<bool> onToggleShowDelegatedReservations;
  final DateTime focusedDay;
  final ValueChanged<DateTime> onPageChanged;
  final Future<void> Function(DateTime selectedDay) onDateTap;
  final bool hideWeekends;
  final bool showAutomation;
  final List<DateTimeRange> vacations;
  final bool compactMode;
  final bool skipPublicHolidays;
  final String holidayCountryCode;
  final Set<String> bookedDates;
  final Set<String> requestedDates;
  final Set<String> ignoredDates;
  final Map<String, String> bookedElsewhereMap;
  final Map<String, String> delegatedBookingsMap;
  final Map<String, String> occupiedByOthers;
  final Map<String, int> favoriteCountsByDate;

  const CalendarTab({
    super.key,
    required this.workspaceName,
    required this.isCalendarBusy,
    required this.pullToRefreshEnabled,
    required this.onRefresh,
    required this.onOpenFavoritesManager,
    required this.onOpenTeamMapFocused,
    required this.onManualSync,
    required this.showAllReservations,
    required this.onToggleShowAllReservations,
    required this.showDelegatedReservations,
    required this.onToggleShowDelegatedReservations,
    required this.focusedDay,
    required this.onPageChanged,
    required this.onDateTap,
    required this.hideWeekends,
    required this.showAutomation,
    required this.vacations,
    required this.compactMode,
    required this.skipPublicHolidays,
    required this.holidayCountryCode,
    required this.bookedDates,
    required this.requestedDates,
    required this.ignoredDates,
    required this.bookedElsewhereMap,
    required this.delegatedBookingsMap,
    required this.occupiedByOthers,
    this.favoriteCountsByDate = const <String, int>{},
  });

  Widget _wrapWithPtr(Widget child) {
    if (pullToRefreshEnabled) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: child,
      );
    }
    return child;
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    bool isToday = false,
    bool isOutside = false,
    bool isSelected = false,
  }) {
    final String dateStr = DateHelpers.formatIsoDate(day);
    final bool isBooked = bookedDates.contains(dateStr) && showAllReservations;
    final bool isRequested =
        requestedDates.contains(dateStr) && showAllReservations;
    final bool isIgnored =
        ignoredDates.contains(dateStr) && showAllReservations;
    final bool isElsewhere =
        bookedElsewhereMap.containsKey(dateStr) && showAllReservations;
    final bool isDelegated =
        delegatedBookingsMap.containsKey(dateStr) && showDelegatedReservations;
    final bool isOccupiedByOthers = !isBooked &&
        !isElsewhere &&
        !isDelegated &&
        occupiedByOthers.containsKey(dateStr);

    Color? bgColor;
    Color textColor =
        isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;
    bool strikeThrough = false;
    final List<Color> dots = <Color>[];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (isBooked) {
      bgColor = isDark ? Colors.green.shade700 : Colors.green;
      textColor = Colors.white;
      if (isElsewhere) {
        dots.add(isDark ? Colors.orange.shade300 : Colors.orange.shade400);
      }
      if (isDelegated) {
        dots.add(isDark ? Colors.purple.shade300 : Colors.purple.shade400);
      }
    } else if (isElsewhere) {
      bgColor = isDark ? Colors.orange.shade800 : Colors.orange.shade200;
      textColor = isDark ? Colors.orange.shade100 : Colors.orange.shade900;
      if (isDelegated) {
        dots.add(isDark ? Colors.purple.shade300 : Colors.purple.shade400);
      }
    } else if (isDelegated) {
      bgColor = isDark ? Colors.purple.shade800 : Colors.purple.shade200;
      textColor = isDark ? Colors.purple.shade100 : Colors.purple.shade900;
    } else if (isRequested) {
      bgColor = isDark ? Colors.blue.shade700 : Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: isDark ? 0.6 : 0.8);
      textColor = Colors.white;
      strikeThrough = true;
    } else if (isOccupiedByOthers) {
      bgColor = isDark ? Colors.grey.shade700 : Colors.grey.shade400;
      textColor = isDark ? Colors.grey.shade200 : Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: isDark ? 0.2 : 0.3);
    }

    String? cellTooltip;
    if (isOccupiedByOthers) {
      cellTooltip = DelegationDisplayHelper.formatOccupiedCalendarTooltip(
        occupiedByOthers[dateStr]!,
      );
    } else if (isDelegated) {
      final List<String> parts =
          delegatedBookingsMap[dateStr]?.split('|') ?? <String>[];
      final String dName = parts.length > 1 ? parts[1] : 'un collègue';
      final String? dCreator =
          parts.length > 5 && parts[5].isNotEmpty ? parts[5] : null;
      cellTooltip = DelegationDisplayHelper.formatDelegationLabel(
        creator: dCreator,
        bookedFor: dName,
      );
    } else if (isBooked) {
      cellTooltip = 'Réservé';
    } else if (isElsewhere) {
      cellTooltip =
          'Réservé sur un autre bureau (${bookedElsewhereMap[dateStr] ?? "Ailleurs"})';
    } else if (isRequested) {
      cellTooltip = 'Programmé en attente';
    } else if (isIgnored) {
      cellTooltip = 'Bloqué';
    }

    final String? holidayName = skipPublicHolidays
        ? HolidayService.getHolidayName(day, countryCode: holidayCountryCode)
        : null;
    if (holidayName != null) {
      cellTooltip = cellTooltip != null
          ? '$cellTooltip • 🎉 Jour férié : $holidayName'
          : '🎉 Jour férié : $holidayName';
    }

    final int favCount = favoriteCountsByDate[dateStr] ?? 0;
    if (favCount > 0) {
      final String favLabel =
          '⭐ $favCount collègue${favCount > 1 ? 's' : ''} favori${favCount > 1 ? 's' : ''}';
      cellTooltip = cellTooltip != null ? '$cellTooltip • $favLabel' : favLabel;
    }

    final Widget cell = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2.2,
                  )
                : (isOccupiedByOthers
                    ? Border.all(color: Colors.grey.shade400, width: 1)
                    : (holidayName != null && bgColor == null
                        ? Border.all(color: Colors.amber.shade600, width: 1.2)
                        : null)),
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontWeight: (isBooked || isRequested || isIgnored)
                  ? FontWeight.bold
                  : FontWeight.normal,
              decoration: strikeThrough ? TextDecoration.lineThrough : null,
              decorationColor: Colors.grey.shade500,
            ),
          ),
        ),
        if (favCount > 0)
          Positioned(
            key: ValueKey<String>('calendar_fav_badge_$dateStr'),
            top: 1,
            left: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.9)
                    : Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark
                      ? Colors.amber.shade400
                      : Colors.amber.shade700,
                  width: 0.6,
                ),
              ),
              child: Text(
                '⭐$favCount',
                style: TextStyle(
                  fontSize: 8.5,
                  height: 1.05,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.amber.shade100 : Colors.amber.shade900,
                ),
              ),
            ),
          ),
        if (holidayName != null)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                shape: BoxShape.circle,
              ),
            ),
          ),
        if (dots.isNotEmpty || isOccupiedByOthers)
          Positioned(
            bottom: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ...dots.map<Widget>(
                  (Color c) => Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                ),
                if (isOccupiedByOthers)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade700,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    if (cellTooltip != null) {
      return Tooltip(
        message: cellTooltip,
        child: Semantics(
          label: cellTooltip,
          child: cell,
        ),
      );
    }
    return cell;
  }

  @override
  Widget build(BuildContext context) {
    if (workspaceName == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Configurez d'abord votre bureau dans l'onglet Accueil pour utiliser le calendrier.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final DateTime now = DateTime.now();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return _wrapWithPtr(
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Mon Calendrier',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  icon: const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                  ),
                                  tooltip: 'Mes collègues favoris',
                                  onPressed: onOpenFavoritesManager,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.map_outlined),
                                  tooltip:
                                      "Plan d'équipe (Où sont mes collègues ?)",
                                  onPressed: onOpenTeamMapFocused,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.sync),
                                  tooltip: 'Synchroniser avec MyRoomz',
                                  onPressed: onManualSync,
                                ),
                              ],
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8.0,
                          children: <Widget>[
                            FilterChip(
                              label: const Text('Mes places'),
                              selected: showAllReservations,
                              onSelected: onToggleShowAllReservations,
                            ),
                            FilterChip(
                              label: const Text('Délégations'),
                              selected: showDelegatedReservations,
                              onSelected: onToggleShowDelegatedReservations,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      AbsorbPointer(
                        absorbing: isCalendarBusy,
                        child: Opacity(
                          opacity: isCalendarBusy ? 0.5 : 1.0,
                          child: TableCalendar<void>(
                            availableGestures:
                                AvailableGestures.horizontalSwipe,
                            enabledDayPredicate: (DateTime day) {
                              final DateTime normDay = normalizeLocalDate(day);
                              final String dateStr =
                                  DateHelpers.formatIsoDate(normDay);
                              final bool hasBooking =
                                  bookedDates.contains(dateStr) ||
                                      bookedElsewhereMap.containsKey(dateStr) ||
                                      delegatedBookingsMap.containsKey(dateStr) ||
                                      requestedDates.contains(dateStr);
                              if (hideWeekends &&
                                  (normDay.weekday == DateTime.saturday ||
                                      normDay.weekday == DateTime.sunday)) {
                                return hasBooking;
                              }
                              if (showAutomation) {
                                for (final DateTimeRange v in vacations) {
                                  final DateTime start =
                                      normalizeLocalDate(v.start);
                                  final DateTime end =
                                      normalizeLocalDate(v.end);
                                  if (!normDay.isBefore(start) &&
                                      !normDay.isAfter(end)) {
                                    return hasBooking;
                                  }
                                }
                              }
                              return true;
                            },
                            firstDay: addCalendarDays(now, -365),
                            lastDay: addCalendarDays(now, 365),
                            focusedDay: focusedDay,
                            startingDayOfWeek: StartingDayOfWeek.monday,
                            rowHeight: compactMode ? 42.0 : 52.0,
                            daysOfWeekHeight: compactMode ? 20.0 : 24.0,
                            headerStyle: const HeaderStyle(
                              formatButtonVisible: false,
                              titleCentered: true,
                            ),
                            calendarStyle: CalendarStyle(
                              todayDecoration: BoxDecoration(
                                color: Colors.lightBlue.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                            onPageChanged: onPageChanged,
                            selectedDayPredicate: (DateTime day) =>
                                DateHelpers.isSameDay(day, focusedDay),
                            onDaySelected:
                                (DateTime selectedDay, DateTime _) {
                              onDateTap(selectedDay);
                            },
                            calendarBuilders: CalendarBuilders<void>(
                              defaultBuilder: (
                                BuildContext ctx,
                                DateTime day,
                                DateTime _,
                              ) =>
                                  _buildDayCell(ctx, day),
                              selectedBuilder: (
                                BuildContext ctx,
                                DateTime day,
                                DateTime _,
                              ) =>
                                  _buildDayCell(ctx, day, isSelected: true),
                              todayBuilder: (
                                BuildContext ctx,
                                DateTime day,
                                DateTime _,
                              ) =>
                                  _buildDayCell(ctx, day, isToday: true),
                              outsideBuilder: (
                                BuildContext ctx,
                                DateTime day,
                                DateTime _,
                              ) =>
                                  _buildDayCell(ctx, day, isOutside: true),
                              disabledBuilder: (
                                BuildContext ctx,
                                DateTime day,
                                DateTime _,
                              ) =>
                                  _buildDayCell(ctx, day),
                            ),
                          ),
                        ),
                      ),
                      if (isCalendarBusy)
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Synchronisation...',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Builder(
                      builder: (BuildContext context) {
                        final bool isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        return Wrap(
                          alignment: WrapAlignment.spaceEvenly,
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _buildLegend(
                              isDark ? Colors.green.shade700 : Colors.green,
                              'Réservé',
                            ),
                            _buildLegend(
                              isDark ? Colors.blue.shade700 : Colors.blue,
                              'En attente',
                            ),
                            _buildLegend(
                              Colors.red.withValues(alpha: isDark ? 0.6 : 0.8),
                              'Bloqué',
                            ),
                            _buildLegend(
                              isDark
                                  ? Colors.orange.shade800
                                  : Colors.orange.shade300,
                              'Ailleurs',
                            ),
                            _buildLegend(
                              isDark
                                  ? Colors.purple.shade800
                                  : Colors.purple.shade200,
                              'Délégué',
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
