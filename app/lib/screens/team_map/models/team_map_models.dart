import '../../../models/colleague.dart';
import '../../../models/desk_occupant.dart';
import '../../../utils/date_helpers.dart';
import '../../../utils/workspace_helpers.dart';

/// Résumé d'occupation d'une pièce/zone pour la barre de filtres.
class RoomSummary {
  final String roomName;
  final int totalOccupants;
  final List<DeskOccupant> favoriteOccupants;

  bool get hasFavorites => favoriteOccupants.isNotEmpty;

  const RoomSummary({
    required this.roomName,
    required this.totalOccupants,
    required this.favoriteOccupants,
  });
}

/// Représentation dédupliquée d'un occupant assis et de son poste associé.
class SeatedOccupantItem {
  final DeskOccupant occupant;
  final Map<String, dynamic> workspace;
  final String roomName;
  final String deskLabel;
  final bool isFavorite;

  const SeatedOccupantItem({
    required this.occupant,
    required this.workspace,
    required this.roomName,
    required this.deskLabel,
    required this.isFavorite,
  });
}

/// Helpers purs (sans état UI) pour la carte d'équipe.
class TeamMapHelpers {
  const TeamMapHelpers._();

  /// Retourne les jours visibles de la semaine contenant [baseDate] (anti-DST).
  static List<DateTime> getVisibleWeekDays(
    DateTime baseDate, {
    required bool hideWeekends,
  }) {
    final normalized = normalizeLocalDate(baseDate);
    final monday = addCalendarDays(normalized, -(normalized.weekday - 1));
    final count = hideWeekends ? 5 : 7;
    return List<DateTime>.generate(
      count,
      (int i) => addCalendarDays(monday, i),
    );
  }

  /// Clé stable d'identification d'un occupant pour la déduplication.
  static String occupantUniqueKey(DeskOccupant occ) {
    final id = occ.occupantId?.trim();
    if (id != null && id.isNotEmpty) {
      return 'id:${id.toLowerCase()}';
    }
    final email = occ.occupantEmail?.trim();
    if (email != null && email.isNotEmpty) {
      return 'email:${email.toLowerCase()}';
    }
    return 'name:${occ.occupantName.trim().toLowerCase()}';
  }

  /// Vérifie si [occupant] possède une identité explicite (ID, email ou nom non générique).
  static bool hasExplicitOccupantIdentity(DeskOccupant occupant) {
    if (occupant.isMe) return true;
    final occId = occupant.occupantId?.trim() ?? '';
    if (occId.isNotEmpty) return true;
    final occEmail = occupant.occupantEmail?.trim() ?? '';
    if (occEmail.isNotEmpty) return true;
    final normalizedName = occupant.occupantName.trim().toLowerCase();
    return normalizedName.isNotEmpty && normalizedName != 'occupant';
  }

  /// Détermine si [occupant] correspond réellement à un collègue favori
  /// par ID utilisateur, email ou nom normalisé.
  ///
  /// Un [fallbackWorkspaceIds] ne doit être utilisé que lorsque l'occupant
  /// ne porte aucune identité explicite contredisant le favori.
  static bool isOccupantFavorite(
    DeskOccupant occupant, {
    required Set<String> favoriteIds,
    required Set<String> favoriteEmailsNormalized,
    required Set<String> favoriteNamesNormalized,
    Set<String> fallbackWorkspaceIds = const <String>{},
  }) {
    if (occupant.isMe) return false;

    final occId = occupant.occupantId?.trim();
    if (occId != null && occId.isNotEmpty) {
      if (favoriteIds.contains(occId) ||
          favoriteIds.contains(occId.toLowerCase())) {
        return true;
      }
    }

    final occEmail = occupant.occupantEmail?.trim().toLowerCase();
    if (occEmail != null && occEmail.isNotEmpty) {
      if (favoriteEmailsNormalized.contains(occEmail) ||
          favoriteIds.contains(occEmail)) {
        return true;
      }
    }

    final normalizedName = occupant.occupantName.trim().toLowerCase();
    if (normalizedName.isNotEmpty &&
        favoriteNamesNormalized.contains(normalizedName)) {
      return true;
    }

    if (!hasExplicitOccupantIdentity(occupant) &&
        fallbackWorkspaceIds.isNotEmpty) {
      final wsLower = occupant.workspaceId.trim().toLowerCase();
      if (wsLower.isNotEmpty &&
          (fallbackWorkspaceIds.contains(occupant.workspaceId) ||
              fallbackWorkspaceIds.contains(wsLower))) {
        return true;
      }
    }

    return false;
  }

  /// Calcule les `workspaceId` favoris effectifs pour [occupants] sans faux positifs :
  /// - Si un occupant correspond à un favori (par ID, email ou nom), son bureau est inclus.
  /// - Un `deskName` enregistré sur un favori n'est inclus en fallback que s'il n'est
  ///   pas occupé par une personne connue non-favorite (anti faux-positif Or).
  static Set<String> computeEffectiveFavoriteWorkspaceIds({
    required List<Colleague> favorites,
    required Map<String, DeskOccupant> occupants,
    required List<Map<String, dynamic>> allWorkspaces,
    required Set<String> favoriteIds,
    required Set<String> favoriteEmailsNormalized,
    required Set<String> favoriteNamesNormalized,
  }) {
    final effective = <String>{};
    final occupantsByWsLower = <String, DeskOccupant>{};

    for (final occ in occupants.values) {
      final wsLower = occ.workspaceId.trim().toLowerCase();
      if (wsLower.isNotEmpty) {
        occupantsByWsLower[wsLower] = occ;
      }
      if (isOccupantFavorite(
        occ,
        favoriteIds: favoriteIds,
        favoriteEmailsNormalized: favoriteEmailsNormalized,
        favoriteNamesNormalized: favoriteNamesNormalized,
      )) {
        if (occ.workspaceId.isNotEmpty) {
          effective.add(occ.workspaceId);
          effective.add(wsLower);
        }
        final ws = resolveWorkspaceById(allWorkspaces, occ.workspaceId);
        final resolvedId = ws['id']?.toString() ?? '';
        final resolvedName = ws['name']?.toString() ?? '';
        if (resolvedId.isNotEmpty) {
          effective.add(resolvedId);
          effective.add(resolvedId.toLowerCase());
        }
        if (resolvedName.isNotEmpty) {
          effective.add(resolvedName);
          effective.add(resolvedName.toLowerCase());
        }
      }
    }

    for (final fav in favorites) {
      final deskName = fav.deskName?.trim() ?? '';
      if (deskName.isEmpty) continue;
      final deskLower = deskName.toLowerCase();
      final matchedWs = resolveWorkspaceById(allWorkspaces, deskName);
      final wsId = matchedWs['id']?.toString().trim() ?? '';
      final wsIdLower = wsId.toLowerCase();

      final occupantOnDesk = occupantsByWsLower[deskLower] ??
          (wsIdLower.isNotEmpty ? occupantsByWsLower[wsIdLower] : null);

      if (occupantOnDesk == null) {
        // Bureau libre : aucun risque de faux-positif sur la carte.
        continue;
      }

      if (isOccupantFavorite(
        occupantOnDesk,
        favoriteIds: favoriteIds,
        favoriteEmailsNormalized: favoriteEmailsNormalized,
        favoriteNamesNormalized: favoriteNamesNormalized,
      )) {
        effective.add(deskName);
        effective.add(deskLower);
        if (wsId.isNotEmpty) {
          effective.add(wsId);
          effective.add(wsIdLower);
        }
      } else if (!hasExplicitOccupantIdentity(occupantOnDesk)) {
        // Fallback uniquement si l'occupant n'a aucune identité explicite qui contredit le favori.
        effective.add(deskName);
        effective.add(deskLower);
        if (wsId.isNotEmpty) {
          effective.add(wsId);
          effective.add(wsIdLower);
        }
      }
    }

    return effective;
  }

  /// Retrouve le workspace correspondant à [wsId] (par `id` ou `name`, insensible à la casse).
  static Map<String, dynamic> resolveWorkspaceById(
    List<Map<String, dynamic>> allWorkspaces,
    String wsId,
  ) {
    final target = wsId.toLowerCase();
    for (final w in allWorkspaces) {
      if (w['id']?.toString().toLowerCase() == target ||
          w['name']?.toString().toLowerCase() == target) {
        return w;
      }
    }
    return <String, dynamic>{'id': wsId};
  }

  /// Retourne le nom lisible d'un bureau depuis [allWorkspaces] ou [wsId] par défaut.
  static String resolveDeskDisplayName(
    List<Map<String, dynamic>> allWorkspaces,
    String wsId,
  ) {
    final ws = resolveWorkspaceById(allWorkspaces, wsId);
    return ws['name']?.toString() ??
        ws['workspaceName']?.toString() ??
        wsId;
  }

  /// Construit la liste dédupliquée et triée des occupants présents sur l'étage.
  static List<SeatedOccupantItem> buildSeatedOccupants({
    required Map<String, DeskOccupant> occupants,
    required List<Map<String, dynamic>> allWorkspaces,
    required Set<String> favoriteIds,
    required Set<String> favoriteEmailsNormalized,
    required Set<String> favoriteNamesNormalized,
  }) {
    final seenWorkspaceIds = <String>{};
    final seatedList = <SeatedOccupantItem>[];

    for (final occ in occupants.values) {
      final wsKey = occ.workspaceId.toLowerCase();
      if (!seenWorkspaceIds.add(wsKey)) continue;

      final ws = resolveWorkspaceById(allWorkspaces, occ.workspaceId);
      final rName = extractRoomName(ws);
      final name = ws['name']?.toString() ?? occ.workspaceId;
      final parts = name.split('-');
      final deskLabel =
          parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : name;
      final isFav = isOccupantFavorite(
        occ,
        favoriteIds: favoriteIds,
        favoriteEmailsNormalized: favoriteEmailsNormalized,
        favoriteNamesNormalized: favoriteNamesNormalized,
      );

      seatedList.add(
        SeatedOccupantItem(
          occupant: occ,
          workspace: ws,
          roomName: rName,
          deskLabel: deskLabel,
          isFavorite: isFav,
        ),
      );
    }

    seatedList.sort((SeatedOccupantItem a, SeatedOccupantItem b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      if (a.occupant.isMe && !b.occupant.isMe) return -1;
      if (!a.occupant.isMe && b.occupant.isMe) return 1;
      return a.occupant.occupantName
          .toLowerCase()
          .compareTo(b.occupant.occupantName.toLowerCase());
    });

    return seatedList;
  }

  /// Construit les résumés de salles triés (favoris desc, occupation desc, nom asc).
  static List<RoomSummary> buildRoomSummaries({
    required Map<String, DeskOccupant> occupants,
    required List<Map<String, dynamic>> allWorkspaces,
    required Set<String> favoriteIds,
    required Set<String> favoriteEmailsNormalized,
    required Set<String> favoriteNamesNormalized,
  }) {
    final roomOccupants = <String, List<DeskOccupant>>{};
    final seenWorkspaceIds = <String>{};

    for (final occ in occupants.values) {
      if (!seenWorkspaceIds.add(occ.workspaceId.toLowerCase())) continue;

      final ws = resolveWorkspaceById(allWorkspaces, occ.workspaceId);
      final rName = extractRoomName(ws);
      if (rName.isNotEmpty) {
        roomOccupants.putIfAbsent(rName, () => <DeskOccupant>[]).add(occ);
      }
    }

    final list = roomOccupants.entries.map<RoomSummary>((
      MapEntry<String, List<DeskOccupant>> entry,
    ) {
      final occs = entry.value;
      final favs = occs
          .where(
            (DeskOccupant occ) => isOccupantFavorite(
              occ,
              favoriteIds: favoriteIds,
              favoriteEmailsNormalized: favoriteEmailsNormalized,
              favoriteNamesNormalized: favoriteNamesNormalized,
            ),
          )
          .toList();
      return RoomSummary(
        roomName: entry.key,
        totalOccupants: occs.length,
        favoriteOccupants: favs,
      );
    }).toList();

    list.sort((RoomSummary a, RoomSummary b) {
      final favComp =
          b.favoriteOccupants.length.compareTo(a.favoriteOccupants.length);
      if (favComp != 0) return favComp;
      final occComp = b.totalOccupants.compareTo(a.totalOccupants);
      if (occComp != 0) return occComp;
      return a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase());
    });

    return list;
  }

  /// Compte les collègues favoris uniques présents dans [occs].
  static int countUniqueFavorites(
    Map<String, DeskOccupant> occs, {
    required Set<String> favoriteIds,
    required Set<String> favoriteEmailsNormalized,
    required Set<String> favoriteNamesNormalized,
  }) {
    final seenPeople = <String>{};
    for (final occ in occs.values) {
      if (isOccupantFavorite(
        occ,
        favoriteIds: favoriteIds,
        favoriteEmailsNormalized: favoriteEmailsNormalized,
        favoriteNamesNormalized: favoriteNamesNormalized,
      )) {
        seenPeople.add(occupantUniqueKey(occ));
      }
    }
    return seenPeople.length;
  }

  /// Trouve le [DeskOccupant] correspondant à un collègue [fav] dans [occs].
  static DeskOccupant? findOccupantForColleague(
    Map<String, DeskOccupant> occs,
    Colleague fav,
  ) {
    for (final occ in occs.values) {
      if (occ.isMe) continue;
      if (occ.occupantId != null &&
          fav.id.isNotEmpty &&
          occ.occupantId!.toLowerCase() == fav.id.toLowerCase()) {
        return occ;
      }
      if (occ.occupantEmail != null &&
          fav.email.isNotEmpty &&
          occ.occupantEmail!.toLowerCase() == fav.email.toLowerCase()) {
        return occ;
      }
      if (fav.name.trim().isNotEmpty &&
          occ.occupantName.trim().toLowerCase() ==
              fav.name.trim().toLowerCase()) {
        return occ;
      }
    }
    return null;
  }

  /// Retrouve toutes les entrées favorites correspondant à [occupant].
  static List<Colleague> findMatchingFavoritesForOccupant(
    List<Colleague> favorites,
    DeskOccupant occupant,
  ) {
    final occId = occupant.occupantId?.trim().toLowerCase() ?? '';
    final occEmail = occupant.occupantEmail?.trim().toLowerCase() ?? '';
    final occName = occupant.occupantName.trim().toLowerCase();

    return favorites.where((Colleague fav) {
      final favId = fav.id.trim().toLowerCase();
      final favEmail = fav.email.trim().toLowerCase();
      final favName = fav.name.trim().toLowerCase();

      if (occId.isNotEmpty && favId.isNotEmpty && favId == occId) {
        return true;
      }
      if (occEmail.isNotEmpty &&
          ((favEmail.isNotEmpty && favEmail == occEmail) ||
              (favId.isNotEmpty && favId == occEmail))) {
        return true;
      }
      if (occName.isNotEmpty && favName.isNotEmpty && favName == occName) {
        return true;
      }
      return false;
    }).toList();
  }
}
