import 'dart:async';
import 'package:flutter/material.dart';
import '../../../api_service.dart';
import '../../../models/colleague.dart';
import '../../../models/desk_occupant.dart';
import '../../../storage_service.dart';
import '../../../utils/date_helpers.dart';
import '../models/team_map_models.dart';

/// Icône composite calendrier + étoile utilisée dans l'AppBar et la modale
/// « Semaine de mes favoris ».
class FavoritesWeekIcon extends StatelessWidget {
  final bool dimStar;

  const FavoritesWeekIcon({
    super.key,
    this.dimStar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        const Icon(Icons.calendar_month_rounded),
        Positioned(
          right: -4,
          bottom: -3,
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.star_rounded,
              size: 12,
              color: dimStar
                  ? Colors.amber.withValues(alpha: 0.55)
                  : Colors.amber,
            ),
          ),
        ),
      ],
    );
  }
}

/// Feuille modale affichant la présence hebdomadaire des collègues favoris.
class FavoritesWeekModal extends StatefulWidget {
  final DateTime selectedDate;
  final String? floorId;
  final bool hideWeekends;
  final bool initialShowIndicators;
  final List<Colleague> savedFavorites;
  final Map<String, DeskOccupant> currentOccupants;
  final Map<String, Map<String, DeskOccupant>> occupancyCache;
  final List<Map<String, dynamic>> allWorkspaces;
  final Set<String> favoriteIds;
  final Set<String> favoriteEmailsNormalized;
  final Set<String> favoriteNamesNormalized;
  final RoomzApiService apiService;
  final StorageService storageService;
  final void Function(String cacheKey, Map<String, DeskOccupant> occs)
      onCacheUpdated;
  final void Function(DateTime targetDay, String workspaceId) onJumpToDesk;
  final Future<void> Function(bool enabled) onToggleIndicators;

  const FavoritesWeekModal({
    super.key,
    required this.selectedDate,
    required this.floorId,
    required this.hideWeekends,
    required this.initialShowIndicators,
    required this.savedFavorites,
    required this.currentOccupants,
    required this.occupancyCache,
    required this.allWorkspaces,
    required this.favoriteIds,
    required this.favoriteEmailsNormalized,
    required this.favoriteNamesNormalized,
    required this.apiService,
    required this.storageService,
    required this.onCacheUpdated,
    required this.onJumpToDesk,
    required this.onToggleIndicators,
  });

  static Future<void> show({
    required BuildContext context,
    required DateTime selectedDate,
    required String? floorId,
    required bool hideWeekends,
    required bool showFavoriteWeekIndicators,
    required List<Colleague> savedFavorites,
    required Map<String, DeskOccupant> currentOccupants,
    required Map<String, Map<String, DeskOccupant>> occupancyCache,
    required List<Map<String, dynamic>> allWorkspaces,
    required Set<String> favoriteIds,
    required Set<String> favoriteEmailsNormalized,
    required Set<String> favoriteNamesNormalized,
    required RoomzApiService apiService,
    required StorageService storageService,
    required void Function(String cacheKey, Map<String, DeskOccupant> occs)
        onCacheUpdated,
    required void Function(DateTime targetDay, String workspaceId) onJumpToDesk,
    required Future<void> Function(bool enabled) onToggleIndicators,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetCtx) => FavoritesWeekModal(
        selectedDate: selectedDate,
        floorId: floorId,
        hideWeekends: hideWeekends,
        initialShowIndicators: showFavoriteWeekIndicators,
        savedFavorites: savedFavorites,
        currentOccupants: currentOccupants,
        occupancyCache: occupancyCache,
        allWorkspaces: allWorkspaces,
        favoriteIds: favoriteIds,
        favoriteEmailsNormalized: favoriteEmailsNormalized,
        favoriteNamesNormalized: favoriteNamesNormalized,
        apiService: apiService,
        storageService: storageService,
        onCacheUpdated: onCacheUpdated,
        onJumpToDesk: onJumpToDesk,
        onToggleIndicators: onToggleIndicators,
      ),
    );
  }

  @override
  State<FavoritesWeekModal> createState() => _FavoritesWeekModalState();
}

class _FavoritesWeekModalState extends State<FavoritesWeekModal> {
  late List<DateTime> _weekDays;
  late String _selectedIso;
  late bool _localShowIndicators;
  late bool _isLoadingWeek;
  late Map<String, Map<String, DeskOccupant>> _localCache;

  @override
  void initState() {
    super.initState();
    _weekDays = TeamMapHelpers.getVisibleWeekDays(
      widget.selectedDate,
      hideWeekends: widget.hideWeekends,
    );
    _selectedIso = DateHelpers.formatIsoDate(widget.selectedDate);
    _localShowIndicators = widget.initialShowIndicators;
    _localCache = Map<String, Map<String, DeskOccupant>>.from(
      widget.occupancyCache,
    );

    final floorId = widget.floorId;
    final missingDays = floorId == null
        ? <DateTime>[]
        : _weekDays.where((DateTime d) {
            final dStr = DateHelpers.formatIsoDate(d);
            return dStr != _selectedIso &&
                !_localCache.containsKey('${floorId}_$dStr');
          }).toList();

    _isLoadingWeek = missingDays.isNotEmpty;
    if (missingDays.isNotEmpty && floorId != null) {
      unawaited(_loadMissingDays(floorId, missingDays));
    }
  }

  Future<void> _loadMissingDays(
    String floorId,
    List<DateTime> missingDays,
  ) async {
    try {
      final String? token = await widget.apiService.refreshMyToken();
      final delegatedMap = await widget.storageService.getDelegatedBookingsMap();
      final savedEmail = await widget.storageService.getSavedEmail();

      await Future.wait<void>(
        missingDays.map<Future<void>>((DateTime d) async {
          final dStr = DateHelpers.formatIsoDate(d);
          try {
            var occs =
                await widget.storageService.getFloorOccupants(floorId, dStr);
            if (occs.isEmpty && token != null && token.isNotEmpty) {
              occs = await widget.apiService.getFloorOccupants(
                token,
                floorId,
                dStr,
                myUserEmail: savedEmail,
                delegatedBookingsMap: delegatedMap,
              );
              if (occs.isNotEmpty) {
                await widget.storageService
                    .saveFloorOccupants(floorId, dStr, occs);
              }
            }
            if (occs.isNotEmpty) {
              final cacheKey = '${floorId}_$dStr';
              _localCache[cacheKey] = occs;
              widget.onCacheUpdated(cacheKey, occs);
            }
          } catch (_) {}
        }),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWeek = false;
        });
      }
    }
  }

  Map<String, Map<String, DeskOccupant>> _buildWeekOccupants() {
    final weekOccupants = <String, Map<String, DeskOccupant>>{};
    final floorId = widget.floorId;
    for (final d in _weekDays) {
      final dStr = DateHelpers.formatIsoDate(d);
      if (dStr == _selectedIso) {
        weekOccupants[dStr] = widget.currentOccupants;
      } else if (floorId != null) {
        weekOccupants[dStr] =
            _localCache['${floorId}_$dStr'] ?? const <String, DeskOccupant>{};
      } else {
        weekOccupants[dStr] = const <String, DeskOccupant>{};
      }
    }
    return weekOccupants;
  }

  List<Colleague> _buildFavoritesList(
    Map<String, Map<String, DeskOccupant>> weekOccupants,
  ) {
    final favoritesList = List<Colleague>.from(widget.savedFavorites);
    for (final occs in weekOccupants.values) {
      for (final occ in occs.values) {
        if (!TeamMapHelpers.isOccupantFavorite(
          occ,
          favoriteIds: widget.favoriteIds,
          favoriteEmailsNormalized: widget.favoriteEmailsNormalized,
          favoriteNamesNormalized: widget.favoriteNamesNormalized,
        )) {
          continue;
        }
        final alreadyPresent = favoritesList.any((Colleague fav) =>
            (occ.occupantId != null &&
                fav.id.isNotEmpty &&
                occ.occupantId!.toLowerCase() == fav.id.toLowerCase()) ||
            (occ.occupantEmail != null &&
                fav.email.isNotEmpty &&
                occ.occupantEmail!.toLowerCase() == fav.email.toLowerCase()) ||
            (fav.name.trim().isNotEmpty &&
                occ.occupantName.trim().toLowerCase() ==
                    fav.name.trim().toLowerCase()));
        if (!alreadyPresent) {
          favoritesList.add(
            Colleague(
              id: occ.occupantId ?? TeamMapHelpers.occupantUniqueKey(occ),
              name: occ.occupantName,
              email: occ.occupantEmail ?? '',
              isFavorite: true,
            ),
          );
        }
      }
    }
    return favoritesList;
  }

  @override
  Widget build(BuildContext context) {
    final weekOccupants = _buildWeekOccupants();
    final favoritesList = _buildFavoritesList(weekOccupants);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const FavoritesWeekIcon(),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Semaine de mes favoris',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (_isLoadingWeek) ...<Widget>[
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 8),
              if (favoritesList.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Aucun collègue favori configuré pour le moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: favoritesList.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (BuildContext ctx, int index) {
                      final fav = favoritesList[index];
                      return _buildFavoriteWeekCard(
                        context,
                        theme,
                        isDark,
                        fav,
                        weekOccupants,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey('modal_toggle_favorite_week_indicators'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Afficher les compteurs ⭐ sur la barre des jours',
                  style: TextStyle(fontSize: 13),
                ),
                value: _localShowIndicators,
                onChanged: (bool val) async {
                  await widget.onToggleIndicators(val);
                  if (mounted) {
                    setState(() {
                      _localShowIndicators = val;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteWeekCard(
    BuildContext sheetCtx,
    ThemeData theme,
    bool isDark,
    Colleague fav,
    Map<String, Map<String, DeskOccupant>> weekOccupants,
  ) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fav.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: _weekDays.map<Widget>((DateTime d) {
                final dStr = DateHelpers.formatIsoDate(d);
                final occ = TeamMapHelpers.findOccupantForColleague(
                  weekOccupants[dStr] ?? const <String, DeskOccupant>{},
                  fav,
                );
                final dayLabel =
                    DateHelpers.frenchShortWeekdaysList[d.weekday - 1];
                final deskDisplay = occ != null
                    ? TeamMapHelpers.resolveDeskDisplayName(
                        widget.allWorkspaces,
                        occ.workspaceId,
                      )
                    : '—';
                final isPresent = occ != null;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: isPresent
                          ? Colors.amber.withValues(alpha: isDark ? 0.25 : 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: ValueKey('fav_week_cell_${fav.id}_$dStr'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: isPresent
                            ? () {
                                Navigator.pop(sheetCtx);
                                widget.onJumpToDesk(d, occ.workspaceId);
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 3,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPresent
                                  ? Colors.amber.shade700.withValues(alpha: 0.5)
                                  : theme.dividerColor.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                dayLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPresent
                                      ? (isDark
                                          ? Colors.amber.shade200
                                          : Colors.amber.shade900)
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                deskDisplay,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isPresent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isPresent
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
