import 'package:flutter/material.dart';
import '../models/desk_occupant.dart';

/// Modal bottom sheet displaying detailed colleague/occupant identity,
/// seat location, delegation context, and favorite action.
/// (Milestone M3 - Requirement R3).
class OccupantDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> workspace;
  final DeskOccupant occupant;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  const OccupantDetailsSheet({
    super.key,
    required this.workspace,
    required this.occupant,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  /// Displays the [OccupantDetailsSheet] as a modal bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> workspace,
    required DeskOccupant occupant,
    bool isFavorite = false,
    VoidCallback? onToggleFavorite,
  }) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => OccupantDetailsSheet(
        workspace: workspace,
        occupant: occupant,
        isFavorite: isFavorite,
        onToggleFavorite: onToggleFavorite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final deskName = workspace['name']?.toString() ?? occupant.workspaceId;
    final roomName = workspace['roomName']?.toString() ?? _extractRoomName(deskName);

    Color avatarBg;
    Color avatarText;
    if (occupant.isMe) {
      avatarBg = isDark ? Colors.green.shade800 : Colors.green.shade200;
      avatarText = isDark ? Colors.green.shade50 : Colors.green.shade900;
    } else if (isFavorite) {
      avatarBg = isDark ? Colors.amber.shade800 : Colors.amber.shade200;
      avatarText = isDark ? Colors.amber.shade50 : Colors.amber.shade900;
    } else {
      avatarBg = theme.colorScheme.primaryContainer;
      avatarText = theme.colorScheme.onPrimaryContainer;
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar + Name Header
            Row(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: avatarBg,
                      child: Text(
                        occupant.initials,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: avatarText,
                        ),
                      ),
                    ),
                    if (isFavorite)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.amber.shade900 : Colors.amber.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.star, size: 14, color: Colors.amber.shade800),
                      )
                    else if (occupant.isMe)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.green.shade900 : Colors.green.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person, size: 14, color: Colors.green.shade700),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        occupant.occupantName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (occupant.isMe)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "Mon bureau",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            )
                          else if (isFavorite)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "⭐ Favori",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          if (occupant.isDelegated)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "Réservé par ${occupant.bookedByName ?? 'un collègue'}",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Desk & Location Details Card
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.desk, color: theme.colorScheme.primary),
                      title: const Text("Bureau", style: TextStyle(fontSize: 12)),
                      subtitle: Text(
                        deskName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    if (roomName.isNotEmpty) ...[
                      const Divider(height: 8),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.meeting_room_outlined, color: theme.colorScheme.primary),
                        title: const Text("Pièce / Zone", style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                          roomName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                    if (occupant.occupantEmail != null && occupant.occupantEmail!.isNotEmpty) ...[
                      const Divider(height: 8),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.email_outlined, color: theme.colorScheme.primary),
                        title: const Text("Email", style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                          occupant.occupantEmail!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            if (!occupant.isMe && onToggleFavorite != null)
              OutlinedButton.icon(
                icon: Icon(isFavorite ? Icons.star_border : Icons.star),
                label: Text(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris"),
                onPressed: () {
                  Navigator.pop(context);
                  onToggleFavorite!();
                },
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fermer"),
            ),
          ],
        ),
      ),
    );
  }

  String _extractRoomName(String name) {
    final lastDash = name.lastIndexOf('-');
    if (lastDash > 0 && lastDash < name.length - 1) {
      final suffix = name.substring(lastDash + 1);
      if (suffix.length <= 4 && !suffix.contains(' ')) {
        return name.substring(0, lastDash);
      }
    }
    return name;
  }
}
