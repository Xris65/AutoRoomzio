// Utilitaires centralisés pour les espaces de travail et plans 2D.

/// Détermine si un workspace issu de l'API MyRoomz est réservable en tant que bureau.
bool isBookableWorkspace(Map<String, dynamic> ws) {
  if (ws['isReservable'] == false) return false;
  if (ws['bookable'] == false) return false;
  if (ws['isBookable'] == false) return false;
  final type = ws['workspaceType'] ?? ws['type'];
  if (type == 'Room' || type == 1) return false;
  if (ws['isReservable'] == true ||
      ws['bookable'] == true ||
      ws['isBookable'] == true) {
    return true;
  }
  return type == null || type == 'Desk' || type == 0;
}

/// Extrait le nom de pièce/zone depuis un objet workspace.
String extractRoomName(Map<String, dynamic> ws, {bool trim = true}) {
  final rawRoom = ws['roomName']?.toString();
  if (rawRoom != null && rawRoom.isNotEmpty) {
    return trim ? rawRoom.trim() : rawRoom;
  }
  final name = ws['name']?.toString() ?? ws['id']?.toString() ?? '';
  final lastDash = name.lastIndexOf('-');
  if (lastDash > 0 && lastDash < name.length - 1) {
    final rawSuffix = name.substring(lastDash + 1);
    final suffix = trim ? rawSuffix.trim() : rawSuffix;
    if (suffix.length <= 4 && !suffix.contains(' ')) {
      final prefix = name.substring(0, lastDash);
      return trim ? prefix.trim() : prefix;
    }
  }
  return trim ? name.trim() : name;
}

/// Parse les features GeoJSON d'un plan d'étage et génère une grille synthétique
/// de secours à partir de [allWs] si le plan est vide.
List<Map<String, dynamic>> parseFloorFeaturesWithFallback(
  dynamic planData,
  List<Map<String, dynamic>> allWs,
) {
  List<Map<String, dynamic>> features = [];
  if (planData is List) {
    features = planData
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } else if (planData is Map) {
    final raw = planData['features'] ?? planData['data'] ?? [];
    if (raw is List) {
      features = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }

  if (features.isEmpty && allWs.isNotEmpty) {
    int col = 0;
    int row = 0;
    const int desksPerRow = 6;
    for (final ws in allWs) {
      final wsId = ws['id']?.toString() ?? '';
      final wsName = ws['name']?.toString() ?? wsId;
      final x = 50.0 + (col * 85.0);
      final y = 50.0 + (row * 65.0);
      features.add({
        'type': 'Feature',
        'properties': {
          'workspaceId': wsId,
          'id': wsId,
          'name': wsName,
          'workspaceType': ws['type']?.toString() ?? 'Desk',
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [x, y],
              [x + 72.0, y],
              [x + 72.0, y + 48.0],
              [x, y + 48.0],
              [x, y],
            ]
          ]
        }
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
