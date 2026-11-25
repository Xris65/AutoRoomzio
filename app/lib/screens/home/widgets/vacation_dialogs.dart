import 'package:flutter/material.dart';
import '../../../utils/date_helpers.dart';

/// Result returned when the user confirms a new vacation range in [showAddVacationFlow].
class VacationAddResult {
  final DateTimeRange range;
  final List<String> conflicts;
  final List<String> toCleanLocally;

  const VacationAddResult({
    required this.range,
    required this.conflicts,
    required this.toCleanLocally,
  });
}

/// Interactive range-picker flow for adding a vacation period with DST-safe
/// calendar day iteration and confirmation if existing bookings overlap.
Future<VacationAddResult?> showAddVacationFlow(
  BuildContext context, {
  required Set<String> requestedDates,
  required Set<String> bookedDates,
  required Map<String, String> bookedElsewhereMap,
}) async {
  final DateTime today = normalizeLocalDate(DateTime.now());
  DateTimeRange? picked;
  bool userConfirmed = false;
  final List<String> conflicts = <String>[];
  final List<String> toCleanLocally = <String>[];

  while (!userConfirmed) {
    if (!context.mounted) return null;
    picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: addCalendarDays(today, 365),
      initialDateRange: picked,
      saveText: 'VALIDER',
    );

    if (picked == null) return null;

    conflicts.clear();
    toCleanLocally.clear();
    final int daySpan = calendarDaysBetween(picked.start, picked.end);
    for (int i = 0; i <= daySpan; i++) {
      final DateTime d = addCalendarDays(picked.start, i);
      final String dateStr = DateHelpers.formatIsoDate(d);

      if (requestedDates.contains(dateStr)) {
        toCleanLocally.add(dateStr);
      }

      if (bookedDates.contains(dateStr) ||
          bookedElsewhereMap.containsKey(dateStr)) {
        conflicts.add(dateStr);
        if (!toCleanLocally.contains(dateStr)) {
          toCleanLocally.add(dateStr);
        }
      }
    }

    if (conflicts.isNotEmpty) {
      if (!context.mounted) return null;
      final DateTimeRange p = picked;
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Réservations existantes'),
          content: Text(
            'Pour vos congés du ${p.start.day}/${p.start.month} au ${p.end.day}/${p.end.month}, vous avez des réservations confirmées :\n\n${conflicts.map<String>((String d) => '• $d').join('\n')}\n\nVoulez-vous ajouter ce congé et annuler automatiquement ces journées ?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('RECTIFIER'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('CONFIRMER'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        userConfirmed = true;
      }
    } else {
      userConfirmed = true;
    }
  }

  if (picked == null || !userConfirmed) return null;
  return VacationAddResult(
    range: picked,
    conflicts: List<String>.unmodifiable(conflicts),
    toCleanLocally: List<String>.unmodifiable(toCleanLocally),
  );
}
