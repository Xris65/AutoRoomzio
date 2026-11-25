// Utilitaires centralisés pour les espaces de travail et plans 2D.

const Set<String> _nonDeskWorkspaceTypes = <String>{
  'parking',
  'phonebooth',
  'phone_booth',
  'phone booth',
  'meetingroom',
  'meeting_room',
  'meeting room',
  'room',
  'zone',
  'area',
  'polygon',
  'feature',
  'wall',
  'corridor',
  'elevator',
  'stairs',
  'restroom',
  'toilet',
  'kitchen',
  '2',
  '3',
  '4',
};

const Set<String> _deskWorkspaceTypes = <String>{
  'desk',
  'workspace',
  '1',
};

/// Détermine si un workspace issu de l'API MyRoomz est réservable en tant que bureau.
bool isBookableWorkspace(Map<String, dynamic> ws) {
  if (ws['isBookable'] == false ||
      ws['isReservable'] == false ||
      ws['bookable'] == false) {
    return false;
  }

  final Object? rawType = ws['workspaceType'] ?? ws['type'];
  if (rawType is int) {
    if (rawType >= 2 || rawType < 0) {
      return false;
    }
  } else if (rawType != null) {
    final normalizedType = rawType.toString().trim().toLowerCase();
    if (_nonDeskWorkspaceTypes.contains(normalizedType)) {
      return false;
    }
  }

  if (ws['isBookable'] == true ||
      ws['isReservable'] == true ||
      ws['bookable'] == true) {
    return true;
  }

  if (rawType == 1) {
    return true;
  }
  if (rawType != null) {
    final normalizedType = rawType.toString().trim().toLowerCase();
    return _deskWorkspaceTypes.contains(normalizedType);
  }

  return false;
}

/// Extrait le nom de pièce/zone depuis un objet workspace.
String extractRoomName(Map<String, dynamic> ws, {bool trim = true}) {
  final rawRoom = ws['roomName']?.toString().trim();
  if (rawRoom != null && rawRoom.isNotEmpty) {
    return rawRoom;
  }
  final name = ws['name']?.toString() ?? ws['id']?.toString() ?? '';
  final lastDash = name.lastIndexOf('-');
  if (lastDash > 0 && lastDash < name.length - 1) {
    final suffix = name.substring(lastDash + 1).trim();
    final prefix = name.substring(0, lastDash).trim();
    if (prefix.isNotEmpty && suffix.isNotEmpty && !suffix.contains(' ')) {
      return prefix;
    }
  }
  return trim ? name.trim() : name;
}

/// Parse les features GeoJSON d'un plan d'étage et génère une grille synthétique
/// de secours à partir des bureaux réservables de [allWs] si le plan est vide.
List<Map<String, dynamic>> parseFloorFeaturesWithFallback(
  dynamic planData,
  List<Map<String, dynamic>> allWs,
) {
  List<Map<String, dynamic>> features = <Map<String, dynamic>>[];
  if (planData is List<Object?>) {
    features = planData
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } else if (planData is Map<Object?, Object?>) {
    final Object raw =
        planData['features'] ?? planData['data'] ?? const <Object?>[];
    if (raw is List<Object?>) {
      features = raw
          .whereType<Map<Object?, Object?>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }

  final bookableDesks = allWs.where(isBookableWorkspace).toList();
  if (features.isEmpty && bookableDesks.isNotEmpty) {
    int col = 0;
    int row = 0;
    const int desksPerRow = 6;
    for (final ws in bookableDesks) {
      final wsId =
          ws['id']?.toString() ?? ws['workspaceId']?.toString() ?? '';
      final wsName = ws['name']?.toString() ?? wsId;
      final Object? rawWsType = ws['workspaceType'] ?? ws['type'];
      final String normalizedType;
      if (rawWsType == null || rawWsType == 1) {
        normalizedType = 'Desk';
      } else {
        final strType = rawWsType.toString().trim();
        final lower = strType.toLowerCase();
        normalizedType =
            (lower == 'desk' || lower == 'workspace' || lower == '1')
                ? 'Desk'
                : strType;
      }

      final x = 50.0 + (col * 85.0);
      final y = 50.0 + (row * 65.0);
      features.add(<String, dynamic>{
        'type': 'Feature',
        'properties': <String, dynamic>{
          'workspaceId': wsId,
          'id': wsId,
          'name': wsName,
          'workspaceType': normalizedType,
        },
        'geometry': <String, dynamic>{
          'type': 'Polygon',
          'coordinates': <List<List<double>>>[
            <List<double>>[
              <double>[x, y],
              <double>[x + 72.0, y],
              <double>[x + 72.0, y + 48.0],
              <double>[x, y + 48.0],
              <double>[x, y],
            ],
          ],
        },
      });
      col++;
      if (col >= desksPerRow) {
        col = 0;
        row++;
      }
    }
  }

  return features;
}
