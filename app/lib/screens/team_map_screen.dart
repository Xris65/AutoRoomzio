import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../api_service.dart';
import '../models/colleague.dart';
import '../models/desk_occupant.dart';
import '../offline_state_manager.dart';
import '../storage_service.dart';
import '../utils/date_helpers.dart';
import '../utils/error_sanitizer.dart';
import '../utils/workspace_helpers.dart';
import '../widgets/action_loading_overlay.dart';
import '../widgets/colleague_selection_dialog.dart';
import '../widgets/occupant_details_sheet.dart';
import '../widgets/time_slider_bar.dart';
import '../widgets/workspace_map_viewer.dart';
import 'team_map/models/team_map_models.dart';
import 'team_map/widgets/colleague_management_dialogs.dart';
import 'team_map/widgets/desk_automation_sheet.dart';
import 'team_map/widgets/favorites_week_modal.dart';
import 'team_map/widgets/free_desk_booking_sheet.dart';
import 'team_map/widgets/occupants_summary_panel.dart';
import 'team_map/widgets/team_map_filter_bar.dart';
import 'team_map/widgets/team_map_skeleton.dart';

/// Dedicated interactive screen displaying the 2D floor plan with colleague tracking,
/// date navigation, floor switching, room filter chips with camera framing,
/// and occupant detail sheets.
/// (Milestone M3 - Requirement R3).
class TeamMapScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialSiteId;
  final String? initialFloorId;
  final bool? hideWeekends;
  final StorageService? storageService;
  final RoomzApiService? apiService;
  final bool isEmbedded;
  final ValueListenable<DateTime>? externalDateNotifier;
  final VoidCallback? onReservationChanged;
  final VoidCallback? onDataSynced;
  final int favoritesSyncVersion;

  const TeamMapScreen({
    super.key,
    this.initialDate,
    this.initialSiteId,
    this.initialFloorId,
    this.hideWeekends,
    this.storageService,
    this.apiService,
    this.isEmbedded = false,
    this.externalDateNotifier,
    this.onReservationChanged,
    this.onDataSynced,
    this.favoritesSyncVersion = 0,
  });

  @override
  State<TeamMapScreen> createState() => _TeamMapScreenState();
}

class _TeamMapScreenState extends State<TeamMapScreen> {
  late final StorageService _storage;
  late final RoomzApiService _api;

  late DateTime _selectedDate;
  String? _siteId;
  String? _floorId;
  String? _defaultWorkspaceId;
  String? _myUserId;
  int _occupancyRequestId = 0;

  List<Map<String, dynamic>> _floors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _features = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _allWorkspaces = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _workspaces = <Map<String, dynamic>>[];
  Map<String, DeskOccupant> _occupants = <String, DeskOccupant>{};
  final Map<String, Map<String, DeskOccupant>> _occupancyCache =
      <String, Map<String, DeskOccupant>>{};
  final Set<String> _sessionFetchedOccupancyKeys = <String>{};

  @visibleForTesting
  Map<String, Map<String, DeskOccupant>> get occupancyCache => _occupancyCache;

  List<Colleague> _favorites = <Colleague>[];
  Set<String> _favoriteIds = <String>{};
  Set<String> _favoriteEmailsNormalized = <String>{};
  Set<String> _favoriteNamesNormalized = <String>{};

  String? _focusedRoom;
  String? _focusedWorkspaceId;
  String? _selectedDeskId;
  Timer? _selectionTimer;
  Set<String> _requestedDates = <String>{};
  Set<String> _bookedDates = <String>{};
  Map<String, String> _requestedWorkspacesMap = <String, String>{};

  bool _isLoading = true;
  bool _isOccupancyLoading = false;
  bool _isOccupantsPanelExpanded = false;
  bool _isActionInProgress = false;
  String? _actionLoadingMessage;
  bool _hideWeekends = true;
  bool _showRoomHeatmap = true;
  bool _showFavoriteWeekIndicators = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _storage = widget.storageService ?? StorageService();
    _api = widget.apiService ?? RoomzApiService();
    _selectedDate = normalizeLocalDate(
      widget.initialDate ??
          widget.externalDateNotifier?.value ??
          DateTime.now(),
    );
    if (widget.hideWeekends != null) {
      _hideWeekends = widget.hideWeekends!;
    }
    _selectedDate = _adjustWeekendForwardIfNeeded(_selectedDate, _hideWeekends);
    widget.externalDateNotifier?.addListener(_handleExternalDateChanged);
    unawaited(_loadCacheFirst());
    unawaited(_loadInitialData());
  }

  @override
  void didUpdateWidget(covariant TeamMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalDateNotifier != widget.externalDateNotifier) {
      oldWidget.externalDateNotifier
          ?.removeListener(_handleExternalDateChanged);
      widget.externalDateNotifier?.addListener(_handleExternalDateChanged);
      if (widget.externalDateNotifier != null) {
        _syncSelectedDateFromExternal(widget.externalDateNotifier!.value);
      }
    }
    if (oldWidget.favoritesSyncVersion != widget.favoritesSyncVersion) {
      unawaited(_loadFavorites(notifySynced: false));
    }
  }

  @override
  void dispose() {
    widget.externalDateNotifier?.removeListener(_handleExternalDateChanged);
    _selectionTimer?.cancel();
    super.dispose();
  }

  void _handleExternalDateChanged() {
    final notifier = widget.externalDateNotifier;
    if (notifier == null || !mounted) return;
    _syncSelectedDateFromExternal(notifier.value);
  }

  void _syncSelectedDateFromExternal(DateTime nextDate) {
    final normalized = _adjustWeekendForwardIfNeeded(
      normalizeLocalDate(nextDate),
      _hideWeekends,
    );
    if (DateHelpers.isSameDay(normalized, _selectedDate)) return;
    setState(() {
      _selectedDate = normalized;
    });
    unawaited(_loadOccupancyForDate(normalized));
  }

  DateTime _adjustWeekendForwardIfNeeded(DateTime date, bool hideWeekends) {
    if (!hideWeekends) return date;
    if (date.weekday == DateTime.saturday) {
      return addCalendarDays(date, 2);
    }
    if (date.weekday == DateTime.sunday) {
      return addCalendarDays(date, 1);
    }
    return date;
  }

  ({
    Set<String> ids,
    Set<String> emails,
    Set<String> names,
  }) _buildFavoriteLookupSets(List<Colleague> favs) {
    final favIds = <String>{};
    final favEmails = <String>{};
    final favNames = <String>{};

    for (final f in favs) {
      if (f.id.isNotEmpty) favIds.add(f.id.toLowerCase());
      if (f.email.isNotEmpty) {
        final emailLower = f.email.trim().toLowerCase();
        favIds.add(emailLower);
        favEmails.add(emailLower);
      }
      if (f.name.trim().isNotEmpty) {
        favNames.add(f.name.trim().toLowerCase());
      }
    }

    return (ids: favIds, emails: favEmails, names: favNames);
  }

  List<DateTime> _build13DayAndVisibleWeekDates(DateTime baseDate) {
    final seenIso = <String>{};
    final dates = <DateTime>[];

    void addIfUnique(DateTime d) {
      final normalized = normalizeLocalDate(d);
      final iso = DateHelpers.formatIsoDate(normalized);
      if (seenIso.add(iso)) {
        dates.add(normalized);
      }
    }

    final visibleWeek = TeamMapHelpers.getVisibleWeekDays(
      baseDate,
      hideWeekends: _hideWeekends,
    );
    for (final d in visibleWeek) {
      addIfUnique(d);
    }

    final today = normalizeLocalDate(DateTime.now());
    for (var i = 0; i <= 13; i++) {
      final d = addCalendarDays(today, i);
      if (_hideWeekends &&
          (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) {
        continue;
      }
      addIfUnique(d);
    }

    return dates;
  }

  Future<void> _loadFavorites({bool notifySynced = true}) async {
    final favs = await _storage.getFavoriteColleagues();
    final favSets = _buildFavoriteLookupSets(favs);

    if (mounted) {
      setState(() {
        _favorites = favs;
        _favoriteIds = favSets.ids;
        _favoriteEmailsNormalized = favSets.emails;
        _favoriteNamesNormalized = favSets.names;
      });
    }
    if (notifySynced) {
      widget.onDataSynced?.call();
    }
  }

  Future<void> _loadCacheFirst() async {
    try {
      final floorId = widget.initialFloorId ??
          await _storage.getMapSelectedFloorId() ??
          await _storage.getFloorId();
      final dateStr = DateHelpers.formatIsoDate(_selectedDate);
      final showFavWeek = await _storage.getShowFavoriteWeekIndicators();
      final hw = await _storage.getHideWeekends();
      final effectiveHide = widget.hideWeekends ?? hw;
      _hideWeekends = effectiveHide;

      final (
        List<String> booked,
        List<String> elsewhere,
        Map<String, Map<String, String>> userRes,
        Map<String, DeskOccupant> occs,
        Object? planData,
        List<Map<String, dynamic>> allWs,
        List<Colleague> favs,
      ) = await (
        _storage.getBookedDates(),
        _storage.getBookedElsewhereDates(),
        _storage.getUserReservationsMap(),
        floorId != null
            ? _storage.getFloorOccupants(floorId, dateStr)
            : Future<Map<String, DeskOccupant>>.value(
                const <String, DeskOccupant>{},
              ),
        floorId != null
            ? _storage.getFloorPlanData(floorId)
            : Future<Object?>.value(null),
        floorId != null
            ? _storage.getFloorWorkspaces(floorId)
            : Future<List<Map<String, dynamic>>>.value(
                const <Map<String, dynamic>>[],
              ),
        _storage.getFavoriteColleagues(),
      ).wait;

      final allBooked = <String>{
        ...booked,
        ...elsewhere,
        ...userRes.keys,
      };
      if (occs.values.any((DeskOccupant o) => o.isMe)) {
        allBooked.add(dateStr);
      }

      final features = parseFloorFeaturesWithFallback(planData, allWs);
      final bookable = allWs.where(isBookableWorkspace).toList();

      if (floorId != null) {
        final horizonDates = _build13DayAndVisibleWeekDates(_selectedDate);
        for (final d in horizonDates) {
          final dStr = DateHelpers.formatIsoDate(d);
          final key = '${floorId}_$dStr';
          if (!_occupancyCache.containsKey(key)) {
            final cachedDay = dStr == dateStr
                ? occs
                : await _storage.getFloorOccupants(floorId, dStr);
            if (cachedDay.isNotEmpty) {
              _occupancyCache[key] = cachedDay;
              if (cachedDay.values.any((DeskOccupant o) => o.isMe)) {
                allBooked.add(dStr);
              }
            }
          }
        }
      }

      if (mounted) {
        final favSets = _buildFavoriteLookupSets(favs);
        setState(() {
          _showFavoriteWeekIndicators = showFavWeek;
          _bookedDates.addAll(allBooked);
          if (favs.isNotEmpty && _favorites.isEmpty) {
            _favorites = favs;
            _favoriteIds = favSets.ids;
            _favoriteEmailsNormalized = favSets.emails;
            _favoriteNamesNormalized = favSets.names;
          }
          if (occs.isNotEmpty && _occupants.isEmpty) {
            _occupants = occs;
          }
          if (features.isNotEmpty && _features.isEmpty) {
            _features = features;
          }
          if (allWs.isNotEmpty && _allWorkspaces.isEmpty) {
            _allWorkspaces = allWs;
            _workspaces = bookable;
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ _loadCacheFirst exception: $e');
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hw = await _storage.getHideWeekends();
      final showFavWeek = await _storage.getShowFavoriteWeekIndicators();
      _showFavoriteWeekIndicators = showFavWeek;
      final effectiveHide = widget.hideWeekends ?? hw;
      _hideWeekends = effectiveHide;
      _selectedDate =
          _adjustWeekendForwardIfNeeded(_selectedDate, effectiveHide);

      if (mounted) {
        setState(() {});
      }

      _requestedDates = (await _storage.getRequestedDates()).toSet();
      _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();
      final booked = await _storage.getBookedDates();
      final bookedElsewhere = await _storage.getBookedElsewhereDates();
      final userRes = await _storage.getUserReservationsMap();
      _bookedDates = <String>{
        ...booked,
        ...bookedElsewhere,
        ...userRes.keys,
      };

      await _loadFavorites(notifySynced: false);

      _siteId = widget.initialSiteId ?? await _storage.getSiteId();
      _floorId = widget.initialFloorId ??
          await _storage.getMapSelectedFloorId() ??
          await _storage.getFloorId();
      _defaultWorkspaceId = await _storage.getWorkspaceId();

      final String? token = await _api.refreshMyToken();
      if (token == null || token.isEmpty) {
        final storedRefresh = await _storage.getRefreshToken();
        if (storedRefresh == null || storedRefresh.isEmpty) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = ErrorSanitizer.sessionExpiredMessage;
            });
          }
          return;
        }
        if (_siteId != null && _siteId!.isNotEmpty) {
          _floors = await _storage.getCachedFloors(_siteId!);
          if ((_floorId == null || _floorId!.isEmpty) && _floors.isNotEmpty) {
            _floorId = _floors.first['id']?.toString();
          }
        }
        await _loadFloorMapFromCacheOnly();
        return;
      }

      // Sync favorites from API (preserves local custom/external favorites)
      try {
        final apiFavs = await _api.getFavorites(token);
        if (apiFavs.isNotEmpty) {
          await _storage.mergeFavoriteColleagues(apiFavs);
          await _loadFavorites();
        }
      } catch (_) {}

      if (_siteId == null || _siteId!.isEmpty) {
        try {
          final sites = await _api.getSites(token);
          if (sites.isNotEmpty) {
            _siteId = sites.first['id']?.toString();
          }
        } catch (_) {}
      }

      if (_siteId != null && _siteId!.isNotEmpty) {
        try {
          final fetchedFloors = await _api.getFloors(token, _siteId!);
          if (fetchedFloors.isNotEmpty) {
            _floors = fetchedFloors;
          } else {
            _floors = await _storage.getCachedFloors(_siteId!);
          }
        } catch (_) {
          _floors = await _storage.getCachedFloors(_siteId!);
        }
        if (_floorId == null || _floorId!.isEmpty) {
          if (_floors.isNotEmpty) {
            _floorId = _floors.first['id']?.toString();
          }
        }
      }

      if (_floorId == null || _floorId!.isEmpty || _siteId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Aucun étage ou bâtiment configuré.';
          });
        }
        return;
      }

      await _loadFloorMapAndOccupancy(token, _siteId!, _floorId!);
    } catch (e) {
      debugPrint('⚠️ Exception in _loadInitialData: $e');
      if (mounted) {
        if (_features.isNotEmpty ||
            _allWorkspaces.isNotEmpty ||
            _workspaces.isNotEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                ErrorSanitizer.sanitize(
                  e,
                  fallback: 'Mode hors-ligne : données du cache affichées.',
                ),
              ),
            ),
          );
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = ErrorSanitizer.sanitize(
              e,
              fallback: 'Erreur de chargement.',
            );
          });
        }
      }
    }
  }

  Future<void> _loadFloorMapFromCacheOnly() async {
    final floorId = _floorId;
    if (floorId == null || floorId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Aucun étage ou bâtiment configuré.';
        });
      }
      return;
    }

    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final planData = await _storage.getFloorPlanData(floorId);
    final allWs = await _storage.getFloorWorkspaces(floorId);
    final occs = await _storage.getFloorOccupants(floorId, dateStr);
    final features = parseFloorFeaturesWithFallback(planData, allWs);
    final bookable = allWs.where(isBookableWorkspace).toList();

    if (!mounted) return;
    if (features.isNotEmpty || allWs.isNotEmpty || occs.isNotEmpty) {
      _occupancyCache['${floorId}_$dateStr'] = occs;
      if (occs.values.any((DeskOccupant o) => o.isMe)) {
        _bookedDates.add(dateStr);
      }
      setState(() {
        _features = features;
        _allWorkspaces = allWs;
        _workspaces = bookable;
        _occupants = occs;
        _isLoading = false;
        _isOccupancyLoading = false;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = false;
        _isOccupancyLoading = false;
        _errorMessage = OfflineStateManager.instance.isOffline
            ? 'Mode hors-ligne : aucune donnée en cache pour cet étage.'
            : ErrorSanitizer.sessionExpiredMessage;
      });
    }
  }

  Future<void> _loadFloorMapAndOccupancy(
    String token,
    String siteId,
    String floorId, {
    bool forceRefresh = false,
  }) async {
    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    if (forceRefresh) {
      final prefix = '${floorId}_';
      _sessionFetchedOccupancyKeys.removeWhere(
        (String k) => k.startsWith(prefix),
      );
    }
    _myUserId ??= await _api.getCurrentUserId(token);
    final delegatedMap = await _storage.getDelegatedBookingsMap();
    final savedEmail = await _storage.getSavedEmail();

    Object? planData;
    List<Map<String, dynamic>> allWs = <Map<String, dynamic>>[];
    Map<String, DeskOccupant> occs = <String, DeskOccupant>{};
    Object? lastError;
    var occsFetchFailed = false;

    try {
      final (
        List<Map<String, dynamic>> rawPlan,
        List<Map<String, dynamic>> rawWs,
        Map<String, DeskOccupant> rawOccs,
      ) = await (
        _api.getFloorPlanData(token, siteId, floorId).catchError((Object e) {
          debugPrint('⚠️ getFloorPlanData error: $e');
          lastError = e;
          return <Map<String, dynamic>>[];
        }),
        _api.getAllWorkspaces(token, siteId, floorId).catchError((Object e) {
          debugPrint('⚠️ getAllWorkspaces error: $e');
          lastError ??= e;
          return <Map<String, dynamic>>[];
        }),
        _api
            .getFloorOccupants(
              token,
              floorId,
              dateStr,
              myUserId: _myUserId,
              myUserEmail: savedEmail,
              delegatedBookingsMap: delegatedMap,
            )
            .catchError((Object e) {
          debugPrint('⚠️ getFloorOccupants error: $e');
          occsFetchFailed = true;
          lastError ??= e;
          return <String, DeskOccupant>{};
        }),
      ).wait;

      if (rawPlan.isNotEmpty) {
        planData = rawPlan;
        await _storage.saveFloorPlanData(floorId, planData);
      } else {
        planData = await _storage.getFloorPlanData(floorId);
      }

      if (rawWs.isNotEmpty) {
        allWs = rawWs;
        await _storage.saveFloorWorkspaces(floorId, allWs);
      } else {
        allWs = await _storage.getFloorWorkspaces(floorId);
      }

      if (!occsFetchFailed &&
          (!OfflineStateManager.instance.isOffline || rawOccs.isNotEmpty)) {
        if (rawOccs.isNotEmpty || forceRefresh) {
          occs = rawOccs;
          await _storage.saveFloorOccupants(floorId, dateStr, occs);
        } else {
          occs = await _storage.getFloorOccupants(floorId, dateStr);
        }
        _sessionFetchedOccupancyKeys.add('${floorId}_$dateStr');
      } else {
        occs = await _storage.getFloorOccupants(floorId, dateStr);
      }
    } catch (e) {
      lastError = e;
      planData = await _storage.getFloorPlanData(floorId);
      allWs = await _storage.getFloorWorkspaces(floorId);
      occs = await _storage.getFloorOccupants(floorId, dateStr);
    }

    final features = parseFloorFeaturesWithFallback(planData, allWs);
    final bookable = allWs.where(isBookableWorkspace).toList();

    if (lastError != null &&
        features.isEmpty &&
        allWs.isEmpty &&
        occs.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOccupancyLoading = false;
          _errorMessage = ErrorSanitizer.sanitize(
            lastError,
            fallback: "Erreur lors du chargement de l'étage.",
          );
        });
      }
      return;
    }

    if (mounted) {
      if (_floorId != null) {
        _occupancyCache['${_floorId}_$dateStr'] = occs;
      }
      if (occs.values.any((DeskOccupant o) => o.isMe)) {
        _bookedDates.add(dateStr);
      }
      setState(() {
        _features = features;
        _allWorkspaces = allWs;
        _workspaces = bookable;
        _occupants = occs;
        _isLoading = false;
        _isOccupancyLoading = false;
        _errorMessage = null;
      });
      unawaited(_preloadHorizonOccupancy(_selectedDate));

      if (lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              "Données partielles affichées : ${ErrorSanitizer.sanitize(lastError, fallback: "certaines informations n'ont pu être actualisées.")}",
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadOccupancyForDate(
    DateTime date, {
    bool forceRefresh = false,
  }) async {
    final requestId = ++_occupancyRequestId;
    final dateStr = DateHelpers.formatIsoDate(date);
    final floorId = _floorId;

    if (!forceRefresh && floorId != null) {
      final cacheKey = '${floorId}_$dateStr';
      if (_occupancyCache.containsKey(cacheKey)) {
        final cachedOccs = _occupancyCache[cacheKey]!;
        if (cachedOccs.values.any((DeskOccupant o) => o.isMe)) {
          _bookedDates.add(dateStr);
        }
        setState(() {
          _occupants = cachedOccs;
          _isOccupancyLoading = false;
        });
        unawaited(_preloadHorizonOccupancy(date));
        return;
      }
    }

    setState(() => _isOccupancyLoading = true);
    try {
      _requestedDates = (await _storage.getRequestedDates()).toSet();
      _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();

      final String? token = await _api.refreshMyToken();

      if (token != null && token.isNotEmpty && floorId != null) {
        _myUserId ??= await _api.getCurrentUserId(token);
        final delegatedMap = await _storage.getDelegatedBookingsMap();
        final savedEmail = await _storage.getSavedEmail();
        var occs = await _api.getFloorOccupants(
          token,
          floorId,
          dateStr,
          myUserId: _myUserId,
          myUserEmail: savedEmail,
          delegatedBookingsMap: delegatedMap,
        );
        final cacheKey = '${floorId}_$dateStr';
        if (!OfflineStateManager.instance.isOffline || occs.isNotEmpty) {
          if (occs.isNotEmpty || forceRefresh) {
            await _storage.saveFloorOccupants(floorId, dateStr, occs);
          } else {
            final diskOccs =
                await _storage.getFloorOccupants(floorId, dateStr);
            if (diskOccs.isNotEmpty) {
              occs = diskOccs;
            } else {
              await _storage.saveFloorOccupants(floorId, dateStr, occs);
            }
          }
          _sessionFetchedOccupancyKeys.add(cacheKey);
        } else {
          occs = await _storage.getFloorOccupants(floorId, dateStr);
        }
        if (mounted && requestId == _occupancyRequestId) {
          if (!OfflineStateManager.instance.isOffline || occs.isNotEmpty) {
            _occupancyCache[cacheKey] = occs;
          }
          if (occs.values.any((DeskOccupant o) => o.isMe)) {
            _bookedDates.add(dateStr);
          }
          setState(() {
            _occupants = occs;
            _isOccupancyLoading = false;
          });
          unawaited(
            _preloadHorizonOccupancy(date, forceRefresh: forceRefresh),
          );
        }
      } else if (floorId != null) {
        final cached = await _storage.getFloorOccupants(floorId, dateStr);
        if (mounted && requestId == _occupancyRequestId) {
          if (cached.isNotEmpty) {
            _occupancyCache['${floorId}_$dateStr'] = cached;
            if (cached.values.any((DeskOccupant o) => o.isMe)) {
              _bookedDates.add(dateStr);
            }
          }
          setState(() {
            _occupants = cached;
            _isOccupancyLoading = false;
          });
        }
      } else {
        if (mounted && requestId == _occupancyRequestId) {
          setState(() => _isOccupancyLoading = false);
        }
      }
    } catch (e) {
      if (floorId != null) {
        final cached = await _storage.getFloorOccupants(floorId, dateStr);
        if (mounted && requestId == _occupancyRequestId) {
          if (cached.isNotEmpty) {
            _occupancyCache['${floorId}_$dateStr'] = cached;
            if (cached.values.any((DeskOccupant o) => o.isMe)) {
              _bookedDates.add(dateStr);
            }
          }
          setState(() {
            _occupants = cached;
            _isOccupancyLoading = false;
          });
          return;
        }
      }
      if (mounted && requestId == _occupancyRequestId) {
        setState(() => _isOccupancyLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorSanitizer.sanitize(
                e,
                fallback: 'Impossible de charger les présences.',
              ),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _preloadHorizonOccupancy(
    DateTime baseDate, {
    bool forceRefresh = false,
  }) async {
    final floorId = _floorId;
    if (floorId == null || floorId.isEmpty) return;

    if (forceRefresh) {
      final prefix = '${floorId}_';
      _sessionFetchedOccupancyKeys.removeWhere(
        (String k) => k.startsWith(prefix),
      );
    }

    final String? token = await _api.refreshMyToken();
    if (token == null || token.isEmpty) return;

    final targetDates = _build13DayAndVisibleWeekDates(baseDate);
    final missingDays = targetDates.where((DateTime d) {
      final key = '${floorId}_${DateHelpers.formatIsoDate(d)}';
      return !_sessionFetchedOccupancyKeys.contains(key);
    }).toList();

    if (missingDays.isEmpty) return;

    _myUserId ??= await _api.getCurrentUserId(token);
    final delegatedMap = await _storage.getDelegatedBookingsMap();
    final savedEmail = await _storage.getSavedEmail();

    var anyUpdated = false;
    const int chunkSize = 5;
    for (var i = 0; i < missingDays.length; i += chunkSize) {
      if (!mounted || _floorId != floorId) return;
      final end = (i + chunkSize) > missingDays.length
          ? missingDays.length
          : (i + chunkSize);
      final chunk = missingDays.sublist(i, end);

      await Future.wait<void>(
        chunk.map<Future<void>>((DateTime d) async {
          final dStr = DateHelpers.formatIsoDate(d);
          final key = '${floorId}_$dStr';
          try {
            final occs = await _api.getFloorOccupants(
              token,
              floorId,
              dStr,
              myUserId: _myUserId,
              myUserEmail: savedEmail,
              delegatedBookingsMap: delegatedMap,
            );
            if (!OfflineStateManager.instance.isOffline || occs.isNotEmpty) {
              _occupancyCache[key] = occs;
              await _storage.saveFloorOccupants(floorId, dStr, occs);
              _sessionFetchedOccupancyKeys.add(key);
              anyUpdated = true;
            }
            if (occs.values.any((DeskOccupant o) => o.isMe)) {
              _bookedDates.add(dStr);
            }
          } catch (_) {
            // Silently swallow background preload error
          }
        }),
      );

      if (mounted && _floorId == floorId && anyUpdated) {
        final currentKey =
            '${floorId}_${DateHelpers.formatIsoDate(_selectedDate)}';
        setState(() {
          if (_occupancyCache.containsKey(currentKey) && _occupants.isEmpty) {
            _occupants = _occupancyCache[currentKey]!;
          }
        });
      }
    }

    if (mounted && anyUpdated) {
      widget.onDataSynced?.call();
    }
  }

  Future<void> _fetchOccupants() async {
    final floorId = _floorId;
    if (floorId != null) {
      _occupancyCache
          .remove('${floorId}_${DateHelpers.formatIsoDate(_selectedDate)}');
    }
    await _loadOccupancyForDate(_selectedDate, forceRefresh: true);
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final hw = await _storage.getHideWeekends();
      final showFavWeek = await _storage.getShowFavoriteWeekIndicators();
      if (mounted) {
        setState(() {
          _hideWeekends = widget.hideWeekends ?? hw;
          _showFavoriteWeekIndicators = showFavWeek;
        });
      } else {
        _hideWeekends = widget.hideWeekends ?? hw;
        _showFavoriteWeekIndicators = showFavWeek;
      }

      final String? token = await _api.refreshMyToken(force: true);
      if (token == null && OfflineStateManager.instance.isOffline) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: <Widget>[
                  Icon(Icons.wifi_off_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Impossible d'actualiser : pas de connexion Internet. Données du cache conservées.",
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return;
      }

      _occupancyCache.clear();
      _sessionFetchedOccupancyKeys.clear();
      _requestedDates = (await _storage.getRequestedDates()).toSet();
      _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();

      if (token != null && token.isNotEmpty) {
        try {
          final apiFavs = await _api.getFavorites(token);
          if (apiFavs.isNotEmpty) {
            await _storage.mergeFavoriteColleagues(apiFavs);
          }
        } catch (_) {}
      }
      await _loadFavorites();

      if (token != null &&
          token.isNotEmpty &&
          _siteId != null &&
          _floorId != null) {
        await _loadFloorMapAndOccupancy(
          token,
          _siteId!,
          _floorId!,
          forceRefresh: true,
        );
      } else {
        await _loadInitialData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (OfflineStateManager.instance.isOffline ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Offline') ||
            e.toString().contains('ClientException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: <Widget>[
                  Icon(Icons.wifi_off_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Impossible d'actualiser : pas de connexion Internet. Données du cache conservées.",
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                "Erreur lors de l'actualisation: ${ErrorSanitizer.sanitize(e, fallback: "Impossible d'actualiser les données.")}",
              ),
            ),
          );
        }
      }
    }
  }

  void _highlightDeskTemporarily(String wsId) {
    _selectionTimer?.cancel();
    setState(() {
      _focusedWorkspaceId = wsId;
      _selectedDeskId = wsId;
    });
    _selectionTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _selectedDeskId == wsId) {
        setState(() {
          _selectedDeskId = null;
        });
      }
    });
  }

  void _changeDate(int offsetDays) {
    var newDate = addCalendarDays(_selectedDate, offsetDays);
    if (_hideWeekends) {
      if (offsetDays > 0) {
        while (newDate.weekday == DateTime.saturday ||
            newDate.weekday == DateTime.sunday) {
          newDate = addCalendarDays(newDate, 1);
        }
      } else if (offsetDays < 0) {
        while (newDate.weekday == DateTime.saturday ||
            newDate.weekday == DateTime.sunday) {
          newDate = addCalendarDays(newDate, -1);
        }
      }
    }
    setState(() {
      _selectedDate = newDate;
    });
    unawaited(_loadOccupancyForDate(newDate));
  }

  Future<void> _pickDate() async {
    final today = normalizeLocalDate(DateTime.now());
    final normalizedSelected = normalizeLocalDate(_selectedDate);
    final isWeekendSelected =
        normalizedSelected.weekday == DateTime.saturday ||
            normalizedSelected.weekday == DateTime.sunday;
    final picked = await showDatePicker(
      context: context,
      initialDate: normalizedSelected,
      firstDate: addCalendarDays(today, -365),
      lastDate: addCalendarDays(today, 365),
      selectableDayPredicate: (_hideWeekends && !isWeekendSelected)
          ? (DateTime date) =>
              date.weekday != DateTime.saturday &&
              date.weekday != DateTime.sunday
          : null,
    );
    if (picked != null && normalizeLocalDate(picked) != normalizedSelected) {
      final normalizedPicked = normalizeLocalDate(picked);
      setState(() {
        _selectedDate = normalizedPicked;
      });
      unawaited(_loadOccupancyForDate(normalizedPicked));
    }
  }

  Future<void> _changeFloor(String newFloorId) async {
    if (newFloorId == _floorId) return;
    try {
      await _storage.saveMapSelectedFloorId(newFloorId);
      if (!mounted) return;
      setState(() {
        _floorId = newFloorId;
        _isLoading = true;
        _focusedRoom = null;
      });

      final Object? cachedPlan = await _storage.getFloorPlanData(newFloorId);
      final cachedWs = await _storage.getFloorWorkspaces(newFloorId);
      final dateStr = DateHelpers.formatIsoDate(_selectedDate);
      final cachedOccs = await _storage.getFloorOccupants(newFloorId, dateStr);

      if (mounted && (cachedPlan != null || cachedWs.isNotEmpty)) {
        final cachedFeatures =
            parseFloorFeaturesWithFallback(cachedPlan, cachedWs);
        final bookable = cachedWs.where(isBookableWorkspace).toList();

        setState(() {
          _features = cachedFeatures;
          _allWorkspaces = cachedWs;
          _workspaces = bookable;
          _occupants = cachedOccs;
        });
      }

      final String? token = await _api.refreshMyToken();
      _siteId ??= await _storage.getSiteId();

      if (token != null &&
          token.isNotEmpty &&
          _siteId != null &&
          _siteId!.isNotEmpty) {
        await _loadFloorMapAndOccupancy(
          token,
          _siteId!,
          newFloorId,
          forceRefresh: true,
        );
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Exception in _changeFloor: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              "Erreur lors du changement d'étage: ${ErrorSanitizer.sanitize(e, fallback: 'Impossible de charger cet étage.')}",
            ),
          ),
        );
      }
    }
  }

  bool _isOccupantFavorite(DeskOccupant occupant) {
    return TeamMapHelpers.isOccupantFavorite(
      occupant,
      favoriteIds: _favoriteIds,
      favoriteEmailsNormalized: _favoriteEmailsNormalized,
      favoriteNamesNormalized: _favoriteNamesNormalized,
    );
  }

  Future<void> _toggleFavorite(DeskOccupant occupant) async {
    final occId = occupant.occupantId ?? '';
    final matchedFavorites =
        TeamMapHelpers.findMatchingFavoritesForOccupant(_favorites, occupant);
    final isLocalOnly = matchedFavorites.isNotEmpty
        ? matchedFavorites.every(
            (Colleague f) =>
                f.id.startsWith('ext_') || f.id.startsWith('occ_'),
          )
        : (occId.startsWith('ext_') || occId.startsWith('occ_'));

    if (!isLocalOnly && OfflineStateManager.instance.isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Modification impossible hors-ligne : une connexion Internet est requise pour modifier vos favoris.',
            ),
          ),
        );
      }
      return;
    }

    try {
      final isFav = _isOccupantFavorite(occupant);
      final String? token = await _api.refreshMyToken();

      if (isFav) {
        if (matchedFavorites.isNotEmpty) {
          for (final fav in matchedFavorites) {
            final deleteTargetId =
                (fav.favoriteId != null && fav.favoriteId!.isNotEmpty)
                    ? fav.favoriteId!
                    : (fav.id.isNotEmpty ? fav.id : occId);
            final isServerTarget = deleteTargetId.isNotEmpty &&
                !deleteTargetId.startsWith('ext_') &&
                !deleteTargetId.startsWith('occ_');
            if (token != null && token.isNotEmpty && isServerTarget) {
              await _api.removeFavorite(token, deleteTargetId);
            }
            if (fav.id.isNotEmpty) {
              await _storage.removeFavoriteColleague(fav.id);
            } else if (fav.email.isNotEmpty) {
              await _storage.removeFavoriteColleague(fav.email);
            }
          }
        } else {
          if (token != null &&
              token.isNotEmpty &&
              occId.isNotEmpty &&
              !occId.startsWith('ext_') &&
              !occId.startsWith('occ_')) {
            await _api.removeFavorite(token, occId);
          }
          if (occId.isNotEmpty) {
            await _storage.removeFavoriteColleague(occId);
          }
          if (occupant.occupantEmail != null &&
              occupant.occupantEmail!.isNotEmpty) {
            await _storage.removeFavoriteColleague(occupant.occupantEmail!);
          }
        }
      } else {
        String? serverFavoriteId;
        if (token != null &&
            token.isNotEmpty &&
            occId.isNotEmpty &&
            !occId.startsWith('ext_') &&
            !occId.startsWith('occ_')) {
          serverFavoriteId = await _api.addFavoriteWithId(token, occId);
        }
        final newFav = Colleague(
          id: occId.isNotEmpty ? occId : 'occ_${occupant.workspaceId}',
          name: occupant.occupantName,
          email: occupant.occupantEmail ?? '',
          isFavorite: true,
          deskName: occupant.workspaceId,
          favoriteId: serverFavoriteId,
        );
        await _storage.addFavoriteColleague(newFav);
      }

      await _loadFavorites();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFav
                  ? '${occupant.occupantName} retiré(e) des favoris'
                  : '${occupant.occupantName} ajouté(e) aux favoris',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de la mise à jour des favoris: ${ErrorSanitizer.sanitize(e, fallback: 'opération impossible.')}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showOccupantDetails(
    Map<String, dynamic> workspace,
    DeskOccupant occupant,
  ) async {
    _selectionTimer?.cancel();
    final wsId = workspace['id']?.toString() ?? occupant.workspaceId;
    setState(() {
      _selectedDeskId = wsId;
    });

    final isFav = _isOccupantFavorite(occupant);
    final today = normalizeLocalDate(DateTime.now());
    final target = normalizeLocalDate(_selectedDate);
    final isPast = target.isBefore(today);

    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final delegatedMap = await _storage.getDelegatedBookingsMap();
    final compositeKey = '$dateStr#$wsId';
    final inDelegatedStorage = delegatedMap.containsKey(compositeKey) ||
        delegatedMap[dateStr] == wsId ||
        (delegatedMap[dateStr]?.startsWith('$wsId|') ?? false);
    final isDelegatedByMe = occupant.isDelegatedByMe || inDelegatedStorage;

    final effectiveOccupant = occupant.copyWith(
      isDelegated: occupant.isDelegated || isDelegatedByMe,
      isDelegatedByMe: isDelegatedByMe,
      isDelegatedOther: !isDelegatedByMe &&
          !occupant.isDelegatedForMe &&
          (occupant.isDelegated || isDelegatedByMe),
    );

    if (!mounted) return;

    await OccupantDetailsSheet.show(
      context: context,
      workspace: workspace,
      occupant: effectiveOccupant,
      isFavorite: isFav,
      onToggleFavorite: () => unawaited(_toggleFavorite(effectiveOccupant)),
      onCancelMyBooking: (!isPast && effectiveOccupant.isMe)
          ? () => unawaited(_cancelMyBooking(workspace, effectiveOccupant))
          : null,
      onCancelDelegatedBooking:
          (!isPast && isDelegatedByMe && !effectiveOccupant.isMe)
              ? () => unawaited(
                    _cancelDelegatedBooking(workspace, effectiveOccupant),
                  )
              : null,
    );

    _selectionTimer?.cancel();
    if (mounted) {
      setState(() {
        _selectedDeskId = null;
      });
    }
  }

  Future<void> _cancelMyBooking(
    Map<String, dynamic> workspace,
    DeskOccupant occupant,
  ) async {
    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final wsId = workspace['id']?.toString() ?? occupant.workspaceId;

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = 'Libération de votre place...';
    });

    try {
      final String? token = await _api.refreshMyToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(ErrorSanitizer.sessionExpiredMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      var success = await _api.cancelReservation(dateStr, token, wsId);
      if (!success) {
        success = await _api.cancelBookingByDate(token, dateStr);
      }

      if (success) {
        await _storage.removeUserReservation(dateStr);
        _bookedDates.remove(dateStr);
        final bookedDates = await _storage.getBookedDates();
        bookedDates.remove(dateStr);
        await _storage.saveBookedDates(bookedDates);

        final bookedElsewhere = await _storage.getBookedElsewhereDates();
        bookedElsewhere.remove(dateStr);
        await _storage.saveBookedElsewhereDates(bookedElsewhere);

        final allTime = await _storage.getAllTimeBookedDates();
        allTime.remove(dateStr);
        await _storage.saveAllTimeBookedDates(allTime);

        final allTimeElsewhere = await _storage.getAllTimeElsewhereDates();
        allTimeElsewhere.remove(dateStr);
        await _storage.saveAllTimeElsewhereDates(allTimeElsewhere);

        await _fetchOccupants();
        widget.onReservationChanged?.call();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de libérer la place'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorSanitizer.sanitize(
                e,
                fallback: "Erreur lors de l'annulation.",
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _actionLoadingMessage = null;
        });
      }
    }
  }

  Future<void> _cancelDelegatedBooking(
    Map<String, dynamic> workspace,
    DeskOccupant occupant,
  ) async {
    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final wsId = workspace['id']?.toString() ?? occupant.workspaceId;

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = 'Libération de la place du collègue...';
    });

    try {
      final String? token = await _api.refreshMyToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(ErrorSanitizer.sessionExpiredMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final success = await _api.cancelReservation(
        dateStr,
        token,
        wsId,
        forUserId: occupant.occupantId,
      );

      if (success) {
        await _storage.removeDelegatedBooking(dateStr, wsId);
        final delegatedMap = await _storage.getDelegatedBookingsMap();
        if (delegatedMap.containsKey(dateStr)) {
          delegatedMap.remove(dateStr);
          await _storage.saveDelegatedBookingsMap(delegatedMap);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Réservation pour le collègue libérée avec succès'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchOccupants();
        widget.onReservationChanged?.call();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de libérer la place du collègue'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorSanitizer.sanitize(
                e,
                fallback: 'Erreur lors de la libération de la place.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _actionLoadingMessage = null;
        });
      }
    }
  }

  Future<void> _programDeskInAdvance(Map<String, dynamic> workspace) async {
    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final wsId = workspace['id']?.toString() ?? '';
    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;

    setState(() {
      _requestedDates.add(dateStr);
      if (wsId.isNotEmpty) {
        _requestedWorkspacesMap[dateStr] = wsId;
      }
    });

    await _storage.addRequestedDate(
      dateStr,
      workspaceId: wsId,
      workspaceName: deskName,
    );
    _requestedDates = (await _storage.getRequestedDates()).toSet();
    _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();

    final ignored = await _storage.getIgnoredDates();
    if (ignored.contains(dateStr)) {
      ignored.remove(dateStr);
      await _storage.saveIgnoredDates(ignored);
    }

    widget.onReservationChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bureau $deskName programmé (En attente) pour le ${DateHelpers.formatFrenchDate(_selectedDate)}',
          ),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  Future<void> _cancelDeskProgramming(Map<String, dynamic> workspace) async {
    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final wsId = workspace['id']?.toString() ?? '';
    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;

    setState(() {
      _requestedDates.remove(dateStr);
      _requestedWorkspacesMap.remove(dateStr);
    });

    await _storage.removeRequestedDate(dateStr);
    _requestedDates = (await _storage.getRequestedDates()).toSet();
    _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();

    widget.onReservationChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Programmation annulée pour le bureau $deskName (${DateHelpers.formatFrenchDate(_selectedDate)})',
          ),
          backgroundColor: Colors.grey.shade800,
        ),
      );
    }
  }

  Future<void> _showFreeDeskSheet(Map<String, dynamic> workspace) async {
    _selectionTimer?.cancel();
    final wsId = workspace['id']?.toString() ?? '';
    setState(() => _selectedDeskId = wsId);

    final hideWe = widget.hideWeekends ?? await _storage.getHideWeekends();
    if (!mounted) return;
    _hideWeekends = hideWe;

    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final hasMyBooking = _hasConfirmedReservationForDate(_selectedDate);
    final pendingWs = _requestedWorkspacesMap[dateStr] ?? _defaultWorkspaceId;
    final isPending = !hasMyBooking &&
        _requestedDates.contains(dateStr) &&
        (pendingWs == null ||
            pendingWs.toLowerCase() == wsId.toLowerCase() ||
            pendingWs.toLowerCase() ==
                (workspace['name']?.toString() ?? '').toLowerCase());

    if (_isOccupantsPanelExpanded) {
      setState(() => _isOccupantsPanelExpanded = false);
    }

    await FreeDeskBookingSheet.show(
      context: context,
      workspace: workspace,
      selectedDate: _selectedDate,
      isPending: isPending,
      hideWeekends: hideWe,
      onCancelProgramming: () => unawaited(_cancelDeskProgramming(workspace)),
      onProgramInAdvance: () => unawaited(_programDeskInAdvance(workspace)),
      onReserveForMe: () => unawaited(_reserveForMe(workspace)),
      onReserveForColleague: () => unawaited(_reserveForColleague(workspace)),
      onOpenAutomation: (String targetWsId, String deskName) {
        unawaited(
          DeskAutomationSheet.show(
            context: context,
            wsId: targetWsId,
            deskName: deskName,
            siteId: _siteId ?? '',
            floorId: _floorId ?? '',
            hideWeekends: _hideWeekends,
            storageService: _storage,
          ),
        );
      },
    );

    _selectionTimer?.cancel();
    if (mounted) {
      setState(() => _selectedDeskId = null);
    }
  }

  Future<void> _reserveForMe(Map<String, dynamic> workspace) async {
    final hideWe = widget.hideWeekends ?? await _storage.getHideWeekends();
    if (!mounted) return;
    final isWeekend = _selectedDate.weekday == DateTime.saturday ||
        _selectedDate.weekday == DateTime.sunday;
    if (hideWe && isWeekend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les réservations sont fermées le weekend')),
      );
      return;
    }

    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final wsId = workspace['id']?.toString() ?? '';
    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;

    DeskOccupant? existingMe;
    for (final o in _occupants.values) {
      if (o.isMe) {
        existingMe = o;
        break;
      }
    }

    if (existingMe != null) {
      final existingDeskName = TeamMapHelpers.resolveDeskDisplayName(
        _allWorkspaces,
        existingMe.workspaceId,
      );
      final confirmed =
          await ColleagueManagementDialogs.showReplaceMyBookingConfirmation(
        context: context,
        existingDeskName: existingDeskName,
        newDeskName: deskName,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = existingMe != null
          ? 'Remplacement de votre réservation...'
          : 'Réservation en cours...';
    });

    try {
      final String? token = await _api.refreshMyToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(ErrorSanitizer.sessionExpiredMessage),
            ),
          );
        }
        return;
      }

      if (existingMe != null) {
        final oldWsId = existingMe.workspaceId;
        final cancelSuccess =
            await _api.cancelReservation(dateStr, token, oldWsId);
        if (!cancelSuccess) {
          await _api.cancelBookingByDate(token, dateStr);
        }
      }

      final success = await _api.reserveWorkspace(dateStr, token, wsId);
      if (success) {
        await _storage.saveUserReservation(dateStr, wsId, deskName);
        _bookedDates.add(dateStr);
        final isDefault = _defaultWorkspaceId != null &&
            wsId.toLowerCase() == _defaultWorkspaceId!.toLowerCase();

        if (isDefault) {
          final bookedDates = await _storage.getBookedDates();
          if (!bookedDates.contains(dateStr)) {
            bookedDates.add(dateStr);
            await _storage.saveBookedDates(bookedDates);
          }
          final allTime = await _storage.getAllTimeBookedDates();
          if (!allTime.contains(dateStr)) {
            allTime.add(dateStr);
            await _storage.saveAllTimeBookedDates(allTime);
          }
          final elsewhere = await _storage.getBookedElsewhereDates();
          if (elsewhere.contains(dateStr)) {
            elsewhere.remove(dateStr);
            await _storage.saveBookedElsewhereDates(elsewhere);
          }
        } else {
          final elsewhere = await _storage.getBookedElsewhereDates();
          if (!elsewhere.contains(dateStr)) {
            elsewhere.add(dateStr);
            await _storage.saveBookedElsewhereDates(elsewhere);
          }
          final allTimeElsewhere = await _storage.getAllTimeElsewhereDates();
          if (!allTimeElsewhere.contains(dateStr)) {
            allTimeElsewhere.add(dateStr);
            await _storage.saveAllTimeElsewhereDates(allTimeElsewhere);
          }
          final bookedDates = await _storage.getBookedDates();
          if (bookedDates.contains(dateStr)) {
            bookedDates.remove(dateStr);
            await _storage.saveBookedDates(bookedDates);
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                existingMe != null
                    ? 'Réservation remplacée : Bureau $deskName réservé pour le ${DateHelpers.formatFrenchDate(_selectedDate)}'
                    : 'Bureau $deskName réservé avec succès pour le ${DateHelpers.formatFrenchDate(_selectedDate)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchOccupants();
        widget.onReservationChanged?.call();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de la réservation du bureau $deskName'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorSanitizer.sanitize(
                e,
                fallback: 'Erreur lors de la réservation.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _actionLoadingMessage = null;
        });
      }
    }
  }

  Future<void> _reserveForColleague(Map<String, dynamic> workspace) async {
    final hideWe = widget.hideWeekends ?? await _storage.getHideWeekends();
    if (!mounted) return;
    final isWeekend = _selectedDate.weekday == DateTime.saturday ||
        _selectedDate.weekday == DateTime.sunday;
    if (hideWe && isWeekend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les réservations sont fermées le weekend')),
      );
      return;
    }

    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    final wsId = workspace['id']?.toString() ?? '';
    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;

    final colleague =
        await ColleagueManagementDialogs.showColleagueSelectionForDesk(
      context: context,
      dateIso: dateStr,
      deskName: deskName,
      apiService: _api,
      storageService: _storage,
      occupants: _occupants,
      allWorkspaces: _allWorkspaces,
    );

    if (colleague == null || !mounted) return;

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = 'Réservation pour ${colleague.name}...';
    });

    try {
      final String? token = await _api.refreshMyToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(ErrorSanitizer.sessionExpiredMessage),
            ),
          );
        }
        return;
      }

      final result = await _api.reserveWorkspaceForColleague(
        date: dateStr,
        token: token,
        workspaceId: wsId,
        colleagueId: colleague.id,
        colleagueName: colleague.name,
        colleagueEmail: colleague.email,
      );

      if (result.isSuccess) {
        final eventId = result.eventId ?? '';
        await _storage.saveDelegatedBooking(
          dateStr,
          wsId,
          '$wsId|${colleague.name}|$deskName|$eventId|${colleague.id}',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.getLocalizedMessage(colleague.name)),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchOccupants();
        widget.onReservationChanged?.call();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorSanitizer.sanitize(
                result.getLocalizedMessage(colleague.name),
                fallback: 'Impossible de réserver pour ${colleague.name}.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorSanitizer.sanitize(
                e,
                fallback: 'Erreur lors de la réservation.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _actionLoadingMessage = null;
        });
      }
    }
  }

  bool _hasConfirmedReservationForDate(DateTime date) {
    final dateStr = DateHelpers.formatIsoDate(date);
    if (DateHelpers.formatIsoDate(_selectedDate) == dateStr) {
      if (_occupants.values.any((DeskOccupant o) => o.isMe)) return true;
    }
    return _bookedDates.contains(dateStr);
  }

  bool _isPendingReservationForDate(DateTime date) {
    if (_hasConfirmedReservationForDate(date)) return false;
    final dateStr = DateHelpers.formatIsoDate(date);
    if (!_requestedDates.contains(dateStr)) return false;
    final today = normalizeLocalDate(DateTime.now());
    final target = normalizeLocalDate(date);
    final diffInDays = calendarDaysBetween(today, target);
    return diffInDays > 13 || _requestedDates.contains(dateStr);
  }

  Set<String> _getPendingWorkspaceIdsForSelectedDate() {
    if (_hasConfirmedReservationForDate(_selectedDate)) return <String>{};
    final dateStr = DateHelpers.formatIsoDate(_selectedDate);
    if (!_requestedDates.contains(dateStr)) return <String>{};
    final wsId = _requestedWorkspacesMap[dateStr] ?? _defaultWorkspaceId;
    if (wsId != null && wsId.isNotEmpty) {
      if (_occupants.containsKey(wsId) ||
          _occupants.containsKey(wsId.toLowerCase())) {
        return <String>{};
      }
      return <String>{wsId.toLowerCase(), wsId};
    }
    return <String>{};
  }

  Map<String, int> _computeFavoriteCountsForVisibleWeek() {
    final days = TeamMapHelpers.getVisibleWeekDays(
      _selectedDate,
      hideWeekends: _hideWeekends,
    );
    final selectedIso = DateHelpers.formatIsoDate(_selectedDate);
    final counts = <String, int>{};
    for (final d in days) {
      final dStr = DateHelpers.formatIsoDate(d);
      final Map<String, DeskOccupant>? occs;
      if (dStr == selectedIso) {
        occs = _occupants;
      } else if (_floorId != null) {
        occs = _occupancyCache['${_floorId}_$dStr'];
      } else {
        occs = null;
      }
      if (occs != null && occs.isNotEmpty) {
        final favCount = TeamMapHelpers.countUniqueFavorites(
          occs,
          favoriteIds: _favoriteIds,
          favoriteEmailsNormalized: _favoriteEmailsNormalized,
          favoriteNamesNormalized: _favoriteNamesNormalized,
        );
        if (favCount > 0) {
          counts[dStr] = favCount;
        }
      }
    }
    return counts;
  }

  void _jumpToFavoriteDesk(DateTime targetDay, String wsId) {
    final normalizedTarget = normalizeLocalDate(targetDay);
    final targetIso = DateHelpers.formatIsoDate(normalizedTarget);
    final currentIso = DateHelpers.formatIsoDate(_selectedDate);
    if (targetIso != currentIso) {
      setState(() {
        _selectedDate = normalizedTarget;
      });
      unawaited(_loadOccupancyForDate(normalizedTarget));
    }
    if (_focusedWorkspaceId == wsId) {
      setState(() {
        _focusedWorkspaceId = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          _highlightDeskTemporarily(wsId);
        }
      });
    } else {
      _highlightDeskTemporarily(wsId);
    }
  }

  Future<void> _openFavoritesManager() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => ColleagueSelectionDialog(
        date: DateHelpers.formatIsoDate(_selectedDate),
        isManagementMode: true,
        apiService: _api,
        storageService: _storage,
      ),
    );
    if (!mounted) return;
    await _loadFavorites(notifySynced: false);
    widget.onDataSynced?.call();
    widget.onReservationChanged?.call();
  }

  Future<void> _showFavoritesWeekSummaryModal() async {
    final savedFavs = await _storage.getFavoriteColleagues();
    if (!mounted) return;

    await FavoritesWeekModal.show(
      context: context,
      selectedDate: _selectedDate,
      floorId: _floorId,
      hideWeekends: _hideWeekends,
      showFavoriteWeekIndicators: _showFavoriteWeekIndicators,
      savedFavorites: savedFavs,
      currentOccupants: _occupants,
      occupancyCache: _occupancyCache,
      allWorkspaces: _allWorkspaces,
      favoriteIds: _favoriteIds,
      favoriteEmailsNormalized: _favoriteEmailsNormalized,
      favoriteNamesNormalized: _favoriteNamesNormalized,
      apiService: _api,
      storageService: _storage,
      onCacheUpdated: (String cacheKey, Map<String, DeskOccupant> occs) {
        _occupancyCache[cacheKey] = occs;
        if (mounted) {
          setState(() {});
        }
      },
      onJumpToDesk: _jumpToFavoriteDesk,
      onToggleIndicators: (bool val) async {
        await _storage.saveShowFavoriteWeekIndicators(val);
        if (mounted) {
          setState(() {
            _showFavoriteWeekIndicators = val;
          });
        }
      },
      onManageFavorites: () => unawaited(_openFavoritesManager()),
    );
  }

  Widget _buildDateNavigationBar() {
    return TimeSliderBar(
      selectedDate: _selectedDate,
      hideWeekends: _hideWeekends,
      bookedDates: _bookedDates,
      pendingDates: _requestedDates,
      hasConfirmedReservation: _hasConfirmedReservationForDate,
      isPendingReservation: _isPendingReservationForDate,
      favoriteCountsByDate: _showFavoriteWeekIndicators
          ? _computeFavoriteCountsForVisibleWeek()
          : const <String, int>{},
      showFavoriteIndicators: _showFavoriteWeekIndicators,
      isLoading: _isOccupancyLoading,
      onDateSelected: (DateTime date) {
        final normalized = normalizeLocalDate(date);
        setState(() {
          _selectedDate = normalized;
        });
        unawaited(_loadOccupancyForDate(normalized));
      },
      onPreviousDay: () => _changeDate(-1),
      onNextDay: () => _changeDate(1),
      onPickDate: _pickDate,
      onToday: () {
        final today = normalizeLocalDate(DateTime.now());
        setState(() => _selectedDate = today);
        unawaited(_loadOccupancyForDate(today));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final seenFavWsIds = <String>{};
    final favoritesSeatedCount = _occupants.values.where((DeskOccupant occ) {
      if (!_isOccupantFavorite(occ)) return false;
      return seenFavWsIds.add(occ.workspaceId.toLowerCase());
    }).length;

    final effectiveFavoriteWorkspaceIds =
        TeamMapHelpers.computeEffectiveFavoriteWorkspaceIds(
      favorites: _favorites,
      occupants: _occupants,
      allWorkspaces: _allWorkspaces,
      favoriteIds: _favoriteIds,
      favoriteEmailsNormalized: _favoriteEmailsNormalized,
      favoriteNamesNormalized: _favoriteNamesNormalized,
    );

    final roomSummaries = TeamMapHelpers.buildRoomSummaries(
      occupants: _occupants,
      allWorkspaces: _allWorkspaces,
      favoriteIds: _favoriteIds,
      favoriteEmailsNormalized: _favoriteEmailsNormalized,
      favoriteNamesNormalized: _favoriteNamesNormalized,
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isEmbedded,
        toolbarHeight: widget.isEmbedded ? 48 : null,
        title: Text(
          "Plan d'équipe",
          style: widget.isEmbedded ? const TextStyle(fontSize: 17) : null,
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('plan_manage_favorites_button'),
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Gérer mes collègues favoris',
            onPressed: _openFavoritesManager,
          ),
          IconButton(
            key: const ValueKey('favorites_week_summary_button'),
            icon: FavoritesWeekIcon(dimStar: !_showFavoriteWeekIndicators),
            tooltip: 'Semaine de mes favoris',
            onPressed: _showFavoritesWeekSummaryModal,
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Actualiser',
            onPressed: _refreshData,
          ),
          IconButton(
            icon: Icon(
              _showRoomHeatmap
                  ? Icons.thermostat_rounded
                  : Icons.thermostat_outlined,
            ),
            tooltip: _showRoomHeatmap
                ? 'Désactiver la coloration thermique'
                : 'Activer la coloration thermique',
            onPressed: () {
              setState(() {
                _showRoomHeatmap = !_showRoomHeatmap;
              });
            },
          ),
          TeamMapFloorSelector(
            floors: _floors,
            selectedFloorId: _floorId,
            onFloorChanged: (String newId) => unawaited(_changeFloor(newId)),
          ),
        ],
      ),
      body: ActionLoadingOverlay(
        isLoading: _isActionInProgress,
        message: _actionLoadingMessage,
        child: Column(
          children: <Widget>[
            _buildDateNavigationBar(),
            if (_errorMessage == null) ...<Widget>[
              TeamMapRoomFilterBar(
                summaries: roomSummaries,
                totalBookableCount: _workspaces.isNotEmpty
                    ? _workspaces.length
                    : _allWorkspaces.length,
                focusedRoom: _focusedRoom,
                onFocusedRoomChanged: (String? room) {
                  setState(() => _focusedRoom = room);
                },
              ),
              const TeamMapLegendBar(),
            ],
            Expanded(
              child: _isLoading
                  ? const TeamMapSkeleton()
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadInitialData,
                                  child: const Text('Réessayer'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (
                            BuildContext context,
                            BoxConstraints constraints,
                          ) {
                            return Stack(
                              children: <Widget>[
                                WorkspaceMapViewer(
                                  features: _features,
                                  workspaces: _workspaces,
                                  allWorkspaces: _allWorkspaces,
                                  occupants: _occupants,
                                  favoriteIds: _favoriteIds,
                                  favoriteNamesNormalized:
                                      _favoriteNamesNormalized,
                                  favoriteWorkspaceIds:
                                      effectiveFavoriteWorkspaceIds,
                                  selectedWorkspaceId: _selectedDeskId,
                                  defaultWorkspaceId: _defaultWorkspaceId,
                                  focusedRoom: _focusedRoom,
                                  focusedWorkspaceId: _focusedWorkspaceId,
                                  pendingWorkspaceIds:
                                      _getPendingWorkspaceIdsForSelectedDate(),
                                  showRoomHeatmap: _showRoomHeatmap,
                                  showHeatmapToggleChip: false,
                                  onToggleHeatmap: (bool val) {
                                    setState(() {
                                      _showRoomHeatmap = val;
                                    });
                                  },
                                  onBackgroundTapped: () {
                                    _selectionTimer?.cancel();
                                    if (_selectedDeskId != null) {
                                      setState(() {
                                        _selectedDeskId = null;
                                      });
                                    }
                                  },
                                  onSelected: (Map<String, dynamic> workspace) {
                                    _selectionTimer?.cancel();
                                    unawaited(_showFreeDeskSheet(workspace));
                                  },
                                  onOccupantTapped: (
                                    Map<String, dynamic> ws,
                                    DeskOccupant occ,
                                  ) {
                                    _selectionTimer?.cancel();
                                    final wsId =
                                        ws['id']?.toString() ?? occ.workspaceId;
                                    setState(() {
                                      _focusedWorkspaceId = wsId;
                                    });
                                    unawaited(_showOccupantDetails(ws, occ));
                                  },
                                ),
                                if (_isOccupantsPanelExpanded)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(
                                        () => _isOccupantsPanelExpanded = false,
                                      ),
                                    ),
                                  ),
                                OccupantsSummaryPanel(
                                  isExpanded: _isOccupantsPanelExpanded,
                                  onToggleExpanded: () {
                                    setState(() {
                                      _isOccupantsPanelExpanded =
                                          !_isOccupantsPanelExpanded;
                                    });
                                  },
                                  onClose: () {
                                    setState(() {
                                      _isOccupantsPanelExpanded = false;
                                    });
                                  },
                                  occupants: _occupants,
                                  allWorkspaces: _allWorkspaces,
                                  favoriteIds: _favoriteIds,
                                  favoriteEmailsNormalized:
                                      _favoriteEmailsNormalized,
                                  favoriteNamesNormalized:
                                      _favoriteNamesNormalized,
                                  favoritesSeatedCount: favoritesSeatedCount,
                                  onSelectOccupant: (
                                    Map<String, dynamic> ws,
                                    DeskOccupant occ,
                                  ) {
                                    _selectionTimer?.cancel();
                                    final wsId =
                                        ws['id']?.toString() ?? occ.workspaceId;
                                    setState(() {
                                      _focusedWorkspaceId = wsId;
                                      _isOccupantsPanelExpanded = false;
                                    });
                                    unawaited(_showOccupantDetails(ws, occ));
                                  },
                                  onHighlightDesk: _highlightDeskTemporarily,
                                  availableWidth: constraints.maxWidth,
                                ),
                                if (_isOccupancyLoading)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Material(
                                      elevation: 4,
                                      borderRadius: BorderRadius.circular(20),
                                      color: theme.colorScheme.surface,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Mise à jour...',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
