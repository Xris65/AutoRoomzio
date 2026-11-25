import 'package:flutter/material.dart';
import '../../../models/automation_rule.dart';
import '../../../utils/date_helpers.dart';

/// Automation tab displaying vacation periods, global automation toggle/time/run,
/// the vertical weekly summary banner, and multi-desk rule cards.
class AutomationTab extends StatelessWidget {
  final bool isCalendarBusy;
  final bool hideWeekends;
  final bool showAutomation;
  final bool automationEnabled;
  final TimeOfDay automationTime;
  final List<DateTimeRange> vacations;
  final List<AutomationRule> automationRules;
  final Future<void> Function() onAddVacation;
  final void Function(DateTimeRange vacation) onDeleteVacation;
  final Future<void> Function(bool value) onToggleAutomation;
  final Future<void> Function(TimeOfDay time) onAutomationTimeChanged;
  final Future<void> Function() onRunAutomationNow;
  final Future<void> Function() onAddAutomationPlace;
  final Future<void> Function(AutomationRule rule) onChangeRulePlace;
  final Future<void> Function(AutomationRule rule) onDeleteAutomationRule;
  final Future<void> Function(
    AutomationRule rule,
    int day,
    AutomationRule? conflictingRule,
  ) onRuleDayPressed;

  const AutomationTab({
    super.key,
    required this.isCalendarBusy,
    required this.hideWeekends,
    required this.showAutomation,
    required this.automationEnabled,
    required this.automationTime,
    required this.vacations,
    required this.automationRules,
    required this.onAddVacation,
    required this.onDeleteVacation,
    required this.onToggleAutomation,
    required this.onAutomationTimeChanged,
    required this.onRunAutomationNow,
    required this.onAddAutomationPlace,
    required this.onChangeRulePlace,
    required this.onDeleteAutomationRule,
    required this.onRuleDayPressed,
  });

  static const List<MaterialColor> _ruleAccentPalette = <MaterialColor>[
    Colors.indigo,
    Colors.teal,
    Colors.deepPurple,
    Colors.deepOrange,
    Colors.pink,
    Colors.blue,
    Colors.green,
  ];

  /// Returns a harmonious light/dark-aware accent color set for an automation rule index.
  ({Color background, Color border, Color foreground, Color icon})
      _ruleAccentColors(int ruleIndex, bool isDark) {
    final int safeIndex = ruleIndex < 0 ? 0 : ruleIndex;
    final MaterialColor paletteColor =
        _ruleAccentPalette[safeIndex % _ruleAccentPalette.length];
    return (
      background: paletteColor.withValues(alpha: isDark ? 0.22 : 0.12),
      border: (isDark ? paletteColor.shade400 : paletteColor.shade300)
          .withValues(alpha: isDark ? 0.55 : 0.75),
      foreground: isDark ? paletteColor.shade200 : paletteColor.shade800,
      icon: isDark ? paletteColor.shade300 : paletteColor.shade700,
    );
  }

  Widget _buildWeeklySummaryBanner({
    required List<int> daysToShow,
    required Map<int, AutomationRule> weekdayMap,
    required Map<String, int> ruleIndexById,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Card(
      key: const ValueKey<String>('weekly_summary_banner'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.calendar_view_week_rounded,
                  size: 18,
                  color: automationEnabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ma semaine type',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!automationEnabled)
                  Container(
                    key: const ValueKey<String>('weekly_summary_paused_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Text(
                      'En pause',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedOpacity(
              opacity: automationEnabled ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: daysToShow.map<Widget>((int day) {
                  final AutomationRule? assignedRule = weekdayMap[day];
                  final bool hasRule = assignedRule != null;
                  final ({
                    Color background,
                    Color border,
                    Color foreground,
                    Color icon,
                  })? accent = hasRule
                      ? _ruleAccentColors(
                          ruleIndexById[assignedRule.workspaceId] ?? 0,
                          isDark,
                        )
                      : null;

                  return Padding(
                    key: ValueKey<String>('weekly_summary_day_$day'),
                    padding: EdgeInsets.only(
                      bottom: day == daysToShow.last ? 0 : 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 48,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hasRule
                                ? theme.colorScheme.primary
                                    .withValues(alpha: isDark ? 0.24 : 0.14)
                                : theme.colorScheme.surface
                                    .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasRule
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.5)
                                  : theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              DateHelpers.frenchShortWeekdaysMap[day] ?? '',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: hasRule
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: hasRule
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: hasRule
                              ? Tooltip(
                                  message: assignedRule.workspaceName,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent!.background,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: accent.border),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: <Widget>[
                                        Icon(
                                          Icons.desk_rounded,
                                          size: 14,
                                          color: accent.icon,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            assignedRule.workspaceName,
                                            softWrap: true,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: accent.foreground,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Aucun bureau automatisé',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<int> daysToShow = hideWeekends
        ? <int>[1, 2, 3, 4, 5]
        : <int>[1, 2, 3, 4, 5, 6, 7];
    final Map<int, AutomationRule> weekdayMap = <int, AutomationRule>{
      for (final AutomationRule r in automationRules)
        for (final int d in r.days) d: r,
    };
    final Map<String, int> ruleIndexById = <String, int>{
      for (int i = 0; i < automationRules.length; i++)
        automationRules[i].workspaceId: i,
    };
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: <Widget>[
        AbsorbPointer(
          absorbing: isCalendarBusy,
          child: Opacity(
            opacity: isCalendarBusy ? 0.5 : 1.0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const ListTile(
                          leading:
                              Icon(Icons.beach_access, color: Colors.orange),
                          title: Text(
                            'Mes Congés / Absences',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "L'automatisation est désactivée sur ces dates",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        if (vacations.isNotEmpty) const Divider(height: 1),
                        if (showAutomation)
                          ...vacations.map<Widget>(
                            (DateTimeRange v) => ListTile(
                              dense: true,
                              title: Text(
                                'Du ${v.start.day}/${v.start.month}/${v.start.year} au ${v.end.day}/${v.end.month}/${v.end.year}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: () => onDeleteVacation(v),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter une période'),
                            onPressed: onAddVacation,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: <Widget>[
                        SwitchListTile(
                          key: const ValueKey<String>(
                            'toggle_automation_enabled',
                          ),
                          title: const Text(
                            'Automatisation',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'Réserver automatiquement mes places',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: automationEnabled,
                          onChanged: onToggleAutomation,
                          secondary: Icon(
                            automationEnabled
                                ? Icons.auto_awesome
                                : Icons.auto_awesome_outlined,
                            color:
                                automationEnabled ? Colors.green : Colors.grey,
                          ),
                        ),
                        if (!automationEnabled)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Container(
                              key: const ValueKey<String>(
                                'automation_disabled_banner',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: theme
                                    .colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.pause_circle_outline_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Automatisation en pause — aucune réservation automatique ne sera effectuée.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Divider(height: 1),
                        ListTile(
                          enabled: automationEnabled,
                          leading: Icon(
                            Icons.schedule,
                            color: automationEnabled
                                ? Colors.blue
                                : theme.disabledColor,
                          ),
                          title: const Text("Heure d'exécution"),
                          subtitle: const Text(
                            "Heure approximative à laquelle l'automatisation s'exécutera chaque jour",
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            automationTime.format(context),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: automationEnabled
                                  ? null
                                  : theme.disabledColor,
                            ),
                          ),
                          onTap: automationEnabled
                              ? () async {
                                  final TimeOfDay? time = await showTimePicker(
                                    context: context,
                                    initialTime: automationTime,
                                  );
                                  if (time != null) {
                                    await onAutomationTimeChanged(time);
                                  }
                                }
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          key: const ValueKey<String>(
                            'run_automation_now_tile',
                          ),
                          enabled: automationEnabled,
                          leading: Icon(
                            Icons.play_circle_fill,
                            color: automationEnabled
                                ? Colors.green
                                : theme.disabledColor,
                          ),
                          title: const Text('Lancer maintenant'),
                          subtitle: const Text(
                            'Exécuter manuellement la routine tout de suite',
                            style: TextStyle(fontSize: 11),
                          ),
                          onTap: automationEnabled ? onRunAutomationNow : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildWeeklySummaryBanner(
                    daysToShow: daysToShow,
                    weekdayMap: weekdayMap,
                    ruleIndexById: ruleIndexById,
                    theme: theme,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'Mes places automatisées',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey<String>(
                            'add_automation_rule_button',
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter une place'),
                          onPressed: onAddAutomationPlace,
                        ),
                      ],
                    ),
                  ),
                  if (!automationEnabled) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      "Activez l'automatisation ci-dessus pour exécuter ces règles.",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (automationRules.isEmpty)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side:
                            BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Aucune place automatisée configurée.\nAjoutez une place pour associer des jours de la semaine.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    AnimatedOpacity(
                      opacity: automationEnabled ? 1.0 : 0.65,
                      duration: const Duration(milliseconds: 200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: automationRules.map<Widget>((
                          AutomationRule rule,
                        ) {
                          final List<int> sortedActiveDays =
                              List<int>.from(rule.days)..sort();
                          final String activeDaysLabel = sortedActiveDays.isEmpty
                              ? 'Aucun jour sélectionné'
                              : sortedActiveDays
                                  .map<String>(
                                    (int d) =>
                                        DateHelpers.frenchWeekdaysMap[d] ?? '',
                                  )
                                  .where((String s) => s.isNotEmpty)
                                  .join(', ');
                          final ({
                            Color background,
                            Color border,
                            Color foreground,
                            Color icon,
                          }) ruleColors = _ruleAccentColors(
                            ruleIndexById[rule.workspaceId] ?? 0,
                            isDark,
                          );
                          return Card(
                            key: ValueKey<String>(
                              'automation_rule_card_${rule.workspaceId}',
                            ),
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.desk_rounded,
                                        color: ruleColors.icon,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              rule.workspaceName,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              activeDaysLabel,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: 0.65),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: ValueKey<String>(
                                          'change_automation_rule_${rule.workspaceId}',
                                        ),
                                        icon: const Icon(
                                          Icons.edit_location_alt_outlined,
                                          size: 20,
                                        ),
                                        tooltip: 'Changer de place',
                                        onPressed: () => onChangeRulePlace(rule),
                                      ),
                                      IconButton(
                                        key: ValueKey<String>(
                                          'delete_automation_rule_${rule.workspaceId}',
                                        ),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                          size: 20,
                                        ),
                                        tooltip: 'Supprimer',
                                        onPressed: () =>
                                            onDeleteAutomationRule(rule),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: daysToShow.map<Widget>((int day) {
                                      final bool isSelectedHere =
                                          rule.days.contains(day);
                                      final AutomationRule? otherRule =
                                          (!isSelectedHere)
                                              ? weekdayMap[day]
                                              : null;
                                      final bool isConflict =
                                          otherRule != null &&
                                              otherRule.workspaceId !=
                                                  rule.workspaceId;
                                      final String shortName =
                                          DateHelpers.frenchShortWeekdaysMap[
                                                  day] ??
                                              '$day';

                                      final Color bgColor;
                                      final Color borderColor;
                                      final Color fgColor;
                                      Widget? leadingIcon;
                                      final String labelText;

                                      if (isSelectedHere) {
                                        bgColor = theme.colorScheme.primary;
                                        borderColor = theme.colorScheme.primary;
                                        fgColor = theme.colorScheme.onPrimary;
                                        leadingIcon = Icon(
                                          Icons.check_rounded,
                                          size: 15,
                                          color: fgColor,
                                        );
                                        labelText = shortName;
                                      } else if (isConflict) {
                                        bgColor = Colors.amber.withValues(
                                          alpha: isDark ? 0.2 : 0.16,
                                        );
                                        borderColor = isDark
                                            ? Colors.amber.shade400
                                            : Colors.orange.shade700;
                                        fgColor = isDark
                                            ? Colors.amber.shade200
                                            : Colors.orange.shade900;
                                        leadingIcon = Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 15,
                                          color: fgColor,
                                        );
                                        labelText =
                                            '$shortName • ${otherRule.workspaceName}';
                                      } else {
                                        bgColor = theme.colorScheme.surface;
                                        borderColor =
                                            theme.colorScheme.outlineVariant;
                                        fgColor = theme.colorScheme.onSurface;
                                        labelText = shortName;
                                      }

                                      return Material(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(20),
                                        child: InkWell(
                                          key: ValueKey<String>(
                                            'rule_day_chip_${rule.workspaceId}_$day',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          onTap: () => onRuleDayPressed(
                                            rule,
                                            day,
                                            otherRule,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: borderColor,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                if (leadingIcon !=
                                                    null) ...<Widget>[
                                                  leadingIcon,
                                                  const SizedBox(width: 5),
                                                ],
                                                Flexible(
                                                  child: Text(
                                                    labelText,
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          isSelectedHere ||
                                                                  isConflict
                                                              ? FontWeight.bold
                                                              : FontWeight.w500,
                                                      color: fgColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
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
                        }).toList(),
                      ),
                    ),
                ],
              ),
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
