import 'package:flutter/material.dart';
import '../models/team_map_models.dart';

/// Sélecteur d'étage dans l'AppBar de TeamMapScreen.
class TeamMapFloorSelector extends StatelessWidget {
  final List<Map<String, dynamic>> floors;
  final String? selectedFloorId;
  final ValueChanged<String> onFloorChanged;

  const TeamMapFloorSelector({
    super.key,
    required this.floors,
    required this.selectedFloorId,
    required this.onFloorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (floors.length > 1) {
      final uniqueFloors = <String, Map<String, dynamic>>{};
      for (final f in floors) {
        final id = f['id']?.toString() ?? '';
        if (id.isNotEmpty && !uniqueFloors.containsKey(id)) {
          uniqueFloors[id] = f;
        }
      }
      final currentFloorValue = uniqueFloors.containsKey(selectedFloorId)
          ? selectedFloorId
          : (uniqueFloors.isNotEmpty ? uniqueFloors.keys.first : null);

      return Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: currentFloorValue,
            icon: const Icon(Icons.arrow_drop_down),
            items: uniqueFloors.values.map<DropdownMenuItem<String>>((
              Map<String, dynamic> f,
            ) {
              final id = f['id']?.toString() ?? '';
              final name = f['name']?.toString() ?? 'Étage $id';
              return DropdownMenuItem<String>(
                value: id,
                child: Text(name),
              );
            }).toList(),
            onChanged: (String? newId) {
              if (newId != null) {
                onFloorChanged(newId);
              }
            },
          ),
        ),
      );
    }

    if (floors.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Center(
          child: Text(
            floors.first['name']?.toString() ?? '',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Barre horizontale de filtres par salle / zone avec compteur de favoris et d'occupants.
class TeamMapRoomFilterBar extends StatelessWidget {
  final List<RoomSummary> summaries;
  final int totalBookableCount;
  final String? focusedRoom;
  final ValueChanged<String?> onFocusedRoomChanged;

  const TeamMapRoomFilterBar({
    super.key,
    required this.summaries,
    required this.totalBookableCount,
    required this.focusedRoom,
    required this.onFocusedRoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            FilterChip(
              label: Text('Tous les bureaux ($totalBookableCount)'),
              selected: focusedRoom == null,
              onSelected: (bool _) => onFocusedRoomChanged(null),
            ),
            const SizedBox(width: 8),
            ...summaries.map<Widget>((RoomSummary s) {
              final isSelected = focusedRoom == s.roomName;
              if (s.hasFavorites) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: const Icon(
                      Icons.star,
                      size: 14,
                      color: Colors.amber,
                    ),
                    label: Text('${s.roomName} (${s.favoriteOccupants.length})'),
                    selected: isSelected,
                    selectedColor: Colors.amber.withValues(alpha: 0.25),
                    checkmarkColor: Colors.amber.shade900,
                    onSelected: (bool selected) {
                      onFocusedRoomChanged(selected ? s.roomName : null);
                    },
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('${s.roomName} (${s.totalOccupants})'),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    onFocusedRoomChanged(selected ? s.roomName : null);
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Légende visuelle des couleurs de postes sur la carte 2D.
class TeamMapLegendBar extends StatelessWidget {
  const TeamMapLegendBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _LegendItem(
              color: isDark ? const Color(0xFFD97706) : const Color(0xFFFBBF24),
              border:
                  isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
              label: 'Collègue favori',
              starPrefix: true,
            ),
            const SizedBox(width: 14),
            _LegendItem(
              color: isDark ? const Color(0xFF15803D) : const Color(0xFF22C55E),
              border:
                  isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534),
              label: 'Mon bureau',
            ),
            const SizedBox(width: 14),
            _LegendItem(
              color: isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1),
              border:
                  isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8),
              label: 'Occupé',
            ),
            const SizedBox(width: 14),
            _LegendItem(
              color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE),
              border:
                  isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD),
              label: 'Libre',
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final Color border;
  final String label;
  final bool starPrefix;

  const _LegendItem({
    required this.color,
    required this.border,
    required this.label,
    this.starPrefix = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: starPrefix
              ? const Icon(Icons.star, size: 9, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
