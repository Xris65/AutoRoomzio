import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/automation_rule.dart';
import '../../../utils/delegation_display_helper.dart';

/// Displays the action bottom sheet for a tapped calendar/upcoming date.
Future<String?> showDateActionSheet(
  BuildContext context, {
  required String dateStr,
  required String? holidayName,
  required bool isDelegated,
  required String delegateName,
  required String delegateLocation,
  required String? delegateCreator,
  required bool isBooked,
  required bool isRequested,
  required bool isIgnored,
  required bool isElsewhere,
  required String? elsewhereName,
  required bool deskOccupiedByThirdParty,
  required String? occupiedByText,
  required bool isWeekendAndHidden,
  required bool isDelegatedOnMyDesk,
  required bool isBookableNow,
  required String? requestedWorkspaceName,
  required String? requestedWorkspaceId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (BuildContext sheetContext) {
      final bool isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final Color purpleColor =
          isDark ? Colors.purple.shade300 : Colors.purple.shade900;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Gestion du $dateStr',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (holidayName != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  key: const ValueKey<String>('holiday_banner_in_modal'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.celebration_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.amber.shade300
                            : Colors.amber.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Jour férié : $holidayName (Automatisation suspendue)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.amber.shade200
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isDelegated)
              ListTile(
                leading: Icon(Icons.group_off, color: purpleColor),
                title: Text(
                  'Annuler la délégation',
                  style: TextStyle(
                    color: purpleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  delegateCreator != null &&
                          delegateCreator.toLowerCase() !=
                              delegateName.toLowerCase()
                      ? 'Réservé pour $delegateName par $delegateCreator${delegateLocation.isNotEmpty ? ' sur $delegateLocation' : ''} ce jour-là.'
                      : 'Annule la réservation faite pour $delegateName${delegateLocation.isNotEmpty ? ' sur $delegateLocation' : ''} ce jour-là.',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(sheetContext, 'cancel_delegation'),
              ),
            if (!isBooked && !isRequested)
              if (deskOccupiedByThirdParty)
                ListTile(
                  leading: const Icon(Icons.person_off, color: Colors.grey),
                  title: const Text(
                    'Place indisponible',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    DelegationDisplayHelper.formatOccupiedSubtitle(
                      occupiedByText ?? '',
                    ),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                )
              else if (isWeekendAndHidden)
                const ListTile(
                  leading: Icon(Icons.weekend, color: Colors.grey),
                  title: Text(
                    'Les nouvelles réservations le week-end sont désactivées.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              else if (isElsewhere)
                ListTile(
                  leading: Icon(
                    Icons.person_off,
                    color: Colors.orange.shade900,
                  ),
                  title: Text(
                    'Libérer mon autre bureau (${elsewhereName ?? "Ailleurs"})',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Annule la réservation que vous avez faite sur cet autre bureau ce jour-là.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'cancel_elsewhere'),
                )
              else if (isDelegatedOnMyDesk)
                const SizedBox.shrink()
              else if (!kIsWeb || isBookableNow)
                ListTile(
                  leading: Icon(
                    isBookableNow
                        ? Icons.check_circle_outline
                        : Icons.pending_actions,
                    color: isBookableNow ? Colors.green : Colors.blue,
                  ),
                  title: Text(
                    isBookableNow
                        ? 'Réserver ce jour'
                        : 'Programmer (En attente)',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'reserve'),
                ),
            if (!isBooked &&
                !isDelegated &&
                !deskOccupiedByThirdParty &&
                !isWeekendAndHidden &&
                isBookableNow)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.purple.shade900.withValues(alpha: 0.4)
                        : Colors.purple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.group_add_outlined,
                    color: isDark
                        ? Colors.purple.shade300
                        : Colors.purple.shade800,
                  ),
                ),
                title: const Text(
                  'Réserver pour un collègue',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Sélectionner parmi vos favoris ou rechercher',
                ),
                onTap: () =>
                    Navigator.pop(sheetContext, 'reserve_for_colleague'),
              ),
            if (isRequested && !isBooked)
              ListTile(
                leading: const Icon(Icons.schedule, color: Colors.blue),
                title: Text(
                  requestedWorkspaceName != null
                      ? 'Bureau programmé : $requestedWorkspaceName'
                      : (requestedWorkspaceId != null
                          ? 'Bureau programmé : $requestedWorkspaceId'
                          : 'Programmation en attente'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: const Text(
                  "Ce bureau sera réservé automatiquement dès l'ouverture des créneaux (J-13).",
                  style: TextStyle(fontSize: 11),
                ),
              ),
            if (isBooked || isRequested)
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                title: Text(
                  isBooked ? 'Libérer la place' : 'Annuler la programmation',
                ),
                onTap: () => Navigator.pop(sheetContext, 'cancel'),
              ),
            if (!kIsWeb &&
                !isIgnored &&
                !isWeekendAndHidden &&
                !isElsewhere &&
                !isRequested &&
                !isBooked)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: const Text("Bloquer (Ignorer l'automatisation)"),
                onTap: () => Navigator.pop(sheetContext, 'block'),
              ),
            if (!kIsWeb && isIgnored && !isWeekendAndHidden)
              ListTile(
                leading: const Icon(Icons.lock_open, color: Colors.green),
                title: const Text('Débloquer ce jour'),
                onTap: () => Navigator.pop(sheetContext, 'unblock'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Confirmation dialog when assigning a weekday that already belongs to another [AutomationRule].
Future<bool> showRuleConflictDialog(
  BuildContext context, {
  required String dayName,
  required AutomationRule targetRule,
  required AutomationRule conflictingRule,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('Conflit sur le $dayName'),
      content: Text(
        'Le $dayName est déjà automatisé sur la place "${conflictingRule.workspaceName}".\n\n'
        'Voulez-vous remplacer cette place par "${targetRule.workspaceName}" pour le $dayName ?',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm_replace_day_button'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Remplacer'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
