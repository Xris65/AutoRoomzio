import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../holiday_service.dart';
import '../../../models/automation_rule.dart';
import '../../../utils/date_helpers.dart';
import '../../../utils/delegation_display_helper.dart';

/// Dashboard (Home) tab displaying the selected workspace, quick actions,
/// team map / favorites shortcuts, and upcoming reservations.
class HomeDashboardTab extends StatelessWidget {
  final bool isCalendarBusy;
  final bool pullToRefreshEnabled;
  final Future<void> Function() onRefresh;
  final bool showAutomation;
  final List<DateTimeRange> vacations;
  final bool Function(DateTime date) isVacation;
  final String? workspaceName;
  final String? defaultWorkspaceId;
  final VoidCallback onChangeWorkspace;
  final VoidCallback onResetWorkspace;
  final bool hideWeekends;
  final Future<void> Function(int daysOffset) onQuickBook;
  final VoidCallback onOpenTeamMapToday;
  final VoidCallback onOpenFavoritesManager;
  final bool showAllReservations;
  final ValueChanged<bool> onToggleShowAllReservations;
  final bool showDelegatedReservations;
  final ValueChanged<bool> onToggleShowDelegatedReservations;
  final bool compactMode;
  final bool automationEnabled;
  final List<AutomationRule> automationRules;
  final List<int> selectedDays;
  final int projectionsCount;
  final bool skipPublicHolidays;
  final String holidayCountryCode;
  final Set<String> ignoredDates;
  final Set<String> bookedDates;
  final Set<String> requestedDates;
  final Map<String, String> requestedWorkspacesMap;
  final Map<String, String> requestedWorkspaceNamesMap;
  final Map<String, String> bookedElsewhereMap;
  final Map<String, String> delegatedBookingsMap;
  final Map<String, String> occupiedByOthers;
  final Future<void> Function(DateTime date) onDateTap;
  final Future<void> Function(
    DateTime date,
    bool isBooked,
    String source, {
    bool isRequested,
  }) onQuickAction;

  const HomeDashboardTab({
    super.key,
    required this.isCalendarBusy,
    required this.pullToRefreshEnabled,
    required this.onRefresh,
    required this.showAutomation,
    required this.vacations,
    required this.isVacation,
    required this.workspaceName,
    required this.defaultWorkspaceId,
    required this.onChangeWorkspace,
    required this.onResetWorkspace,
    required this.hideWeekends,
    required this.onQuickBook,
    required this.onOpenTeamMapToday,
    required this.onOpenFavoritesManager,
    required this.showAllReservations,
    required this.onToggleShowAllReservations,
    required this.showDelegatedReservations,
    required this.onToggleShowDelegatedReservations,
    required this.compactMode,
    required this.automationEnabled,
    required this.automationRules,
    required this.selectedDays,
    required this.projectionsCount,
    required this.skipPublicHolidays,
    required this.holidayCountryCode,
    required this.ignoredDates,
    required this.bookedDates,
    required this.requestedDates,
    required this.requestedWorkspacesMap,
    required this.requestedWorkspaceNamesMap,
    required this.bookedElsewhereMap,
    required this.delegatedBookingsMap,
    required this.occupiedByOthers,
    required this.onDateTap,
    required this.onQuickAction,
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

  Widget _buildShimmerLoading(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 3,
        itemBuilder: (BuildContext _, int index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingBookings(BuildContext context) {
    final List<Map<String, Object?>> upcoming = <Map<String, Object?>>[];
    final DateTime now = normalizeLocalDate(DateTime.now());
    int recurringProjectionsCount = 0;
    final Map<int, AutomationRule> rulesByWeekday = <int, AutomationRule>{
      for (final AutomationRule r in automationRules)
        for (final int d in r.days) d: r,
    };

    for (int i = 0; i < 60; i++) {
      final DateTime date = addCalendarDays(now, i);
      final String dateStr = DateHelpers.formatIsoDate(date);

      if (ignoredDates.contains(dateStr)) continue;

      final bool isBooked =
          bookedDates.contains(dateStr) && showAllReservations;
      final bool isRequested =
          requestedDates.contains(dateStr) && showAllReservations;
      final bool isElsewhere =
          bookedElsewhereMap.containsKey(dateStr) && showAllReservations;
      final bool isDelegated =
          delegatedBookingsMap.containsKey(dateStr) &&
              showDelegatedReservations;

      String delegateName = "Quelqu'un";
      String delegateLocation = '';
      String? delegateCreator;
      if (isDelegated) {
        final List<String> parts = delegatedBookingsMap[dateStr]!.split('|');
        delegateName = parts.length > 1 ? parts[1] : parts[0];
        if (parts.length > 2) delegateLocation = parts[2];
        if (parts.length > 5 && parts[5].isNotEmpty) {
          delegateCreator = parts[5];
        }
      }

      final bool isOccupiedByOthers = !isBooked &&
          !isElsewhere &&
          !isDelegated &&
          occupiedByOthers.containsKey(dateStr);
      final AutomationRule? ruleForDay = rulesByWeekday[date.weekday];
      final bool hasRuleOrLegacyDay = ruleForDay != null ||
          (automationRules.isEmpty && selectedDays.contains(date.weekday));
      bool isRecurring =
          automationEnabled && hasRuleOrLegacyDay && showAllReservations;
      if (hideWeekends &&
          (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)) {
        isRecurring = false;
      }
      if (isVacation(date)) isRecurring = false;
      if (skipPublicHolidays &&
          HolidayService.isHoliday(date, countryCode: holidayCountryCode)) {
        isRecurring = false;
      }

      final bool targetsDefaultDesk = ruleForDay == null ||
          (defaultWorkspaceId != null &&
              defaultWorkspaceId!.isNotEmpty &&
              ruleForDay.workspaceId.toLowerCase() ==
                  defaultWorkspaceId!.toLowerCase());
      final String? projectedWorkspaceName =
          ruleForDay?.workspaceName ?? workspaceName;

      if (isDelegated) {
        upcoming.add(<String, Object?>{
          'date': date,
          'source': 'Délégué',
          'isBooked': true,
          'name': delegateName,
          'location': delegateLocation,
          'creator': delegateCreator,
        });
      }

      if (isElsewhere) {
        upcoming.add(<String, Object?>{
          'date': date,
          'source': 'Ailleurs',
          'isBooked': true,
          'name': bookedElsewhereMap[dateStr],
        });
      }
      if (isBooked) {
        upcoming.add(<String, Object?>{
          'date': date,
          'source': 'Calendrier',
          'isBooked': true,
        });
      } else if (isRequested) {
        final String? requestedWs = requestedWorkspaceNamesMap[dateStr] ??
            requestedWorkspacesMap[dateStr];
        upcoming.add(<String, Object?>{
          'date': date,
          'source': 'Calendrier',
          'isBooked': false,
          'name': requestedWs,
          'isRequested': true,
        });
      } else if (isOccupiedByOthers && targetsDefaultDesk) {
        if (isRecurring && recurringProjectionsCount < projectionsCount) {
          upcoming.add(<String, Object?>{
            'date': date,
            'source': 'Occupé',
            'isBooked': false,
            'name': occupiedByOthers[dateStr],
          });
          recurringProjectionsCount++;
        }
      } else if (isRecurring && recurringProjectionsCount < projectionsCount) {
        upcoming.add(<String, Object?>{
          'date': date,
          'source': 'Récurrent',
          'isBooked': false,
          'workspaceName': projectedWorkspaceName,
        });
        recurringProjectionsCount++;
      }
    }

    if (upcoming.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Aucune réservation prévue.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: upcoming.map<Widget>((Map<String, Object?> item) {
        final DateTime date = item['date']! as DateTime;
        final String source = item['source']! as String;
        final bool isBooked = item['isBooked']! as bool;
        final bool isRequested =
            item['isRequested'] == true || (!isBooked && source == 'Calendrier');
        final bool isDeletable = isBooked ||
            source == 'Délégué' ||
            source == 'Ailleurs' ||
            isRequested;
        final String weekDayName =
            DateHelpers.frenchWeekdaysList[date.weekday - 1];

        final Color itemColor = switch (source) {
          'Ailleurs' =>
            isDark ? Colors.orange.shade300 : Colors.orange.shade900,
          'Délégué' =>
            isDark ? Colors.purple.shade300 : Colors.purple.shade900,
          'Occupé' => isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          _ when isBooked =>
            isDark ? Colors.green.shade400 : Colors.green,
          _ => isDark ? Colors.blue.shade300 : Colors.blue,
        };

        final IconData itemIcon = switch (source) {
          'Ailleurs' => Icons.person,
          'Délégué' => Icons.group,
          'Occupé' => Icons.person_off,
          _ when isBooked => Icons.check_circle,
          _ => Icons.pending,
        };

        final String subtitleText;
        if (source == 'Ailleurs') {
          subtitleText =
              'Réservé sur un autre bureau (${item['name'] ?? 'Ailleurs'})';
        } else if (source == 'Délégué') {
          subtitleText = DelegationDisplayHelper.formatDelegatedHomeSubtitle(
            delegateName: item['name']?.toString() ?? "Quelqu'un",
            location: item['location']?.toString(),
            creatorName: item['creator']?.toString(),
          );
        } else if (source == 'Occupé') {
          subtitleText = DelegationDisplayHelper.formatOccupiedHomeSubtitle(
            item['name']?.toString() ?? '',
          );
        } else if (isBooked) {
          subtitleText = 'Déjà réservé';
        } else if (source == 'Calendrier' &&
            item['name'] != null &&
            item['name'].toString().isNotEmpty) {
          subtitleText = 'Programmé en attente (${item['name']})';
        } else if (item['workspaceName'] != null &&
            item['workspaceName'].toString().isNotEmpty) {
          subtitleText = 'Sera réservé (${item['workspaceName']})';
        } else {
          subtitleText = 'Sera réservé (Automatique)';
        }

        final Color chipBg = switch (source) {
          'Calendrier' => Colors.purple.withValues(alpha: 0.1),
          'Ailleurs' => Colors.orange.withValues(alpha: 0.3),
          'Délégué' => Colors.purple.withValues(alpha: 0.3),
          'Occupé' => Colors.grey.withValues(alpha: 0.2),
          _ => Colors.orange.withValues(alpha: 0.1),
        };

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ListTile(
            visualDensity: compactMode ? VisualDensity.compact : null,
            contentPadding: compactMode
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 0)
                : null,
            onTap: () => onDateTap(date),
            leading: Icon(itemIcon, color: itemColor),
            title: Text('$weekDayName ${date.day}/${date.month}'),
            subtitle: Text(
              subtitleText,
              style: TextStyle(
                color: itemColor,
                fontSize: compactMode ? 10 : 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Chip(
                  label: Text(source, style: const TextStyle(fontSize: 10)),
                  backgroundColor: chipBg,
                  visualDensity: VisualDensity.compact,
                ),
                if (source != 'Occupé')
                  IconButton(
                    icon: Icon(
                      isDeletable ? Icons.delete_outline : Icons.block,
                      size: 20,
                    ),
                    color: Colors.redAccent,
                    tooltip: isDeletable ? 'Supprimer' : 'Bloquer',
                    onPressed: () => onQuickAction(
                      date,
                      isBooked || source == 'Délégué' || source == 'Ailleurs',
                      source,
                      isRequested: isRequested,
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = normalizeLocalDate(DateTime.now());
    final DateTime tomorrow = addCalendarDays(today, 1);
    final bool todayIsWeekend = today.weekday == DateTime.saturday ||
        today.weekday == DateTime.sunday;
    final bool tomorrowIsWeekend = tomorrow.weekday == DateTime.saturday ||
        tomorrow.weekday == DateTime.sunday;
    final bool todayIsVacation = isVacation(today);
    final bool tomorrowIsVacation = isVacation(tomorrow);
    final bool disableToday =
        todayIsVacation || (hideWeekends && todayIsWeekend);
    final bool disableTomorrow =
        tomorrowIsVacation || (hideWeekends && tomorrowIsWeekend);

    return Stack(
      children: <Widget>[
        AbsorbPointer(
          absorbing: isCalendarBusy,
          child: Opacity(
            opacity: isCalendarBusy ? 0.5 : 1.0,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return _wrapWithPtr(
                  SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (showAutomation && isVacation(today))
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.beach_access,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "Mode Congés activé. L'automatisation est en pause sur cette date.",
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: onChangeWorkspace,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.desk,
                                      color: Colors.lightBlue,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          const Text(
                                            'Bureau sélectionné',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            workspaceName ??
                                                'Aucun bureau configuré',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: workspaceName != null
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (workspaceName != null)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Réinitialiser',
                                        onPressed: onResetWorkspace,
                                      )
                                    else
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (workspaceName != null) ...<Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: Icon(
                                      todayIsVacation
                                          ? Icons.beach_access
                                          : (disableToday
                                              ? Icons.weekend
                                              : Icons.flash_on),
                                      size: 16,
                                    ),
                                    label: Text(
                                      todayIsVacation
                                          ? 'En Congés'
                                          : (disableToday
                                              ? "Aujourd'hui (Week-end)"
                                              : "Aujourd'hui"),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: disableToday
                                        ? null
                                        : () => onQuickBook(0),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: Icon(
                                      tomorrowIsVacation
                                          ? Icons.beach_access
                                          : (disableTomorrow
                                              ? Icons.weekend
                                              : Icons.flash_on),
                                      size: 16,
                                    ),
                                    label: Text(
                                      tomorrowIsVacation
                                          ? 'En Congés'
                                          : (disableTomorrow
                                              ? 'Demain (Week-end)'
                                              : 'Demain'),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: disableTomorrow
                                        ? null
                                        : () => onQuickBook(1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Card(
                              elevation: 0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: onOpenTeamMapToday,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.people_outline,
                                        color: Colors.amber,
                                        size: 24,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              "Plan d'équipe",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              "Voir où sont assis vos collègues aujourd'hui",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Card(
                              elevation: 0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: onOpenFavoritesManager,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.star_rounded,
                                        color: Colors.amber,
                                        size: 24,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              'Mes collègues favoris',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              'Rechercher et gérer vos collègues favoris',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  '📅 Prochaines réservations',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8.0,
                                  children: <Widget>[
                                    FilterChip(
                                      label: const Text(
                                        'Mes places',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      selected: showAllReservations,
                                      onSelected: onToggleShowAllReservations,
                                    ),
                                    FilterChip(
                                      label: const Text(
                                        'Délégations',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      selected: showDelegatedReservations,
                                      onSelected:
                                          onToggleShowDelegatedReservations,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            isCalendarBusy
                                ? _buildShimmerLoading(context)
                                : _buildUpcomingBookings(context),
                          ],
                          if (workspaceName == null) ...<Widget>[
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                "Configurez d'abord votre bureau en cliquant sur la carte ci-dessus.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            if (automationRules.any(
                                  (AutomationRule r) => r.days.isNotEmpty,
                                ) &&
                                automationEnabled) ...<Widget>[
                              const SizedBox(height: 20),
                              const Text(
                                '📅 Prochaines réservations',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              isCalendarBusy
                                  ? _buildShimmerLoading(context)
                                  : _buildUpcomingBookings(context),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (isCalendarBusy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}
