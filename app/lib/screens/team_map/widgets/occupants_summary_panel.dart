import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/desk_occupant.dart';
import '../models/team_map_models.dart';

/// Panneau flottant résumant les collègues favoris et présents sur l'étage,
/// avec recherche isolée via [ValueNotifier] (aucun rebuild parent à la frappe)
/// et déduplication garantie des occupants.
class OccupantsSummaryPanel extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onClose;
  final Map<String, DeskOccupant> occupants;
  final List<Map<String, dynamic>> allWorkspaces;
  final Set<String> favoriteIds;
  final Set<String> favoriteEmailsNormalized;
  final Set<String> favoriteNamesNormalized;
  final int favoritesSeatedCount;
  final void Function(Map<String, dynamic> workspace, DeskOccupant occupant)
      onSelectOccupant;
  final ValueChanged<String> onHighlightDesk;

  const OccupantsSummaryPanel({
    super.key,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onClose,
    required this.occupants,
    required this.allWorkspaces,
    required this.favoriteIds,
    required this.favoriteEmailsNormalized,
    required this.favoriteNamesNormalized,
    required this.favoritesSeatedCount,
    required this.onSelectOccupant,
    required this.onHighlightDesk,
  });

  @override
  State<OccupantsSummaryPanel> createState() => _OccupantsSummaryPanelState();
}

class _OccupantsSummaryPanelState extends State<OccupantsSummaryPanel> {
  late final TextEditingController _searchController;
  late final ValueNotifier<String> _searchQueryNotifier;
  late final ValueNotifier<Offset> _barOffset;
  Offset _longPressStartPos = Offset.zero;
  Offset _longPressStartOffset = Offset.zero;

  List<SeatedOccupantItem> _seatedList = <SeatedOccupantItem>[];
  List<SeatedOccupantItem> _seatedFavorites = <SeatedOccupantItem>[];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchQueryNotifier = ValueNotifier<String>('');
    _barOffset = ValueNotifier<Offset>(Offset.zero);
    _searchController.addListener(_handleSearchChanged);
    _recomputeSeatedLists();
  }

  @override
  void didUpdateWidget(covariant OccupantsSummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.occupants != widget.occupants ||
        oldWidget.allWorkspaces != widget.allWorkspaces ||
        oldWidget.favoriteIds != widget.favoriteIds ||
        oldWidget.favoriteEmailsNormalized !=
            widget.favoriteEmailsNormalized ||
        oldWidget.favoriteNamesNormalized != widget.favoriteNamesNormalized) {
      _recomputeSeatedLists();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _barOffset.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim();
    if (_searchQueryNotifier.value != nextQuery) {
      _searchQueryNotifier.value = nextQuery;
    }
  }

  void _recomputeSeatedLists() {
    _seatedList = TeamMapHelpers.buildSeatedOccupants(
      occupants: widget.occupants,
      allWorkspaces: widget.allWorkspaces,
      favoriteIds: widget.favoriteIds,
      favoriteEmailsNormalized: widget.favoriteEmailsNormalized,
      favoriteNamesNormalized: widget.favoriteNamesNormalized,
    );
    _seatedFavorites = _seatedList
        .where((SeatedOccupantItem item) => item.isFavorite)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalOccupantsCount = _seatedList.length;

    return Positioned(
      bottom: 72,
      left: 16,
      right: 16,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _barOffset,
        builder: (BuildContext context, Offset barOffset, Widget? child) {
          return Transform.translate(
            offset: barOffset,
            child: child,
          );
        },
        child: TapRegion(
          groupId: 'occupants_summary_panel',
          onTapOutside: (PointerDownEvent _) {
            if (widget.isExpanded) {
              widget.onClose();
            }
          },
          child: Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surface.withValues(alpha: 0.95),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildHeaderRow(theme, isDark, totalOccupantsCount),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: widget.isExpanded
                        ? _buildExpandedContent(theme, isDark)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(
    ThemeData theme,
    bool isDark,
    int totalOccupantsCount,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPressStart: (LongPressStartDetails details) {
              HapticFeedback.selectionClick();
              _longPressStartPos = details.globalPosition;
              _longPressStartOffset = _barOffset.value;
            },
            onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
              final delta = details.globalPosition - _longPressStartPos;
              _barOffset.value = _longPressStartOffset + delta;
            },
            onLongPressEnd: (LongPressEndDetails _) {
              HapticFeedback.selectionClick();
            },
            child: InkWell(
              key: const ValueKey('toggle_occupants_panel_left'),
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.star,
                      size: 16,
                      color: widget.favoritesSeatedCount > 0
                          ? Colors.amber.shade800
                          : Colors.grey,
                    ),
                    if (_seatedFavorites.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final fav in _seatedFavorites.take(3))
                            Container(
                              margin: const EdgeInsets.only(right: 3),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFFFBBF24),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFFFDE68A)
                                      : const Color(0xFFB45309),
                                  width: 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                fav.occupant.initials,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF78350F),
                                ),
                              ),
                            ),
                          if (_seatedFavorites.length > 3)
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF78350F)
                                    : const Color(0xFFFDE68A),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '+${_seatedFavorites.length - 3}',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.amber.shade200
                                      : const Color(0xFF78350F),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.favoritesSeatedCount > 0
                            ? "${widget.favoritesSeatedCount} collègue${widget.favoritesSeatedCount > 1 ? 's' : ''} favori${widget.favoritesSeatedCount > 1 ? 's' : ''} sur site"
                            : 'Aucun favori assis ce jour-là',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<Offset>(
          valueListenable: _barOffset,
          builder: (BuildContext context, Offset off, Widget? _) {
            if (off == Offset.zero) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: const Icon(Icons.restart_alt, size: 16),
                tooltip: 'Repositionner en bas',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  _barOffset.value = Offset.zero;
                },
              ),
            );
          },
        ),
        InkWell(
          key: const ValueKey('toggle_occupants_panel_right'),
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onToggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Collègues présents ($totalOccupantsCount)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: widget.isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.isExpanded) ...<Widget>[
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('close_occupants_panel_button'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Fermer le panneau',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: widget.onClose,
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedContent(ThemeData theme, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        ValueListenableBuilder<String>(
          valueListenable: _searchQueryNotifier,
          builder: (BuildContext context, String queryText, Widget? _) {
            return TextField(
              key: const ValueKey('colleague_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un collègue ou une salle...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: queryText.isNotEmpty
                    ? IconButton(
                        key: const ValueKey('clear_colleague_search_button'),
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        ValueListenableBuilder<String>(
          valueListenable: _searchQueryNotifier,
          builder: (BuildContext context, String rawQuery, Widget? _) {
            final query = rawQuery.toLowerCase();
            final filteredList = query.isEmpty
                ? _seatedList
                : _seatedList.where((SeatedOccupantItem item) {
                    final name = item.occupant.occupantName.toLowerCase();
                    final room = item.roomName.toLowerCase();
                    final desk = item.deskLabel.toLowerCase();
                    return name.contains(query) ||
                        room.contains(query) ||
                        desk.contains(query);
                  }).toList();

            if (filteredList.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    rawQuery.isNotEmpty
                        ? 'Aucun collègue trouvé pour « $rawQuery »'
                        : 'Aucun occupant sur cet étage',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filteredList.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  return _buildOccupantRow(
                    theme,
                    isDark,
                    filteredList[index],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOccupantRow(
    ThemeData theme,
    bool isDark,
    SeatedOccupantItem item,
  ) {
    final occ = item.occupant;
    final isFav = item.isFavorite;
    final isMe = occ.isMe;

    final Color badgeBg;
    final Color badgeBorder;
    final Color badgeText;
    if (isFav) {
      badgeBg = isDark ? const Color(0xFFD97706) : const Color(0xFFFBBF24);
      badgeBorder = isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
      badgeText = isDark ? Colors.white : const Color(0xFF78350F);
    } else if (isMe) {
      badgeBg = isDark ? const Color(0xFF15803D) : const Color(0xFF22C55E);
      badgeBorder = isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534);
      badgeText = Colors.white;
    } else {
      badgeBg = isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1);
      badgeBorder = isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8);
      badgeText = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1E293B);
    }

    final wsId = item.workspace['id']?.toString() ?? occ.workspaceId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              key: ValueKey('colleague_item_${occ.workspaceId}'),
              onTap: () => widget.onSelectOccupant(item.workspace, occ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: badgeBorder, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        occ.initials,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: badgeText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  occ.occupantName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isFav) ...<Widget>[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.star,
                                  size: 12,
                                  color: Colors.amber,
                                ),
                              ],
                              if (isMe) ...<Widget>[
                                const SizedBox(width: 4),
                                const Text(
                                  '(Moi)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            "${item.roomName.isNotEmpty ? item.roomName : 'Bureau'} • ${item.deskLabel}",
                            style: TextStyle(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('colleague_gps_${occ.workspaceId}'),
            icon: const Icon(Icons.gps_fixed, size: 18),
            tooltip: 'Centrer sur le plan',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => widget.onHighlightDesk(wsId),
          ),
          IconButton(
            key: ValueKey('colleague_details_${occ.workspaceId}'),
            icon: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.grey,
            ),
            tooltip: 'Voir les détails',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => widget.onSelectOccupant(item.workspace, occ),
          ),
        ],
      ),
    );
  }
}
