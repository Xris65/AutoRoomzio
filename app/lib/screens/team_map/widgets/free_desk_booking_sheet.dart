import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../utils/date_helpers.dart';
import '../../../utils/workspace_helpers.dart';

/// Feuille modale de réservation d'un bureau libre (pour soi, pour un collègue,
/// programmation J>13 et accès à l'automatisation récurrente).
class FreeDeskBookingSheet extends StatelessWidget {
  final Map<String, dynamic> workspace;
  final DateTime selectedDate;
  final bool isPending;
  final bool isPast;
  final bool isBeyond13Days;
  final bool isWeekendBlocked;
  final VoidCallback onCancelProgramming;
  final VoidCallback onProgramInAdvance;
  final VoidCallback onReserveForMe;
  final VoidCallback onReserveForColleague;
  final void Function(String wsId, String deskName) onOpenAutomation;

  const FreeDeskBookingSheet({
    super.key,
    required this.workspace,
    required this.selectedDate,
    required this.isPending,
    required this.isPast,
    required this.isBeyond13Days,
    required this.isWeekendBlocked,
    required this.onCancelProgramming,
    required this.onProgramInAdvance,
    required this.onReserveForMe,
    required this.onReserveForColleague,
    required this.onOpenAutomation,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> workspace,
    required DateTime selectedDate,
    required bool isPending,
    required bool hideWeekends,
    required VoidCallback onCancelProgramming,
    required VoidCallback onProgramInAdvance,
    required VoidCallback onReserveForMe,
    required VoidCallback onReserveForColleague,
    required void Function(String wsId, String deskName) onOpenAutomation,
  }) {
    final today = normalizeLocalDate(DateTime.now());
    final target = normalizeLocalDate(selectedDate);
    final diffInDays = calendarDaysBetween(today, target);
    final isPast = diffInDays < 0;
    final isBeyond13Days = diffInDays > 13;
    final isWeekend = selectedDate.weekday == DateTime.saturday ||
        selectedDate.weekday == DateTime.sunday;
    final isWeekendBlocked = hideWeekends && isWeekend;

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => FreeDeskBookingSheet(
        workspace: workspace,
        selectedDate: selectedDate,
        isPending: isPending,
        isPast: isPast,
        isBeyond13Days: isBeyond13Days,
        isWeekendBlocked: isWeekendBlocked,
        onCancelProgramming: onCancelProgramming,
        onProgramInAdvance: onProgramInAdvance,
        onReserveForMe: onReserveForMe,
        onReserveForColleague: onReserveForColleague,
        onOpenAutomation: onOpenAutomation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wsId = workspace['id']?.toString() ?? '';
    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;
    final roomName =
        workspace['roomName']?.toString() ?? extractRoomName(workspace);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.desk,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        deskName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (roomName.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          roomName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isPending ? 'En attente' : 'Libre',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isPending ? Colors.blue.shade800 : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      DateHelpers.formatFrenchDate(selectedDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isWeekendBlocked) ...<Widget>[
              _InfoBanner(
                backgroundColor: Colors.orange.withValues(alpha: 0.15),
                borderColor: Colors.orange.shade700.withValues(alpha: 0.5),
                icon: Icons.event_busy,
                iconColor: Colors.orange.shade900,
                text: 'Réservations fermées le weekend',
                textStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.brightness == Brightness.dark
                      ? Colors.orange.shade200
                      : Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 16),
            ] else if (isPast) ...<Widget>[
              _InfoBanner(
                backgroundColor: Colors.amber.withValues(alpha: 0.15),
                borderColor: Colors.amber.shade700.withValues(alpha: 0.5),
                icon: Icons.info_outline,
                iconColor: Colors.amber.shade900,
                text:
                    "La réservation directe n'est pas disponible pour une date passée.",
                textStyle: TextStyle(
                  fontSize: 12,
                  color: theme.brightness == Brightness.dark
                      ? Colors.amber.shade200
                      : Colors.amber.shade900,
                ),
              ),
              const SizedBox(height: 16),
            ] else if (isPending) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.blue.shade700.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.pending_actions,
                      color: Colors.blue.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Programmation en attente',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Ce bureau sera réservé automatiquement par AutoRoomzio dès l'ouverture des créneaux (J-13).",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('cancel_programming_button'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annuler la programmation'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onCancelProgramming();
                },
              ),
              const SizedBox(height: 8),
            ] else if (isBeyond13Days) ...<Widget>[
              if (!kIsWeb) ...<Widget>[
                FilledButton.icon(
                  key: const ValueKey('program_desk_button'),
                  icon: const Icon(Icons.schedule_rounded),
                  label: const Text('Programmer ce bureau (En attente)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onProgramInAdvance();
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('reserve_for_colleague_beyond13_button'),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Réserver pour un collègue'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: null,
                ),
                const SizedBox(height: 4),
                Text(
                  'La réservation pour un collègue est limitée à J+13.',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ] else ...<Widget>[
                _InfoBanner(
                  backgroundColor: Colors.blueGrey.withValues(alpha: 0.15),
                  borderColor: Colors.blueGrey.shade400.withValues(alpha: 0.5),
                  icon: Icons.info_outline,
                  iconColor: Colors.blueGrey.shade700,
                  text:
                      "La réservation directe n'est pas encore ouverte pour cette date (créneaux ouverts jusqu'à 13 jours à l'avance).",
                  textStyle: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ] else ...<Widget>[
              FilledButton.icon(
                key: const ValueKey('reserve_for_me_button'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Réserver ce bureau pour moi'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onReserveForMe();
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('reserve_for_colleague_button'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Réserver ce bureau pour un collègue'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onReserveForColleague();
                },
              ),
              const SizedBox(height: 8),
            ],
            if (!kIsWeb) ...<Widget>[
              OutlinedButton.icon(
                key: const ValueKey('automate_desk_button'),
                icon: const Icon(Icons.auto_mode_rounded),
                label: const Text('Automatiser ce bureau'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  onOpenAutomation(wsId, deskName);
                },
              ),
              const SizedBox(height: 8),
            ],
            TextButton(
              key: const ValueKey('close_free_desk_sheet_button'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle textStyle;

  const _InfoBanner({
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: textStyle),
          ),
        ],
      ),
    );
  }
}
