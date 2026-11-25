import 'package:flutter/material.dart';
import '../../models/desk_occupant.dart';
import 'room_occupancy_stats.dart';

const double _dimmedAlphaFactor = 0.25;

Color _applyDimAlpha(Color color, bool isDimmed) {
  if (!isDimmed) return color;
  return color.withValues(alpha: color.a * _dimmedAlphaFactor);
}

/// Tuile représentant un poste de travail ou une zone sur le plan 2D.
///
/// Lorsque [isDimmed] est vrai, atténue directement les canaux alpha des couleurs
/// de fond, bordure, icône et texte sans recourir à un widget `Opacity` (0 `saveLayer`).
class DeskMarkerWidget extends StatelessWidget {
  final String label;
  final DeskOccupant? occupant;
  final bool isSelected;
  final bool isMe;
  final bool isPending;
  final bool isFavorite;
  final bool isBookable;
  final bool isDimmed;
  final VoidCallback? onTap;

  const DeskMarkerWidget({
    super.key,
    required this.label,
    required this.occupant,
    required this.isSelected,
    required this.isMe,
    required this.isPending,
    required this.isFavorite,
    required this.isBookable,
    required this.isDimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor;
    Color textColor;
    Color borderColor;
    double borderWidth;
    List<BoxShadow>? boxShadow;

    if (isSelected) {
      bgColor = isDark ? const Color(0xFF0284C7) : const Color(0xFF38BDF8);
      textColor = Colors.white;
      borderColor = isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1);
      borderWidth = 2.5;
      if (!isDimmed) {
        boxShadow = <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF38BDF8)
                .withValues(alpha: isDark ? 0.45 : 0.65),
            blurRadius: 8.0,
            spreadRadius: 2.0,
          ),
        ];
      }
    } else if (isMe) {
      bgColor = isDark ? const Color(0xFF15803D) : const Color(0xFF22C55E);
      textColor = Colors.white;
      borderColor = isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534);
      borderWidth = 2.5;
      if (!isDimmed) {
        boxShadow = <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF22C55E)
                .withValues(alpha: isDark ? 0.4 : 0.5),
            blurRadius: 6.0,
            spreadRadius: 1.5,
          ),
        ];
      }
    } else if (isPending) {
      bgColor = isDark ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB);
      textColor = Colors.white;
      borderColor = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF);
      borderWidth = 2.5;
      if (!isDimmed) {
        boxShadow = <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF3B82F6)
                .withValues(alpha: isDark ? 0.4 : 0.5),
            blurRadius: 6.0,
            spreadRadius: 1.5,
          ),
        ];
      }
    } else if (isFavorite) {
      bgColor = isDark ? const Color(0xFFD97706) : const Color(0xFFFBBF24);
      textColor = isDark ? Colors.white : const Color(0xFF78350F);
      borderColor = isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
      borderWidth = 2.5;
      if (!isDimmed) {
        boxShadow = <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFF59E0B)
                .withValues(alpha: isDark ? 0.45 : 0.55),
            blurRadius: 6.0,
            spreadRadius: 1.5,
          ),
        ];
      }
    } else if (occupant != null) {
      bgColor = isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1);
      textColor = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1E293B);
      borderColor = isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8);
      borderWidth = 1.5;
    } else if (isBookable) {
      bgColor = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE);
      textColor = isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E40AF);
      borderColor = isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD);
      borderWidth = 1.5;
    } else {
      bgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
      textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
      borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
      borderWidth = 1.0;
    }

    final Color effectiveBgColor = _applyDimAlpha(bgColor, isDimmed);
    final Color effectiveTextColor = _applyDimAlpha(textColor, isDimmed);
    final Color effectiveSubTextColor = textColor.withValues(
      alpha: textColor.a * 0.85 * (isDimmed ? _dimmedAlphaFactor : 1.0),
    );
    final Color effectiveBorderColor = _applyDimAlpha(borderColor, isDimmed);

    final Widget deskContent;
    final DeskOccupant? occ = occupant;
    if (occ != null) {
      final String displayName = occ.formattedDisplayName.isNotEmpty
          ? occ.formattedDisplayName
          : occ.occupantName.toUpperCase();
      deskContent = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                displayName,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: effectiveTextColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9,
                      color: effectiveSubTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else if (isPending) {
      deskContent = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.schedule, size: 9, color: effectiveTextColor),
                  const SizedBox(width: 2),
                  Text(
                    'EN ATTENTE',
                    style: TextStyle(
                      fontSize: 7.5,
                      color: effectiveTextColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: effectiveTextColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      deskContent = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              color: effectiveTextColor,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: effectiveBgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
          boxShadow: boxShadow,
        ),
        alignment: Alignment.center,
        child: deskContent,
      ),
    );
  }
}

/// Cadre d'une pièce sur le plan 2D avec coloration thermique optionnelle
/// et atténuation directe du canal alpha sans `saveLayer`.
class RoomBoxWidget extends StatelessWidget {
  final String name;
  final int totalCount;
  final int occupiedCount;
  final bool showHeatmap;
  final bool isDimmed;

  const RoomBoxWidget({
    super.key,
    required this.name,
    required this.totalCount,
    required this.occupiedCount,
    required this.showHeatmap,
    required this.isDimmed,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    final Color roomBgColor;
    if (showHeatmap && totalCount > 0) {
      final Color heatmapTint = RoomOccupancyStats.getRoomHeatmapColor(
        occupiedDesks: occupiedCount,
        totalDesks: totalCount,
        isDark: isDark,
      );
      final Color baseFloor =
          colorScheme.surface.withValues(alpha: isDark ? 0.45 : 0.65);
      roomBgColor = Color.alphaBlend(heatmapTint, baseFloor);
    } else {
      roomBgColor = colorScheme.surface.withValues(alpha: 0.55);
    }

    final Color effectiveBg = _applyDimAlpha(roomBgColor, isDimmed);
    final Color effectiveBorder =
        _applyDimAlpha(colorScheme.outlineVariant, isDimmed);
    final Color effectiveBadgeBg = _applyDimAlpha(
      colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      isDimmed,
    );
    final Color effectiveTitleColor =
        _applyDimAlpha(colorScheme.onSurface, isDimmed);
    final Color effectiveRatioColor =
        _applyDimAlpha(colorScheme.onSurfaceVariant, isDimmed);

    return Container(
      key: ValueKey<String>('room_box_$name'),
      decoration: BoxDecoration(
        border: Border.all(color: effectiveBorder, width: 1.5),
        borderRadius: BorderRadius.circular(8),
        color: effectiveBg,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 2, left: 4, right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: effectiveBadgeBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: effectiveTitleColor,
                  ),
                ),
              ),
              if (showHeatmap && totalCount > 0) ...<Widget>[
                const SizedBox(width: 4),
                Text(
                  '${totalCount - occupiedCount}/$totalCount',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: effectiveRatioColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
