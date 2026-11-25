import 'package:flutter/material.dart';
import '../../utils/workspace_helpers.dart';
import 'floor_geometry_cache.dart';
import 'room_occupancy_stats.dart';

/// Utilitaires purs de calcul de matrices caméra pour [WorkspaceMapViewer].
class MapCameraHelper {
  const MapCameraHelper._();

  static Matrix4 buildScaleTranslationMatrix({
    required double scale,
    required double dx,
    required double dy,
  }) {
    return Matrix4.identity()
      ..setTranslationRaw(dx, dy, 0.0)
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale);
  }

  /// Résout le rectangle cible initial (salle englobante prioritaire, sinon poste).
  static Rect? resolveInitialTargetRect({
    required FloorGeometrySnapshot snapshot,
    required String? selectedWorkspaceId,
    required String? defaultWorkspaceId,
    required String? myDeskId,
  }) {
    String? targetDeskId =
        (selectedWorkspaceId ?? defaultWorkspaceId)?.toLowerCase();
    if (targetDeskId == null || targetDeskId.isEmpty) {
      targetDeskId = myDeskId;
    }
    if (targetDeskId == null || targetDeskId.isEmpty) {
      return null;
    }

    final Map<String, dynamic>? targetWs =
        snapshot.wsMap[targetDeskId] ?? snapshot.allWsMap[targetDeskId];
    String? targetRoomName = snapshot.deskRooms[targetDeskId];

    if (targetRoomName == null || targetRoomName.isEmpty) {
      if (targetWs != null) {
        targetRoomName = extractRoomName(targetWs, trim: false);
      } else {
        for (final ParsedFloorFeature feature in snapshot.parsedFeatures) {
          if (feature.wsId == targetDeskId && feature.propName != null) {
            targetRoomName = extractRoomName(
              <String, dynamic>{'name': feature.propName},
              trim: false,
            );
            break;
          }
        }
      }
    }

    if (targetRoomName != null && targetRoomName.isNotEmpty) {
      final RoomBounds? bounds = snapshot.roomBounds[targetRoomName];
      if (bounds != null && bounds.isValid) {
        return Rect.fromLTRB(
          bounds.minX - 16.0,
          bounds.minY - 28.0,
          bounds.maxX + 16.0,
          bounds.maxY + 16.0,
        );
      }
    }

    return snapshot.deskRawBounds[targetDeskId];
  }

  /// Calcule la matrice initiale (cadrage sur [targetRect] ou Zoom-to-Fit global).
  static Matrix4? computeInitialTransform({
    required double viewW,
    required double viewH,
    required double mapW,
    required double mapH,
    required Rect? targetRect,
  }) {
    if (mapW <= 0 || mapH <= 0 || viewW <= 0 || viewH <= 0) return null;

    final double scale;
    final double targetCx;
    final double targetCy;

    if (targetRect != null && targetRect.width > 0 && targetRect.height > 0) {
      final double fitScale = (viewW * 0.75) / targetRect.width;
      scale = fitScale.clamp(0.85, 1.25);
      targetCx = targetRect.left + targetRect.width / 2;
      targetCy = targetRect.top + targetRect.height / 2;
    } else {
      final double scaleX = (viewW * 0.90) / mapW;
      final double scaleY = (viewH * 0.85) / mapH;
      final double fitScale = scaleX < scaleY ? scaleX : scaleY;
      scale = fitScale.clamp(0.60, 1.25);
      targetCx = mapW / 2;
      targetCy = mapH / 2;
    }

    final double dx = (viewW / 2) - (targetCx * scale);
    final double dy = (viewH / 2) - (targetCy * scale);
    return buildScaleTranslationMatrix(scale: scale, dx: dx, dy: dy);
  }

  /// Calcule la matrice permettant de cadrer un rectangle cible.
  static Matrix4? computeFrameTargetRect({
    required double viewW,
    required double viewH,
    required Rect targetRect,
  }) {
    if (targetRect.width <= 0 ||
        targetRect.height <= 0 ||
        viewW <= 0 ||
        viewH <= 0) {
      return null;
    }
    final double scaleX = viewW / targetRect.width;
    final double scaleY = viewH / targetRect.height;
    final double scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.5, 2.5) * 0.90;

    final double targetCx = targetRect.left + targetRect.width / 2;
    final double targetCy = targetRect.top + targetRect.height / 2;
    final double dx = (viewW / 2) - (targetCx * scale);
    final double dy = (viewH / 2) - (targetCy * scale);
    return buildScaleTranslationMatrix(scale: scale, dx: dx, dy: dy);
  }

  /// Calcule la nouvelle matrice pour centrer un poste sans sur-zoomer s'il est déjà visible.
  static Matrix4? computeFocusOnWorkspace({
    required String workspaceId,
    required Size viewport,
    required Matrix4 currentMatrix,
    required Map<String, Rect> savedDeskBounds,
    required Map<String, String> savedDeskRooms,
    required Map<String, RoomBounds> savedRoomBounds,
  }) {
    final double viewW = viewport.width;
    final double viewH = viewport.height;
    final String key = workspaceId.toLowerCase();

    Rect? rect = savedDeskBounds[key];
    if (rect == null) {
      for (final MapEntry<String, Rect> entry in savedDeskBounds.entries) {
        if (entry.key == key ||
            entry.key.contains(key) ||
            key.contains(entry.key)) {
          rect = entry.value;
          break;
        }
      }
    }

    if (rect == null || rect.width <= 0 || rect.height <= 0) return null;

    if (!currentMatrix.isIdentity()) {
      final double currentScale = currentMatrix.entry(0, 0);
      final double currentDx = currentMatrix.entry(0, 3);
      final double currentDy = currentMatrix.entry(1, 3);

      final double deskScreenLeft = rect.left * currentScale + currentDx;
      final double deskScreenTop = rect.top * currentScale + currentDy;
      final double deskScreenRight = rect.right * currentScale + currentDx;
      final double deskScreenBottom = rect.bottom * currentScale + currentDy;

      const double margin = 24.0;
      final bool isDeskVisible = deskScreenLeft >= margin &&
          deskScreenRight <= (viewW - margin) &&
          deskScreenTop >= margin &&
          deskScreenBottom <= (viewH - margin);

      if (isDeskVisible && currentScale >= 0.85) {
        return null;
      }
    }

    RoomBounds? roomBounds;
    String? roomName = savedDeskRooms[key];
    if (roomName == null) {
      for (final MapEntry<String, String> entry in savedDeskRooms.entries) {
        if (entry.key == key ||
            entry.key.contains(key) ||
            key.contains(entry.key)) {
          roomName = entry.value;
          break;
        }
      }
    }

    if (roomName != null && roomName.isNotEmpty) {
      roomBounds = savedRoomBounds[roomName];
      if (roomBounds == null) {
        final String targetLower = roomName.toLowerCase();
        for (final MapEntry<String, RoomBounds> entry
            in savedRoomBounds.entries) {
          if (entry.key.toLowerCase() == targetLower) {
            roomBounds = entry.value;
            break;
          }
        }
      }
    }

    if (roomBounds == null || !roomBounds.isValid) {
      for (final RoomBounds bounds in savedRoomBounds.values) {
        if (bounds.isValid &&
            rect.left >= bounds.minX - 20 &&
            rect.right <= bounds.maxX + 20 &&
            rect.top >= bounds.minY - 20 &&
            rect.bottom <= bounds.maxY + 20) {
          roomBounds = bounds;
          break;
        }
      }
    }

    final double targetCx;
    final double targetCy;
    final double scale;

    if (roomBounds != null && roomBounds.isValid) {
      final Rect roomRect = Rect.fromLTRB(
        roomBounds.minX - 28,
        roomBounds.minY - 36,
        roomBounds.maxX + 28,
        roomBounds.maxY + 36,
      );
      targetCx = roomRect.left + roomRect.width / 2;
      targetCy = roomRect.top + roomRect.height / 2;

      final double fitScaleX = (viewW * 0.80) / roomRect.width;
      final double fitScaleY = (viewH * 0.80) / roomRect.height;
      final double fitScale = fitScaleX < fitScaleY ? fitScaleX : fitScaleY;
      scale = fitScale.clamp(0.85, 1.25);
    } else {
      targetCx = rect.left + rect.width / 2;
      targetCy = rect.top + rect.height / 2;
      scale = 1.2;
    }

    final double dx = (viewW / 2) - (targetCx * scale);
    final double dy = (viewH / 2) - (targetCy * scale);
    return buildScaleTranslationMatrix(scale: scale, dx: dx, dy: dy);
  }

  /// Calcule la matrice pour cadrer une salle focalisée par son nom.
  static Matrix4? computeFocusedRoomMatrix({
    required String focusedRoom,
    required Size viewport,
    required Map<String, RoomBounds> savedRoomBounds,
  }) {
    if (focusedRoom.isEmpty) return null;
    RoomBounds? bounds = savedRoomBounds[focusedRoom];
    if (bounds == null) {
      final String focusedLower = focusedRoom.toLowerCase();
      for (final MapEntry<String, RoomBounds> entry
          in savedRoomBounds.entries) {
        if (entry.key.toLowerCase() == focusedLower) {
          bounds = entry.value;
          break;
        }
      }
    }
    if (bounds == null || !bounds.isValid) return null;

    final Rect targetRect = Rect.fromLTRB(
      bounds.minX - 28,
      bounds.minY - 36,
      bounds.maxX + 28,
      bounds.maxY + 36,
    );
    return computeFrameTargetRect(
      viewW: viewport.width,
      viewH: viewport.height,
      targetRect: targetRect,
    );
  }
}
