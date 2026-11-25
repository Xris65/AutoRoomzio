import 'package:flutter/material.dart';
import '../../../storage_service.dart';
import '../../../utils/date_helpers.dart';
import 'colleague_management_dialogs.dart';

/// Feuille modale d'automatisation récurrente d'un bureau depuis la carte 2D.
class DeskAutomationSheet extends StatefulWidget {
  final String wsId;
  final String deskName;
  final String siteId;
  final String floorId;
  final bool hideWeekends;
  final List<AutomationRule> initialRules;
  final StorageService storageService;

  const DeskAutomationSheet({
    super.key,
    required this.wsId,
    required this.deskName,
    required this.siteId,
    required this.floorId,
    required this.hideWeekends,
    required this.initialRules,
    required this.storageService,
  });

  static Future<void> show({
    required BuildContext context,
    required String wsId,
    required String deskName,
    required String siteId,
    required String floorId,
    required bool hideWeekends,
    required StorageService storageService,
  }) async {
    final rules = await storageService.getAutomationRules();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext _) => DeskAutomationSheet(
        wsId: wsId,
        deskName: deskName,
        siteId: siteId,
        floorId: floorId,
        hideWeekends: hideWeekends,
        initialRules: rules,
        storageService: storageService,
      ),
    );
  }

  @override
  State<DeskAutomationSheet> createState() => _DeskAutomationSheetState();
}

class _DeskAutomationSheetState extends State<DeskAutomationSheet> {
  late List<AutomationRule> _rules;
  late List<int> _daysToShow;

  @override
  void initState() {
    super.initState();
    _rules = List<AutomationRule>.from(widget.initialRules);
    _daysToShow = widget.hideWeekends
        ? <int>[1, 2, 3, 4, 5]
        : <int>[1, 2, 3, 4, 5, 6, 7];
  }

  Future<void> _persistChanges(List<int> nextDays) async {
    final idx = _rules.indexWhere(
      (AutomationRule r) =>
          r.workspaceId.toLowerCase() == widget.wsId.toLowerCase(),
    );
    if (nextDays.isEmpty) {
      if (idx >= 0) {
        _rules.removeAt(idx);
      }
    } else if (idx >= 0) {
      _rules[idx] = _rules[idx].copyWith(
        siteId: widget.siteId.isNotEmpty ? widget.siteId : _rules[idx].siteId,
        floorId:
            widget.floorId.isNotEmpty ? widget.floorId : _rules[idx].floorId,
        workspaceName: widget.deskName,
        days: nextDays,
      );
    } else {
      _rules.add(
        AutomationRule(
          id: widget.wsId,
          siteId: widget.siteId,
          floorId: widget.floorId,
          workspaceId: widget.wsId,
          workspaceName: widget.deskName,
          days: nextDays,
        ),
      );
    }
    await widget.storageService.saveAutomationRules(_rules);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final weekdayMap = <int, AutomationRule>{
      for (final r in _rules)
        for (final d in r.days) d: r,
    };
    final existingIdx = _rules.indexWhere(
      (AutomationRule r) =>
          r.workspaceId.toLowerCase() == widget.wsId.toLowerCase(),
    );
    final currentRule = existingIdx >= 0
        ? _rules[existingIdx]
        : AutomationRule(
            id: widget.wsId,
            siteId: widget.siteId,
            floorId: widget.floorId,
            workspaceId: widget.wsId,
            workspaceName: widget.deskName,
            days: const <int>[],
          );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.auto_mode_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Automatiser ${widget.deskName}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Choisissez les jours récurrents pour ce bureau',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._daysToShow.map<Widget>((int day) {
              final isActiveHere = currentRule.days.contains(day);
              final otherRule = !isActiveHere ? weekdayMap[day] : null;
              final isConflict = otherRule != null &&
                  otherRule.workspaceId.toLowerCase() !=
                      widget.wsId.toLowerCase();
              final dayName =
                  DateHelpers.frenchWeekdaysMap[day] ?? 'Jour $day';
              final shortName =
                  DateHelpers.frenchShortWeekdaysMap[day] ?? '$day';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isActiveHere
                      ? theme.colorScheme.primaryContainer
                          .withValues(alpha: isDark ? 0.5 : 0.7)
                      : (isConflict
                          ? Colors.amber.withValues(alpha: isDark ? 0.18 : 0.14)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('desk_auto_day_$day'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      if (isActiveHere) {
                        final nextDays = List<int>.from(currentRule.days)
                          ..remove(day);
                        await _persistChanges(nextDays);
                      } else if (isConflict) {
                        final confirmed = await ColleagueManagementDialogs
                            .showAutomationDayConflict(
                          context: context,
                          dayName: dayName,
                          existingWorkspaceName: otherRule.workspaceName,
                          targetDeskName: widget.deskName,
                        );
                        if (!confirmed) return;
                        final otherIdx = _rules.indexWhere(
                          (AutomationRule r) =>
                              r.workspaceId.toLowerCase() ==
                              otherRule.workspaceId.toLowerCase(),
                        );
                        if (otherIdx >= 0) {
                          final otherDays = List<int>.from(
                            _rules[otherIdx].days,
                          )..remove(day);
                          _rules[otherIdx] =
                              _rules[otherIdx].copyWith(days: otherDays);
                        }
                        final nextDays = List<int>.from(currentRule.days)
                          ..add(day);
                        await _persistChanges(nextDays);
                      } else {
                        final nextDays = List<int>.from(currentRule.days)
                          ..add(day);
                        await _persistChanges(nextDays);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActiveHere
                              ? theme.colorScheme.primary
                              : (isConflict
                                  ? (isDark
                                      ? Colors.amber.shade400
                                      : Colors.orange.shade700)
                                  : theme.dividerColor.withValues(alpha: 0.25)),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            isActiveHere
                                ? Icons.check_circle_rounded
                                : (isConflict
                                    ? Icons.swap_horiz_rounded
                                    : Icons.radio_button_unchecked_rounded),
                            color: isActiveHere
                                ? theme.colorScheme.primary
                                : (isConflict
                                    ? (isDark
                                        ? Colors.amber.shade300
                                        : Colors.orange.shade800)
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$dayName ($shortName)',
                              style: TextStyle(
                                fontWeight: isActiveHere || isConflict
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isConflict)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber
                                      .withValues(alpha: isDark ? 0.25 : 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.amber.shade400
                                        : Colors.orange.shade700,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  '⇄ ${otherRule.workspaceName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.amber.shade200
                                        : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('close_desk_automation_sheet_button'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminer'),
            ),
          ],
        ),
      ),
    );
  }
}
