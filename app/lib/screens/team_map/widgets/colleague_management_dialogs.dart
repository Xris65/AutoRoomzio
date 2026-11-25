import 'package:flutter/material.dart';
import '../../../api_service.dart';
import '../../../models/colleague.dart';
import '../../../models/desk_occupant.dart';
import '../../../storage_service.dart';
import '../../../widgets/colleague_selection_dialog.dart';
import '../models/team_map_models.dart';

/// Dialogues de confirmation de conflits, de sélection de collègue pour
/// délégation et d'ajout de collègue favori externe (avec `dispose()` propre).
class ColleagueManagementDialogs {
  const ColleagueManagementDialogs._();

  /// Demande confirmation avant de remplacer la réservation existante de l'utilisateur.
  static Future<bool> showReplaceMyBookingConfirmation({
    required BuildContext context,
    required String existingDeskName,
    required String newDeskName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remplacer votre réservation ?'),
        content: Text(
          'Vous avez déjà réservé la place $existingDeskName pour cette journée.\n\n'
          'En réservant la place $newDeskName, votre place actuelle sera automatiquement libérée et remplacée.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer le remplacement'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Demande confirmation avant de remplacer une règle d'automatisation sur un jour en conflit.
  static Future<bool> showAutomationDayConflict({
    required BuildContext context,
    required String dayName,
    required String existingWorkspaceName,
    required String targetDeskName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dlgCtx) => AlertDialog(
        title: Text('Conflit sur le $dayName'),
        content: Text(
          'Le $dayName est déjà automatisé sur la place "$existingWorkspaceName".\n\n'
          'Voulez-vous remplacer cette place par "$targetDeskName" pour le $dayName ?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('confirm_replace_day_button'),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Ouvre le sélecteur de collègue pour réserver [deskName] à [dateIso]
  /// en signalant les collègues déjà installés ce jour-là.
  static Future<Colleague?> showColleagueSelectionForDesk({
    required BuildContext context,
    required String dateIso,
    required String deskName,
    required RoomzApiService apiService,
    required StorageService storageService,
    required Map<String, DeskOccupant> occupants,
    required List<Map<String, dynamic>> allWorkspaces,
  }) {
    final alreadySeatedMap = <String, String>{};
    for (final occ in occupants.values) {
      final seatedDeskName = TeamMapHelpers.resolveDeskDisplayName(
        allWorkspaces,
        occ.workspaceId,
      );

      final occId = occ.occupantId;
      if (occId != null && occId.isNotEmpty) {
        alreadySeatedMap[occId] = seatedDeskName;
        alreadySeatedMap[occId.toLowerCase()] = seatedDeskName;
      }
      if (occ.occupantName.isNotEmpty) {
        alreadySeatedMap[occ.occupantName] = seatedDeskName;
        alreadySeatedMap[occ.occupantName.toLowerCase()] = seatedDeskName;
      }
      final occEmail = occ.occupantEmail;
      if (occEmail != null && occEmail.isNotEmpty) {
        alreadySeatedMap[occEmail] = seatedDeskName;
        alreadySeatedMap[occEmail.toLowerCase()] = seatedDeskName;
      }
    }

    return showDialog<Colleague>(
      context: context,
      builder: (BuildContext ctx) => ColleagueSelectionDialog(
        date: dateIso,
        deskName: deskName,
        apiService: apiService,
        storageService: storageService,
        alreadySeatedColleagues: alreadySeatedMap,
      ),
    );
  }

  /// Ouvre le dialogue de gestion complète des collègues favoris.
  static Future<void> showFavoritesManager({
    required BuildContext context,
    required String dateIso,
    required RoomzApiService apiService,
    required StorageService storageService,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => ColleagueSelectionDialog(
        date: dateIso,
        apiService: apiService,
        storageService: storageService,
        isManagementMode: true,
      ),
    );
  }

  /// Ouvre un dialogue dédié pour ajouter rapidement un collègue favori externe.
  static Future<Colleague?> showAddExternalFavoriteDialog(
    BuildContext context,
  ) {
    return showDialog<Colleague>(
      context: context,
      builder: (BuildContext ctx) => const _AddExternalFavoriteDialog(),
    );
  }
}

class _AddExternalFavoriteDialog extends StatefulWidget {
  const _AddExternalFavoriteDialog();

  @override
  State<_AddExternalFavoriteDialog> createState() =>
      _AddExternalFavoriteDialogState();
}

class _AddExternalFavoriteDialogState
    extends State<_AddExternalFavoriteDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _validationError = 'Veuillez saisir le nom du collègue.';
      });
      return;
    }
    Navigator.pop(
      context,
      Colleague(
        id: 'ext_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        email: email,
        isFavorite: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Ajouter un collègue favori'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom complet',
              hintText: 'Ex: Marie Curie',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email (optionnel)',
              hintText: 'Ex: marie.curie@entreprise.fr',
            ),
          ),
          if (_validationError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _validationError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
