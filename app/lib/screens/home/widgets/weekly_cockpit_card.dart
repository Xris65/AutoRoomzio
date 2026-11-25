import 'dart:async';
import 'package:flutter/material.dart';
import '../../../holiday_service.dart';
import '../../../models/colleague.dart';
import '../../../models/desk_occupant.dart';
import '../../../storage_service.dart';
import '../../../utils/date_helpers.dart';
import '../../team_map/models/team_map_models.dart';

const List<String> _cockpitShortMonths = <String>[
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
  'déc.',
];

enum _CockpitDayStatus {
  bookedHere,
  bookedElsewhere,
  requested,
  vacation,
  holiday,
  autoProjected,
  free,
}

/// Interactive "Ma semaine" cockpit card displayed at the top of the Home tab.
/// Shows daily booking/automation/vacation/holiday status and cached favorite
/// colleague counts (`⭐ N`) without blocking builds or animations.
class WeeklyCockpitCard extends StatefulWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDaySelected;
  final bool hideWeekends;
  final bool showAutomation;
  final bool automationEnabled;
  final List<AutomationRule> automationRules;
  final List<int> selectedDays;
  final bool Function(DateTime date) isVacation;
  final bool skipPublicHolidays;
  final String holidayCountryCode;
  final Set<String> bookedDates;
  final Set<String> requestedDates;
  final Set<String> ignoredDates;
  final Map<String, String> bookedElsewhereMap;
  final StorageService? storageService;
  final String? floorId;
  final bool showFavoriteWeekIndicators;
  final int refreshToken;

  const WeeklyCockpitCard({
    super.key,
    required this.onDaySelected,
    required this.hideWeekends,
    required this.showAutomation,
    required this.automationEnabled,
    required this.automationRules,
    required this.selectedDays,
    required this.isVacation,
    required this.skipPublicHolidays,
    required this.holidayCountryCode,
    required this.bookedDates,
    required this.requestedDates,
    required this.ignoredDates,
    required this.bookedElsewhereMap,
    this.selectedDate,
    this.storageService,
    this.floorId,
    this.showFavoriteWeekIndicators = true,
    this.refreshToken = 0,
  });

  @override
  State<WeeklyCockpitCard> createState() => _WeeklyCockpitCardState();
}

class _WeeklyCockpitCardState extends State<WeeklyCockpitCard> {
  late DateTime _weekAnchor;
  Map<String, int> _favoriteCounts = <String, int>{};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _weekAnchor = normalizeLocalDate(widget.selectedDate ?? DateTime.now());
    unawaited(_loadCachedFavoritesForWeek());
  }

  @override
  void didUpdateWidget(covariant WeeklyCockpitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool weekChanged = false;
    final DateTime? newSelected = widget.selectedDate;
    final DateTime? oldSelected = oldWidget.selectedDate;
    if (newSelected != null &&
        (oldSelected == null || !DateHelpers.isSameDay(newSelected, oldSelected))) {
      final List<DateTime> currentDays = _visibleWeekDays(_weekAnchor);
      final bool isInCurrentWeek = currentDays.any(
        (DateTime d) => DateHelpers.isSameDay(d, newSelected),
      );
      if (!isInCurrentWeek) {
        _weekAnchor = normalizeLocalDate(newSelected);
        weekChanged = true;
      }
    }

    if (weekChanged ||
        widget.floorId != oldWidget.floorId ||
        widget.hideWeekends != oldWidget.hideWeekends ||
        widget.showFavoriteWeekIndicators !=
            oldWidget.showFavoriteWeekIndicators ||
        widget.refreshToken != oldWidget.refreshToken ||
        widget.storageService != oldWidget.storageService) {
      unawaited(_loadCachedFavoritesForWeek());
    }
  }

  List<DateTime> _visibleWeekDays(DateTime anchor) {
    return TeamMapHelpers.getVisibleWeekDays(
      anchor,
      hideWeekends: widget.hideWeekends,
    );
  }

  void _shiftWeek(int deltaDays) {
    setState(() {
      _weekAnchor = addCalendarDays(_weekAnchor, deltaDays);
    });
    unawaited(_loadCachedFavoritesForWeek());
  }

  Future<void> _loadCachedFavoritesForWeek() async {
    final int gen = ++_loadGeneration;
    final StorageService? storage = widget.storageService;
    final String? floorId = widget.floorId;

    if (!widget.showFavoriteWeekIndicators ||
        storage == null ||
        floorId == null ||
        floorId.isEmpty) {
      if (_favoriteCounts.isNotEmpty && mounted) {
        setState(() => _favoriteCounts = <String, int>{});
      }
      return;
    }

    final List<Colleague> favorites = await storage.getFavoriteColleagues();
    if (!mounted || gen != _loadGeneration) return;
    if (favorites.isEmpty) {
      if (_favoriteCounts.isNotEmpty) {
        setState(() => _favoriteCounts = <String, int>{});
      }
      return;
    }

    final Set<String> favIds = <String>{};
    final Set<String> favEmails = <String>{};
    final Set<String> favNames = <String>{};
    for (final Colleague fav in favorites) {
      if (fav.id.isNotEmpty) favIds.add(fav.id.toLowerCase());
      if (fav.email.isNotEmpty) {
        final String emailLower = fav.email.trim().toLowerCase();
        favIds.add(emailLower);
        favEmails.add(emailLower);
      }
      if (fav.name.trim().isNotEmpty) {
        favNames.add(fav.name.trim().toLowerCase());
      }
    }

    final List<DateTime> days = _visibleWeekDays(_weekAnchor);
    final List<String> isos =
        days.map<String>(DateHelpers.formatIsoDate).toList();
    final List<Map<String, DeskOccupant>> occResults =
        await Future.wait<Map<String, DeskOccupant>>(
      isos.map<Future<Map<String, DeskOccupant>>>(
        (String iso) => storage.getFloorOccupants(floorId, iso),
      ),
    );
    if (!mounted || gen != _loadGeneration) return;

    final Map<String, int> counts = <String, int>{};
    for (int i = 0; i < isos.length; i++) {
      final int count = TeamMapHelpers.countUniqueFavorites(
        occResults[i],
        favoriteIds: favIds,
        favoriteEmailsNormalized: favEmails,
        favoriteNamesNormalized: favNames,
      );
      if (count > 0) {
        counts[isos[i]] = count;
      }
    }

    if (mounted && gen == _loadGeneration) {
      setState(() => _favoriteCounts = counts);
    }
  }

  String _formatDateRange(List<DateTime> days) {
    if (days.isEmpty) return '';
    final DateTime first = days.first;
    final DateTime last = days.last;
    final String firstMonth = _cockpitShortMonths[first.month - 1];
    final String lastMonth = _cockpitShortMonths[last.month - 1];
    return '${first.day} $firstMonth – ${last.day} $lastMonth';
  }

  _CockpitDayStatus _resolveStatus(
    DateTime day,
    String iso,
    Map<int, AutomationRule> rulesByWeekday,
  ) {
    if (widget.bookedDates.contains(iso)) {
      return _CockpitDayStatus.bookedHere;
    }
    if (widget.bookedElsewhereMap.containsKey(iso)) {
      return _CockpitDayStatus.bookedElsewhere;
    }
    if (widget.requestedDates.contains(iso)) {
      return _CockpitDayStatus.requested;
    }
    if (widget.showAutomation && widget.isVacation(day)) {
      return _CockpitDayStatus.vacation;
    }
    if (widget.skipPublicHolidays &&
        HolidayService.isHoliday(
          day,
          countryCode: widget.holidayCountryCode,
        )) {
      return _CockpitDayStatus.holiday;
    }
    final bool hasRuleOrDay = rulesByWeekday.containsKey(day.weekday) ||
        (widget.automationRules.isEmpty &&
            widget.selectedDays.contains(day.weekday));
    final bool isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    if (widget.automationEnabled &&
        !widget.ignoredDates.contains(iso) &&
        !(widget.hideWeekends && isWeekend) &&
        hasRuleOrDay) {
      return _CockpitDayStatus.autoProjected;
    }
    return _CockpitDayStatus.free;
  }

  String _statusTooltip(
    _CockpitDayStatus status,
    DateTime day,
    String iso,
    int favCount,
  ) {
    final String dayLabel = DateHelpers.formatFrenchDate(day);
    final String statusText = switch (status) {
      _CockpitDayStatus.bookedHere => 'Réservé sur votre bureau',
      _CockpitDayStatus.bookedElsewhere =>
        'Réservé ailleurs (${widget.bookedElsewhereMap[iso] ?? 'Autre bureau'})',
      _CockpitDayStatus.requested => 'Programmé en attente',
      _CockpitDayStatus.vacation => 'En congés',
      _CockpitDayStatus.holiday =>
        'Jour férié (${HolidayService.getHolidayName(day, countryCode: widget.holidayCountryCode) ?? ''})',
      _CockpitDayStatus.autoProjected => 'Réservation automatique prévue',
      _CockpitDayStatus.free => 'Libre',
    };
    if (favCount > 0) {
      return '$dayLabel • $statusText • $favCount favori${favCount > 1 ? 's' : ''}';
    }
    return '$dayLabel • $statusText';
  }

  Widget _buildStatusBadge(_CockpitDayStatus status, bool isDark) {
    return switch (status) {
      _CockpitDayStatus.bookedHere => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isDark ? Colors.green.shade400 : Colors.green.shade600,
            shape: BoxShape.circle,
          ),
        ),
      _CockpitDayStatus.bookedElsewhere => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isDark ? Colors.orange.shade300 : Colors.orange.shade600,
            shape: BoxShape.circle,
          ),
        ),
      _CockpitDayStatus.requested => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
            shape: BoxShape.circle,
          ),
        ),
      _CockpitDayStatus.autoProjected => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: (isDark ? Colors.blue.shade300 : Colors.blue.shade600)
                .withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
              width: 2,
            ),
          ),
        ),
      _CockpitDayStatus.vacation => Icon(
          Icons.beach_access_rounded,
          size: 14,
          color: isDark ? Colors.amber.shade300 : Colors.orange.shade700,
        ),
      _CockpitDayStatus.holiday => Icon(
          Icons.celebration_rounded,
          size: 14,
          color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
        ),
      _CockpitDayStatus.free => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final DateTime today = normalizeLocalDate(DateTime.now());
    final List<DateTime> days = _visibleWeekDays(_weekAnchor);
    final Map<int, AutomationRule> rulesByWeekday = <int, AutomationRule>{
      for (final AutomationRule r in widget.automationRules)
        for (final int d in r.days) d: r,
    };

    return Card(
      key: const ValueKey<String>('weekly_cockpit_card'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.view_week_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Ma semaine',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatDateRange(days),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('cockpit_week_prev_btn'),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Semaine précédente',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shiftWeek(-7),
                ),
                IconButton(
                  key: const ValueKey<String>('cockpit_week_next_btn'),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Semaine suivante',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shiftWeek(7),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: days.map<Widget>((DateTime day) {
                final String iso = DateHelpers.formatIsoDate(day);
                final bool isToday = DateHelpers.isSameDay(day, today);
                final bool isSelected = widget.selectedDate != null &&
                    DateHelpers.isSameDay(day, widget.selectedDate!);
                final _CockpitDayStatus status =
                    _resolveStatus(day, iso, rulesByWeekday);
                final int favCount = widget.showFavoriteWeekIndicators
                    ? (_favoriteCounts[iso] ?? 0)
                    : 0;
                final String shortDay =
                    DateHelpers.frenchShortWeekdaysList[day.weekday - 1];

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: _statusTooltip(status, day, iso, favCount),
                      child: Material(
                        color: isSelected
                            ? scheme.primaryContainer.withValues(alpha: 0.65)
                            : (isToday
                                ? scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.6)
                                : scheme.surfaceContainerLowest),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: ValueKey<String>('cockpit_day_$iso'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onDaySelected(day),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? scheme.primary
                                    : (isToday
                                        ? scheme.primary.withValues(alpha: 0.45)
                                        : scheme.outlineVariant
                                            .withValues(alpha: 0.5)),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    shortDay,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isToday || isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isToday || isSelected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 16,
                                  child: Center(
                                    child: _buildStatusBadge(status, isDark),
                                  ),
                                ),
                                if (favCount > 0) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Container(
                                    key: ValueKey<String>(
                                      'cockpit_fav_badge_$iso',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.amber.shade700
                                            .withValues(alpha: 0.45),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '⭐ $favCount',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.amber.shade200
                                              : Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
