import 'package:flutter/material.dart';

/// Boîte englobante mutable utilisée lors de la construction du cache de pièces.
class RoomBounds {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;

  void addRect(double left, double top, double width, double height) {
    if (left < minX) minX = left;
    if (top < minY) minY = top;
    if (left + width > maxX) maxX = left + width;
    if (top + height > maxY) maxY = top + height;
  }

  bool get isValid => minX != double.infinity;
}

/// Statistiques d'occupation et coloration thermique d'une salle sur le plan 2D.
class RoomOccupancyStats {
  final int totalDesks;
  final int occupiedDesks;

  static const Color heatmapGreen = Color(0x1822C55E);
  static const Color heatmapOrange = Color(0x18F59E0B);
  static const Color heatmapRed = Color(0x18EF4444);
  static const Color heatmapSlate = Color(0x1A64748B);

  const RoomOccupancyStats({
    required this.totalDesks,
    required this.occupiedDesks,
  });

  /// Calcule le taux d'occupation : bureaux_occupés / total_bureaux
  static double calculateOccupancyRatio({
    required int occupiedDesks,
    required int totalDesks,
  }) {
    if (totalDesks <= 0) return 0.0;
    return (occupiedDesks / totalDesks).clamp(0.0, 1.0);
  }

  /// Calcule le ratio de places libres : places_libres / total_bureaux
  static double calculateFreeRatio({
    required int occupiedDesks,
    required int totalDesks,
  }) {
    if (totalDesks <= 0) return 1.0;
    final int free = (totalDesks - occupiedDesks).clamp(0, totalDesks);
    return free / totalDesks;
  }

  /// Retourne la couleur thermique pastel adaptée à l'occupation de la salle.
  static Color getRoomHeatmapColor({
    required int occupiedDesks,
    required int totalDesks,
    bool isDark = false,
  }) {
    if (totalDesks <= 0) return Colors.transparent;
    final double freeRatio = calculateFreeRatio(
      occupiedDesks: occupiedDesks,
      totalDesks: totalDesks,
    );

    if (freeRatio > 0.65) {
      return isDark ? const Color(0x2222C55E) : heatmapGreen;
    } else if (freeRatio >= 0.35) {
      return isDark ? const Color(0x22F59E0B) : heatmapOrange;
    } else {
      return isDark ? const Color(0x22EF4444) : heatmapRed;
    }
  }

  /// Nombre de bureaux disponibles
  int get freeDesks => (totalDesks - occupiedDesks).clamp(0, totalDesks);

  /// Taux d'occupation : bureaux_occupés / total_bureaux (0.0 à 1.0)
  double get occupancyRatio => calculateOccupancyRatio(
        occupiedDesks: occupiedDesks,
        totalDesks: totalDesks,
      );

  /// Ratio de places libres : places_libres / total_bureaux (0.0 à 1.0)
  double get freeRatio => calculateFreeRatio(
        occupiedDesks: occupiedDesks,
        totalDesks: totalDesks,
      );

  /// Pourcentage de places libres (0 à 100)
  double get freePercentage => freeRatio * 100.0;

  /// Pourcentage d'occupation (0 à 100)
  double get occupancyPercentage => occupancyRatio * 100.0;

  /// Couleur thermique pastel associée selon les seuils
  Color get heatmapColor => getRoomHeatmapColor(
        occupiedDesks: occupiedDesks,
        totalDesks: totalDesks,
      );
}
