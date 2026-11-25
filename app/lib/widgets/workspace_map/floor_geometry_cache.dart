import 'package:flutter/material.dart';
import '../../utils/workspace_helpers.dart';
import 'room_occupancy_stats.dart';

/// Feature GeoJSON pré-parsée avec géométrie écran et clés de recherche pré-calculées.
class ParsedFloorFeature {
  final String? wsId;
  final String? propName;
  final String? pNameLower;
  final bool isDesk;
  final Map<String, dynamic>? workspace;
  final bool isBookable;
  final Map<String, dynamic>? effectiveWs;
  final double left;
  final double top;
  final double width;
  final double height;
  final double renderLeft;
  final double renderTop;
  final double renderWidth;
  final double renderHeight;
  final Rect rawRect;
  final Rect renderRect;
  final bool isPointFeature;
  final String label;
  final String? roomName;
  final String? roomNameLower;
  final bool countsInRoomStats;
  final List<String> occupantLookupKeys;
  final List<String> idLookupKeysLower;

  const ParsedFloorFeature({
    required this.wsId,
    required this.propName,
    required this.pNameLower,
    required this.isDesk,
    required this.workspace,
    required this.isBookable,
    required this.effectiveWs,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.renderLeft,
    required this.renderTop,
    required this.renderWidth,
    required this.renderHeight,
    required this.rawRect,
    required this.renderRect,
    required this.isPointFeature,
    required this.label,
    required this.roomName,
    required this.roomNameLower,
    required this.countsInRoomStats,
    required this.occupantLookupKeys,
    required this.idLookupKeysLower,
  });
}

/// Géométrie agrégée d'une salle sur le plan d'étage.
class ParsedRoomGeometry {
  final String name;
  final String nameLower;
  final RoomBounds bounds;
  final Rect outerRect;
  final int totalDesks;

  const ParsedRoomGeometry({
    required this.name,
    required this.nameLower,
    required this.bounds,
    required this.outerRect,
    required this.totalDesks,
  });
}

/// Résultat immuable du parsing géométrique et de la mise à l'échelle d'un étage.
class FloorGeometrySnapshot {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final double coordScale;
  final double padding;
  final double mapWidth;
  final double mapHeight;
  final Size mapSize;
  final bool hasValidBounds;
  final Map<String, Map<String, dynamic>> wsMap;
  final Map<String, Map<String, dynamic>> allWsMap;
  final List<ParsedFloorFeature> parsedFeatures;
  final List<ParsedRoomGeometry> rooms;
  final Map<String, RoomBounds> roomBounds;
  final Map<String, Rect> deskBounds;
  final Map<String, Rect> deskRawBounds;
  final Map<String, String> deskRooms;
  final List<Rect> miniMapRooms;
  final List<Rect> miniMapDesks;

  const FloorGeometrySnapshot({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.coordScale,
    required this.padding,
    required this.mapWidth,
    required this.mapHeight,
    required this.mapSize,
    required this.hasValidBounds,
    required this.wsMap,
    required this.allWsMap,
    required this.parsedFeatures,
    required this.rooms,
    required this.roomBounds,
    required this.deskBounds,
    required this.deskRawBounds,
    required this.deskRooms,
    required this.miniMapRooms,
    required this.miniMapDesks,
  });
}

/// Cache mémoïsé de la géométrie d'étage (polygones GeoJSON, coordonnées,
/// dimensions des postes, bounding box, listes `rooms`/`desks` pour la mini-map).
class FloorGeometryCache {
  List<Map<String, dynamic>>? _featuresSnapshot;
  List<Map<String, dynamic>>? _workspacesSnapshot;
  List<Map<String, dynamic>>? _allWorkspacesSnapshot;
  FloorGeometrySnapshot? _cachedSnapshot;

  /// Retourne le snapshot géométrique mémoïsé si [features], [workspaces] et
  /// [allWorkspaces] contiennent les mêmes références d'éléments.
  FloorGeometrySnapshot resolve({
    required List<Map<String, dynamic>> features,
    required List<Map<String, dynamic>> workspaces,
    required List<Map<String, dynamic>> allWorkspaces,
  }) {
    final FloorGeometrySnapshot? existing = _cachedSnapshot;
    if (existing != null &&
        _sameElementRefs(_featuresSnapshot, features) &&
        _sameElementRefs(_workspacesSnapshot, workspaces) &&
        _sameElementRefs(_allWorkspacesSnapshot, allWorkspaces)) {
      return existing;
    }

    final FloorGeometrySnapshot built = _buildSnapshot(
      features: features,
      workspaces: workspaces,
      allWorkspaces: allWorkspaces,
    );
    _featuresSnapshot = List<Map<String, dynamic>>.of(features);
    _workspacesSnapshot = List<Map<String, dynamic>>.of(workspaces);
    _allWorkspacesSnapshot = List<Map<String, dynamic>>.of(allWorkspaces);
    _cachedSnapshot = built;
    return built;
  }

  static bool _sameElementRefs(
    List<Map<String, dynamic>>? a,
    List<Map<String, dynamic>> b,
  ) {
    if (a == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Extrait récursivement toutes les paires de coordonnées `[x, y]` d'une
  /// géométrie GeoJSON quelle que soit sa profondeur d'imbrication.
  static void extractBounds(
    List<Object?> coords,
    void Function(double x, double y) cb,
  ) {
    if (coords.isEmpty) return;
    final Object? first = coords[0];
    if (first is num) {
      if (coords.length >= 2 && coords[1] is num) {
        cb(first.toDouble(), (coords[1] as num).toDouble());
      }
    } else {
      for (final Object? item in coords) {
        if (item is List<Object?>) {
          extractBounds(item, cb);
        }
      }
    }
  }

  static Map<Object?, Object?> _asMap(Object? raw) {
    if (raw is Map<Object?, Object?>) return raw;
    return const <Object?, Object?>{};
  }

  static List<Object?>? _extractCoords(Map<String, dynamic> feature) {
    final Object? rawGeom = feature['geometry'];
    if (rawGeom is Map<Object?, Object?>) {
      final Object? rawCoords = rawGeom['coordinates'];
      if (rawCoords is List<Object?>) {
        return rawCoords;
      }
    }
    return null;
  }

  static FloorGeometrySnapshot _buildSnapshot({
    required List<Map<String, dynamic>> features,
    required List<Map<String, dynamic>> workspaces,
    required List<Map<String, dynamic>> allWorkspaces,
  }) {
    // ── 1. Passe bounding box globale et échelle des bureaux ──────────────
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    double totalDeskWidth = 0.0;
    int deskCount = 0;

    final List<({double minX, double minY, double maxX, double maxY})?>
        perFeatureRawBounds =
        List<({double minX, double minY, double maxX, double maxY})?>.filled(
      features.length,
      null,
    );

    for (int i = 0; i < features.length; i++) {
      final Map<String, dynamic> feature = features[i];
      final List<Object?>? coords = _extractCoords(feature);
      if (coords == null || coords.isEmpty) continue;

      double fMinX = double.infinity;
      double fMinY = double.infinity;
      double fMaxX = double.negativeInfinity;
      double fMaxY = double.negativeInfinity;

      extractBounds(coords, (double x, double y) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        if (x < fMinX) fMinX = x;
        if (y < fMinY) fMinY = y;
        if (x > fMaxX) fMaxX = x;
        if (y > fMaxY) fMaxY = y;
      });

      if (fMinX != double.infinity) {
        perFeatureRawBounds[i] = (
          minX: fMinX,
          minY: fMinY,
          maxX: fMaxX,
          maxY: fMaxY,
        );
        final Map<Object?, Object?> props = _asMap(feature['properties']);
        final bool isDesk = props['workspaceType'] == 'Desk';
        if (isDesk && (fMaxX - fMinX) > 0) {
          totalDeskWidth += (fMaxX - fMinX);
          deskCount++;
        }
      }
    }

    final Map<String, Map<String, dynamic>> wsMap =
        <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> w in workspaces)
        if (w['id'] != null) w['id'].toString().toLowerCase(): w,
    };
    final Map<String, Map<String, dynamic>> allWsMap =
        <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> w in allWorkspaces)
        if (w['id'] != null) w['id'].toString().toLowerCase(): w,
    };

    if (minX == double.infinity) {
      return FloorGeometrySnapshot(
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
        coordScale: 2.0,
        padding: 40.0,
        mapWidth: 0.0,
        mapHeight: 0.0,
        mapSize: Size.zero,
        hasValidBounds: false,
        wsMap: wsMap,
        allWsMap: allWsMap,
        parsedFeatures: const <ParsedFloorFeature>[],
        rooms: const <ParsedRoomGeometry>[],
        roomBounds: const <String, RoomBounds>{},
        deskBounds: const <String, Rect>{},
        deskRawBounds: const <String, Rect>{},
        deskRooms: const <String, String>{},
        miniMapRooms: const <Rect>[],
        miniMapDesks: const <Rect>[],
      );
    }

    final double avgDeskWidth =
        deskCount > 0 ? (totalDeskWidth / deskCount) : 32.0;
    final double coordScale =
        avgDeskWidth > 0 ? (72.0 / avgDeskWidth).clamp(1.0, 3.5) : 2.0;
    const double padding = 40.0;

    // ── 2. Parsing géométrique & indexation des bureaux / pièces ──────────
    final Map<String, RoomBounds> roomBounds = <String, RoomBounds>{};
    final Map<String, int> roomTotalDesks = <String, int>{};
    final Map<String, Rect> deskBounds = <String, Rect>{};
    final Map<String, Rect> deskRawBounds = <String, Rect>{};
    final Map<String, String> deskRooms = <String, String>{};
    final List<ParsedFloorFeature> parsedFeatures = <ParsedFloorFeature>[];
    final Set<Rect> uniqueDesksForMiniMap = <Rect>{};

    for (int i = 0; i < features.length; i++) {
      final ({double minX, double minY, double maxX, double maxY})? rawB =
          perFeatureRawBounds[i];
      if (rawB == null) continue;

      final Map<String, dynamic> feature = features[i];
      final Map<Object?, Object?> props = _asMap(feature['properties']);
      final String? wsId = (props['workspaceId']?.toString() ??
              props['roomId']?.toString() ??
              props['id']?.toString())
          ?.toLowerCase();
      final bool isDesk = props['workspaceType'] == 'Desk';
      final Map<String, dynamic>? workspace = wsId != null ? wsMap[wsId] : null;
      final bool isBookable = workspace != null;
      final Map<String, dynamic>? effectiveWs =
          workspace ?? (wsId != null ? allWsMap[wsId] : null);

      final double left = (rawB.minX - minX) * coordScale + padding;
      final double top = (rawB.minY - minY) * coordScale + padding;
      final double width = (rawB.maxX - rawB.minX) * coordScale;
      final double height = (rawB.maxY - rawB.minY) * coordScale;
      final Rect rawRect = Rect.fromLTWH(left, top, width, height);

      double renderWidth = width;
      double renderHeight = height;
      double renderLeft = left;
      double renderTop = top;

      if (isDesk || isBookable) {
        const double deskGap = 1.5;
        if (width > deskGap * 2 && height > deskGap * 2) {
          renderWidth = width - deskGap * 2;
          renderHeight = height - deskGap * 2;
          renderLeft = left + deskGap;
          renderTop = top + deskGap;
        }
      }

      final Rect deskRect =
          Rect.fromLTWH(renderLeft, renderTop, renderWidth, renderHeight);
      final String? pNameLower = props['name']?.toString().toLowerCase();

      void registerRect(Map<String, Rect> target, Rect rect) {
        if (wsId != null && wsId.isNotEmpty) target[wsId] = rect;
        if (pNameLower != null && pNameLower.isNotEmpty) {
          target[pNameLower] = rect;
        }
        if (workspace != null) {
          final String? wId = workspace['id']?.toString().toLowerCase();
          if (wId != null && wId.isNotEmpty) target[wId] = rect;
          final String? wName = workspace['name']?.toString().toLowerCase();
          if (wName != null && wName.isNotEmpty) target[wName] = rect;
        }
        if (effectiveWs != null) {
          final String? ewId = effectiveWs['id']?.toString().toLowerCase();
          if (ewId != null && ewId.isNotEmpty) target[ewId] = rect;
          final String? ewName = effectiveWs['name']?.toString().toLowerCase();
          if (ewName != null && ewName.isNotEmpty) target[ewName] = rect;
        }
      }

      registerRect(deskBounds, deskRect);
      registerRect(deskRawBounds, rawRect);
      if (width > 0 || height > 0) {
        uniqueDesksForMiniMap.add(deskRect);
      }

      final String? propName = props['name']?.toString() ??
          props['title']?.toString() ??
          props['label']?.toString() ??
          props['workspaceName']?.toString() ??
          props['text']?.toString() ??
          props['description']?.toString();

      String label = '';
      String? roomName;
      bool countsInRoomStats = false;

      if (effectiveWs != null || isDesk) {
        final String name = effectiveWs?['name']?.toString() ?? propName ?? '';
        final List<String> parts = name.split('-');
        label = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : name;

        final Map<String, dynamic> roomSource;
        if (effectiveWs != null) {
          roomSource = (effectiveWs['roomName'] != null ||
                  effectiveWs['name'] != null)
              ? effectiveWs
              : <String, dynamic>{
                  ...effectiveWs,
                  'name': ?propName,
                };
        } else {
          roomSource = <String, dynamic>{
            'name': name,
            'roomName': ?props['roomName'],
          };
        }
        roomName = extractRoomName(roomSource, trim: false);

        if (roomName.isNotEmpty) {
          roomBounds
              .putIfAbsent(roomName, RoomBounds.new)
              .addRect(renderLeft, renderTop, renderWidth, renderHeight);
          if (width > 0 || height > 0) {
            roomTotalDesks[roomName] = (roomTotalDesks[roomName] ?? 0) + 1;
            countsInRoomStats = true;
          }
        }
      } else if (!isDesk) {
        final Map<String, dynamic>? roomWs =
            wsId != null ? allWsMap[wsId] : null;
        label = roomWs?['name']?.toString() ??
            propName ??
            (wsId != null ? 'Err: $wsId' : '');
      }

      if (roomName != null && roomName.isNotEmpty) {
        if (wsId != null && wsId.isNotEmpty) deskRooms[wsId] = roomName;
        if (pNameLower != null && pNameLower.isNotEmpty) {
          deskRooms[pNameLower] = roomName;
        }
        if (workspace != null) {
          final String? wId = workspace['id']?.toString().toLowerCase();
          if (wId != null && wId.isNotEmpty) deskRooms[wId] = roomName;
          final String? wName = workspace['name']?.toString().toLowerCase();
          if (wName != null && wName.isNotEmpty) deskRooms[wName] = roomName;
        }
        if (effectiveWs != null) {
          final String? ewId = effectiveWs['id']?.toString().toLowerCase();
          if (ewId != null && ewId.isNotEmpty) deskRooms[ewId] = roomName;
          final String? ewName = effectiveWs['name']?.toString().toLowerCase();
          if (ewName != null && ewName.isNotEmpty) deskRooms[ewName] = roomName;
        }
      }

      // Clés pré-calculées pour les recherches occupants/sélection/pending en O(1)
      final List<String> occupantKeys = <String>[];
      final Set<String> seenOccKeys = <String>{};
      void addOccKey(String? raw) {
        if (raw == null || raw.isEmpty) return;
        if (seenOccKeys.add(raw)) occupantKeys.add(raw);
        final String lower = raw.toLowerCase();
        if (seenOccKeys.add(lower)) occupantKeys.add(lower);
      }

      addOccKey(wsId);
      if (workspace != null) {
        addOccKey(workspace['id']?.toString());
        addOccKey(workspace['name']?.toString());
      }
      if (effectiveWs != null) {
        addOccKey(effectiveWs['id']?.toString());
        addOccKey(effectiveWs['name']?.toString());
      }

      final List<String> idKeysLower = <String>[];
      final Set<String> seenIdKeys = <String>{};
      void addIdKeyLower(String? raw) {
        if (raw == null) return;
        final String lower = raw.trim().toLowerCase();
        if (lower.isEmpty) return;
        if (seenIdKeys.add(lower)) idKeysLower.add(lower);
      }

      addIdKeyLower(wsId);
      if (workspace != null) addIdKeyLower(workspace['id']?.toString());
      if (effectiveWs != null) addIdKeyLower(effectiveWs['id']?.toString());

      parsedFeatures.add(
        ParsedFloorFeature(
          wsId: wsId,
          propName: propName,
          pNameLower: pNameLower,
          isDesk: isDesk,
          workspace: workspace,
          isBookable: isBookable,
          effectiveWs: effectiveWs,
          left: left,
          top: top,
          width: width,
          height: height,
          renderLeft: renderLeft,
          renderTop: renderTop,
          renderWidth: renderWidth,
          renderHeight: renderHeight,
          rawRect: rawRect,
          renderRect: deskRect,
          isPointFeature: width == 0 && height == 0,
          label: label,
          roomName: roomName,
          roomNameLower: roomName?.toLowerCase(),
          countsInRoomStats: countsInRoomStats,
          occupantLookupKeys: List<String>.unmodifiable(occupantKeys),
          idLookupKeysLower: List<String>.unmodifiable(idKeysLower),
        ),
      );
    }

    // ── 3. Construction des salles & bounding box finale ──────────────────
    final List<ParsedRoomGeometry> rooms = <ParsedRoomGeometry>[];
    final List<Rect> miniMapRooms = <Rect>[];

    double calculatedMaxX = (maxX - minX) * coordScale + padding * 2;
    double calculatedMaxY = (maxY - minY) * coordScale + padding * 2;

    roomBounds.forEach((String name, RoomBounds bounds) {
      if (!bounds.isValid) return;
      final Rect outerRect = Rect.fromLTWH(
        bounds.minX - 16.0,
        bounds.minY - 28.0,
        (bounds.maxX - bounds.minX) + 32.0,
        (bounds.maxY - bounds.minY) + 44.0,
      );
      rooms.add(
        ParsedRoomGeometry(
          name: name,
          nameLower: name.toLowerCase(),
          bounds: bounds,
          outerRect: outerRect,
          totalDesks: roomTotalDesks[name] ?? 0,
        ),
      );
      miniMapRooms.add(outerRect);

      final double rightEdge = bounds.maxX + 16.0 + padding;
      final double bottomEdge = bounds.maxY + 16.0 + padding;
      if (rightEdge > calculatedMaxX) calculatedMaxX = rightEdge;
      if (bottomEdge > calculatedMaxY) calculatedMaxY = bottomEdge;
    });

    final double mapWidth = calculatedMaxX + 24.0;
    final double mapHeight = calculatedMaxY + 24.0;

    return FloorGeometrySnapshot(
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
      coordScale: coordScale,
      padding: padding,
      mapWidth: mapWidth,
      mapHeight: mapHeight,
      mapSize: Size(mapWidth, mapHeight),
      hasValidBounds: true,
      wsMap: wsMap,
      allWsMap: allWsMap,
      parsedFeatures: List<ParsedFloorFeature>.unmodifiable(parsedFeatures),
      rooms: List<ParsedRoomGeometry>.unmodifiable(rooms),
      roomBounds: Map<String, RoomBounds>.unmodifiable(roomBounds),
      deskBounds: Map<String, Rect>.unmodifiable(deskBounds),
      deskRawBounds: Map<String, Rect>.unmodifiable(deskRawBounds),
      deskRooms: Map<String, String>.unmodifiable(deskRooms),
      miniMapRooms: List<Rect>.unmodifiable(miniMapRooms),
      miniMapDesks: List<Rect>.unmodifiable(uniqueDesksForMiniMap),
    );
  }
}
