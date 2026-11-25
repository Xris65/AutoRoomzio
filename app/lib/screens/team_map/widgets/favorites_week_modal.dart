import 'dart:async';
import 'package:flutter/material.dart';
import '../../../api_service.dart';
import '../../../models/colleague.dart';
import '../../../models/desk_occupant.dart';
import '../../../offline_state_manager.dart';
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
  final VoidCallback? onManageFavorites;

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
    this.onManageFavorites,
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
    VoidCallback? onManageFavorites,
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
        onManageFavorites: onManageFavorites,
      ),
    );
  }

  @override
  State<FavoritesWeekModal> createState() => _FavoritesWeekModalState();
}

class _FavoritesWeekModalState extends State<FavoritesWeekModal> {
  static const List<String> _shortMonths = <String>[
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  late DateTime _initialWeekAnchor;
  late DateTime _currentWeekAnchor;
  late List<DateTime> _weekDays;
  late String _selectedIso;
  late bool _localShowIndicators;
  late bool _isLoadingWeek;
  late Map<String, Map<String, DeskOccupant>> _localCache;
  final Set<String> _modalFetchedKeys = <String>{};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initialWeekAnchor = normalizeLocalDate(widget.selectedDate);
    _currentWeekAnchor = _initialWeekAnchor;
    _weekDays = TeamMapHelpers.getVisibleWeekDays(
      _currentWeekAnchor,
      hideWeekends: widget.hideWeekends,
    );
    _selectedIso = DateHelpers.formatIsoDate(widget.selectedDate);
    _localShowIndicators = widget.initialShowIndicators;
    _localCache = Map<String, Map<String, DeskOccupant>>.from(
      widget.occupancyCache,
    );
    _isLoadingWeek = false;
    _loadMissingWeekOccupancy(fromInitState: true);
  }

  void _setWeekAnchor(DateTime nextAnchor) {
    final normalized = normalizeLocalDate(nextAnchor);
    setState(() {
      _currentWeekAnchor = normalized;
      _weekDays = TeamMapHelpers.getVisibleWeekDays(
        _currentWeekAnchor,
        hideWeekends: widget.hideWeekends,
      );
    });
    _loadMissingWeekOccupancy();
  }

  void _loadMissingWeekOccupancy({bool fromInitState = false}) {
    final floorId = widget.floorId;
    final generation = ++_loadGeneration;
    final missingDays = floorId == null
        ? <DateTime>[]
        : _weekDays.where((DateTime d) {
            final dStr = DateHelpers.formatIsoDate(d);
            final cacheKey = '${floorId}_$dStr';
            return dStr != _selectedIso &&
                !_modalFetchedKeys.contains(cacheKey);
          }).toList();

    if (missingDays.isEmpty || floorId == null) {
      if (fromInitState) {
        _isLoadingWeek = false;
      } else if (mounted && _isLoadingWeek) {
        setState(() {
          _isLoadingWeek = false;
        });
      }
      return;
    }

    if (fromInitState) {
      _isLoadingWeek = true;
    } else if (mounted) {
      setState(() {
        _isLoadingWeek = true;
      });
    }
    unawaited(_loadMissingDays(floorId, missingDays, generation));
  }

  Future<void> _loadMissingDays(
    String floorId,
    List<DateTime> missingDays,
    int generation,
  ) async {
    try {
      final String? token = await widget.apiService.refreshMyToken();
      final delegatedMap = await widget.storageService.getDelegatedBookingsMap();
      final savedEmail = await widget.storageService.getSavedEmail();
      final String? myUserId = (token != null && token.isNotEmpty)
          ? await widget.apiService.getCurrentUserId(token)
          : null;

      await Future.wait<void>(
        missingDays.map<Future<void>>((DateTime d) async {
          final dStr = DateHelpers.formatIsoDate(d);
          final cacheKey = '${floorId}_$dStr';
          try {
            if (token != null && token.isNotEmpty) {
              final occs = await widget.apiService.getFloorOccupants(
                token,
                floorId,
                dStr,
                myUserId: myUserId,
                myUserEmail: savedEmail,
                delegatedBookingsMap: delegatedMap,
              );
              if (!OfflineStateManager.instance.isOffline || occs.isNotEmpty) {
                _modalFetchedKeys.add(cacheKey);
                _localCache[cacheKey] = occs;
                await widget.storageService
                    .saveFloorOccupants(floorId, dStr, occs);
                widget.onCacheUpdated(cacheKey, occs);
                return;
              }
            }
            final cached =
                await widget.storageService.getFloorOccupants(floorId, dStr);
            if (cached.isNotEmpty || !_localCache.containsKey(cacheKey)) {
              _localCache[cacheKey] = cached;
            }
          } catch (_) {
            final cached =
                await widget.storageService.getFloorOccupants(floorId, dStr);
            if (cached.isNotEmpty && !_localCache.containsKey(cacheKey)) {
              _localCache[cacheKey] = cached;
            }
          }
        }),
      );
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoadingWeek = false;
        });
      }
    }
  }

  String _formatWeekRangeLabel(DateTime first, DateTime last) {
    final firstMonth = _shortMonths[first.month - 1];
    final lastMonth = _shortMonths[last.month - 1];
    if (first.year == last.year) {
      return '${first.day} $firstMonth – ${last.day} $lastMonth ${last.year}';
    }
    return '${first.day} $firstMonth ${first.year} – ${last.day} $lastMonth ${last.year}';
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
    final isInitialWeek =
        calendarDaysBetween(_initialWeekAnchor, _currentWeekAnchor).abs() < 7;
    final weekRangeText = _weekDays.isNotEmpty
        ? _formatWeekRangeLabel(_weekDays.first, _weekDays.last)
        : DateHelpers.formatFrenchDate(_currentWeekAnchor, includeYear: true);

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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.onManageFavorites != null)
                    Tooltip(
                      message: 'Gérer mes favoris',
                      child: TextButton.icon(
                        key: const ValueKey<String>(
                          'modal_manage_favorites_btn',
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onManageFavorites?.call();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Gérer'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        IconButton(
                          key: const ValueKey<String>('fav_week_prev_btn'),
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Semaine précédente',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setWeekAnchor(
                            addCalendarDays(_currentWeekAnchor, -7),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            weekRangeText,
                            key: const ValueKey<String>('fav_week_range_label'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey<String>('fav_week_next_btn'),
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Semaine suivante',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _setWeekAnchor(
                            addCalendarDays(_currentWeekAnchor, 7),
                          ),
                        ),
                      ],
                    ),
                    if (!isInitialWeek)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: TextButton.icon(
                          key: const ValueKey<String>('fav_week_reset_btn'),
                          onPressed: () => _setWeekAnchor(_initialWeekAnchor),
                          icon: const Icon(Icons.today_rounded, size: 15),
                          label: const Text(
                            'Revenir à cette semaine',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                  ],
                ),
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
    var presentDaysCount = 0;
    for (final d in _weekDays) {
      final dStr = DateHelpers.formatIsoDate(d);
      final occ = TeamMapHelpers.findOccupantForColleague(
        weekOccupants[dStr] ?? const <String, DeskOccupant>{},
        fav,
      );
      if (occ != null) {
        presentDaysCount++;
      }
    }

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
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: presentDaysCount > 0
                        ? Colors.amber.withValues(alpha: isDark ? 0.25 : 0.2)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$presentDaysCount/${_weekDays.length} j.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: presentDaysCount > 0
                          ? (isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
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
                final dayLabel = DateHelpers.formatShortDay(d);
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
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  dayLabel,
                                  maxLines: 1,
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
