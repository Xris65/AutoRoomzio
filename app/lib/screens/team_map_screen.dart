import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../models/desk_occupant.dart';
import '../models/colleague.dart';
import '../api_service.dart';
import '../storage_service.dart';
import '../widgets/workspace_map_viewer.dart';
import '../widgets/occupant_details_sheet.dart';
import '../widgets/colleague_selection_dialog.dart';
import '../widgets/action_loading_overlay.dart';

class _RoomSummary {
  final String roomName;
  final int totalOccupants;
  final List<DeskOccupant> favoriteOccupants;
  bool get hasFavorites => favoriteOccupants.isNotEmpty;

  _RoomSummary({
    required this.roomName,
    required this.totalOccupants,
    required this.favoriteOccupants,
  });
}

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

  const TeamMapScreen({
    super.key,
    this.initialDate,
    this.initialSiteId,
    this.initialFloorId,
    this.hideWeekends,
    this.storageService,
    this.apiService,
  });

  @override
  State<TeamMapScreen> createState() => _TeamMapScreenState();
}

class _TeamMapScreenState extends State<TeamMapScreen> {
  late final StorageService _storage = widget.storageService ?? StorageService();
  late final RoomzApiService _api = widget.apiService ?? RoomzApiService();

  late DateTime _selectedDate;
  String? _siteId;
  String? _floorId;
  String? _defaultWorkspaceId;
  String? _cachedAccessToken;
  int _occupancyRequestId = 0;

  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _features = [];
  List<Map<String, dynamic>> _allWorkspaces = [];
  List<Map<String, dynamic>> _workspaces = [];
  Map<String, DeskOccupant> _occupants = {};

  Set<String> _favoriteIds = {};
  Set<String> _favoriteNamesNormalized = {};
  Set<String> _favoriteWorkspaceIds = {};

  String? _focusedRoom;
  String? _focusedWorkspaceId;
  String? _selectedDeskId;
  Timer? _selectionTimer;
  Set<String> _requestedDates = {};
  Set<String> _bookedDates = {};
  Map<String, String> _requestedWorkspacesMap = {};
  final TextEditingController _colleagueSearchController = TextEditingController();
  String _colleagueSearchQuery = '';

  bool _isLoading = true;
  bool _isOccupancyLoading = false;
  bool _isOccupantsPanelExpanded = false;
  bool _isActionInProgress = false;
  String? _actionLoadingMessage;
  bool _hideWeekends = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    if (widget.hideWeekends != null) {
      _hideWeekends = widget.hideWeekends!;
    }
    _colleagueSearchController.addListener(() {
      if (mounted) {
        setState(() {
          _colleagueSearchQuery = _colleagueSearchController.text.trim();
        });
      }
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _colleagueSearchController.dispose();
    super.dispose();
  }

  String _formatDateIso(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _formatDateFrench(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    const weekdays = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche'
    ];
    const months = [
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
      'déc.'
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];

    if (diff == 0) return "Aujourd'hui (${date.day} $month)";
    if (diff == 1) return "Demain (${date.day} $month)";
    if (diff == -1) return "Hier (${date.day} $month)";
    return "$weekday ${date.day} $month";
  }

  String _extractRoomName(Map<String, dynamic> workspace) {
    if (workspace['roomName'] != null &&
        workspace['roomName'].toString().isNotEmpty) {
      return workspace['roomName'].toString();
    }
    final name =
        workspace['name']?.toString() ?? workspace['id']?.toString() ?? '';
    final lastDash = name.lastIndexOf('-');
    if (lastDash > 0 && lastDash < name.length - 1) {
      final suffix = name.substring(lastDash + 1).trim();
      if (suffix.length <= 4 && !suffix.contains(' ')) {
        return name.substring(0, lastDash).trim();
      }
    }
    return name.trim();
  }

  Future<void> _loadFavorites() async {
    final favs = await _storage.getFavoriteColleagues();
    final favIds = <String>{};
    final favNames = <String>{};
    final favWsIds = <String>{};

    for (final f in favs) {
      if (f.id.isNotEmpty) favIds.add(f.id.toLowerCase());
      if (f.email.isNotEmpty) favIds.add(f.email.toLowerCase());
      if (f.name.isNotEmpty) favNames.add(f.name.trim().toLowerCase());
      if (f.deskName != null && f.deskName!.isNotEmpty) {
        favWsIds.add(f.deskName!.toLowerCase());
      }
    }

    if (mounted) {
      setState(() {
        _favoriteIds = favIds;
        _favoriteNamesNormalized = favNames;
        _favoriteWorkspaceIds = favWsIds;
      });
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hw = await _storage.getHideWeekends();
      if (mounted) {
        setState(() {
          _hideWeekends = widget.hideWeekends ?? hw;
        });
      } else {
        _hideWeekends = widget.hideWeekends ?? hw;
      }
      _requestedDates = (await _storage.getRequestedDates()).toSet();
      _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();
      _bookedDates = (await _storage.getBookedDates()).toSet();

      await _loadFavorites();

      _siteId = widget.initialSiteId ?? await _storage.getSiteId();
      _floorId = widget.initialFloorId ?? await _storage.getFloorId();
      _defaultWorkspaceId = await _storage.getWorkspaceId();

      String? token = await _api.refreshMyToken();
      token ??= await _storage.getRefreshToken();
      _cachedAccessToken = token;

      if (token == null || token.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Session expirée. Veuillez vous reconnecter.";
        });
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

      // If site or floor not stored, fetch from API
      if (_siteId == null || _siteId!.isEmpty) {
        final sites = await _api.getSites(token);
        if (sites.isNotEmpty) {
          _siteId = sites.first['id']?.toString();
        }
      }

      if (_siteId != null && _siteId!.isNotEmpty) {
        _floors = await _api.getFloors(token, _siteId!);
        if (_floorId == null || _floorId!.isEmpty) {
          if (_floors.isNotEmpty) {
            _floorId = _floors.first['id']?.toString();
          }
        }
      }

      if (_floorId == null || _floorId!.isEmpty || _siteId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Aucun étage ou bâtiment configuré.";
        });
        return;
      }

      await _loadFloorMapAndOccupancy(token, _siteId!, _floorId!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Erreur de chargement: $e";
        });
      }
    }
  }

  Future<void> _loadFloorMapAndOccupancy(
      String token, String siteId, String floorId) async {
    try {
      final dateStr = _formatDateIso(_selectedDate);

      final futures = await Future.wait<dynamic>([
        _api.getFloorPlanData(token, siteId, floorId),
        _api.getAllWorkspaces(token, siteId, floorId),
        _api.getFloorOccupants(token, floorId, dateStr),
      ]);

      final planData = futures[0];
      final List<Map<String, dynamic>> allWs = futures[1] is List
          ? (futures[1] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final Map<String, DeskOccupant> occs = futures[2] is Map
          ? Map<String, DeskOccupant>.from(futures[2] as Map)
          : <String, DeskOccupant>{};

      List<Map<String, dynamic>> features;
      if (planData is List) {
        features = planData.whereType<Map<String, dynamic>>().toList();
      } else if (planData is Map) {
        final raw = planData['features'] ?? planData['data'] ?? [];
        if (raw is List) {
          features = raw.whereType<Map<String, dynamic>>().toList();
        } else {
          features = [];
        }
      } else {
        features = [];
      }
      final bookable = allWs.where((w) {
        return w['isReservable'] == true ||
            w['bookable'] == true ||
            w['isBookable'] == true;
      }).toList();

      if (mounted) {
        final hasMe = occs.values.any((o) => o.isMe);
        if (hasMe) {
          _bookedDates.add(_formatDateIso(_selectedDate));
        }
        setState(() {
          _features = features;
          _allWorkspaces = allWs;
          _workspaces = bookable;
          _occupants = occs;
          _isLoading = false;
          _isOccupancyLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOccupancyLoading = false;
          if (_features.isEmpty) {
            _errorMessage = "Erreur lors du chargement de l'étage: $e";
          }
        });
        if (_features.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Erreur de mise à jour: $e"),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadOccupancyForDate(DateTime date) async {
    final requestId = ++_occupancyRequestId;
    setState(() => _isOccupancyLoading = true);
    try {
      _requestedDates = (await _storage.getRequestedDates()).toSet();
      _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();

      String? token = _cachedAccessToken;
      if (token == null || token.isEmpty) {
        token = await _api.refreshMyToken() ?? await _storage.getRefreshToken();
        _cachedAccessToken = token;
      }

      if (token != null && token.isNotEmpty && _floorId != null) {
        final dateStr = _formatDateIso(date);
        final occs = await _api.getFloorOccupants(token, _floorId!, dateStr);
        if (mounted && requestId == _occupancyRequestId) {
          final hasMe = occs.values.any((o) => o.isMe);
          if (hasMe) {
            _bookedDates.add(dateStr);
          }
          setState(() {
            _occupants = occs;
            _isOccupancyLoading = false;
          });
        }
      } else {
        if (mounted && requestId == _occupancyRequestId) {
          setState(() => _isOccupancyLoading = false);
        }
      }
    } catch (e) {
      if (mounted && requestId == _occupancyRequestId) {
        setState(() => _isOccupancyLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Impossible de charger les présences : $e"),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _fetchOccupants() async {
    await _loadOccupancyForDate(_selectedDate);
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final hw = await _storage.getHideWeekends();
      if (mounted) {
        setState(() => _hideWeekends = widget.hideWeekends ?? hw);
      } else {
        _hideWeekends = widget.hideWeekends ?? hw;
      }
      String? token = await _api.refreshMyToken(force: true);
      token ??= await _storage.getRefreshToken();
      _cachedAccessToken = token;
      _requestedDates = (await _storage.getRequestedDates()).toSet();
      _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();
      await _loadFavorites();
      if (token != null && token.isNotEmpty && _siteId != null && _floorId != null) {
        await _loadFloorMapAndOccupancy(token, _siteId!, _floorId!);
      } else {
        await _loadInitialData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de l'actualisation: $e")),
        );
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
    final newDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + offsetDays);
    setState(() {
      _selectedDate = newDate;
    });
    _loadOccupancyForDate(newDate);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final isWeekendSelected = _selectedDate.weekday == DateTime.saturday || _selectedDate.weekday == DateTime.sunday;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      selectableDayPredicate: (_hideWeekends && !isWeekendSelected)
          ? (date) => date.weekday != DateTime.saturday && date.weekday != DateTime.sunday
          : null,
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadOccupancyForDate(picked);
    }
  }

  Future<void> _changeFloor(String newFloorId) async {
    if (newFloorId == _floorId) return;
    setState(() {
      _floorId = newFloorId;
      _isLoading = true;
      _focusedRoom = null;
    });
    String? token = _cachedAccessToken;
    if (token == null || token.isEmpty) {
      token = await _api.refreshMyToken() ?? await _storage.getRefreshToken();
      _cachedAccessToken = token;
    }
    if (token != null && _siteId != null) {
      await _loadFloorMapAndOccupancy(token, _siteId!, newFloorId);
    }
  }

  bool _isOccupantFavorite(DeskOccupant occupant) {
    if (occupant.isMe) return false;
    if (occupant.occupantId != null &&
        (_favoriteIds.contains(occupant.occupantId!.toLowerCase()) ||
            _favoriteIds.contains(occupant.occupantId!))) {
      return true;
    }
    if (_favoriteNamesNormalized
        .contains(occupant.occupantName.trim().toLowerCase())) {
      return true;
    }
    return false;
  }

  Future<void> _toggleFavorite(DeskOccupant occupant) async {
    try {
      final isFav = _isOccupantFavorite(occupant);
      String? token = await _api.refreshMyToken();
      token ??= await _storage.getRefreshToken();
      final occId = occupant.occupantId ?? '';

      if (isFav) {
        if (token != null && token.isNotEmpty && occId.isNotEmpty) {
          await _api.removeFavorite(token, occId);
        }
        if (occId.isNotEmpty) {
          await _storage.removeFavoriteColleague(occId);
        }
        if (occupant.occupantEmail != null && occupant.occupantEmail!.isNotEmpty) {
          await _storage.removeFavoriteColleague(occupant.occupantEmail!);
        }
        await _storage.removeFavoriteColleague(occupant.occupantName);
      } else {
        if (token != null && token.isNotEmpty && occId.isNotEmpty) {
          await _api.addFavorite(token, occId);
        }
        final newFav = Colleague(
          id: occId.isNotEmpty ? occId : 'occ_${occupant.workspaceId}',
          name: occupant.occupantName,
          email: occupant.occupantEmail ?? '',
          isFavorite: true,
          deskName: occupant.workspaceId,
        );
        await _storage.addFavoriteColleague(newFav);
      }
      await _loadFavorites();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFav
                ? '${occupant.occupantName} retiré(e) des favoris'
                : '${occupant.occupantName} ajouté(e) aux favoris'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de la mise à jour des favoris: $e")),
        );
      }
    }
  }

  Future<void> _showOccupantDetails(
      Map<String, dynamic> workspace, DeskOccupant occupant) async {
    _selectionTimer?.cancel();
    final wsId = workspace['id']?.toString() ?? occupant.workspaceId;
    setState(() {
      _selectedDeskId = wsId;
    });

    final isFav = _isOccupantFavorite(occupant);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final isPast = target.isBefore(today);

    final dateStr = _formatDateIso(_selectedDate);
    final delegatedMap = await _storage.getDelegatedBookingsMap();
    final compositeKey = '$dateStr#$wsId';
    final isDelegated = occupant.isDelegated ||
        delegatedMap.containsKey(compositeKey) ||
        delegatedMap.containsKey(dateStr);

    if (!mounted) return;

    await OccupantDetailsSheet.show(
      context: context,
      workspace: workspace,
      occupant: occupant,
      isFavorite: isFav,
      onToggleFavorite: () => _toggleFavorite(occupant),
      onCancelMyBooking: (!isPast && occupant.isMe)
          ? () => _cancelMyBooking(workspace, occupant)
          : null,
      onCancelDelegatedBooking: (!isPast && (isDelegated || occupant.isDelegated) && !occupant.isMe)
          ? () => _cancelDelegatedBooking(workspace, occupant)
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
      Map<String, dynamic> workspace, DeskOccupant occupant) async {
    final dateStr = _formatDateIso(_selectedDate);
    final wsId = workspace['id']?.toString() ?? occupant.workspaceId;

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = "Libération de votre place...";
    });

    try {
      String? token = _cachedAccessToken;
      if (token == null || token.isEmpty) {
        token = await _api.refreshMyToken() ?? await _storage.getRefreshToken();
        _cachedAccessToken = token;
      }

      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Session expirée. Veuillez vous reconnecter."),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      bool success = await _api.cancelReservation(dateStr, token, wsId);
      if (!success) {
        success = await _api.cancelBookingByDate(token, dateStr);
      }

      if (success) {
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
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Impossible de libérer la place"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de l'annulation: $e"),
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
      Map<String, dynamic> workspace, DeskOccupant occupant) async {
    final dateStr = _formatDateIso(_selectedDate);
    final wsId = workspace['id']?.toString() ?? occupant.workspaceId;

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = "Libération de la place du collègue...";
    });

    try {
      String? token = _cachedAccessToken;
      if (token == null || token.isEmpty) {
        token = await _api.refreshMyToken() ?? await _storage.getRefreshToken();
        _cachedAccessToken = token;
      }

      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Session expirée. Veuillez vous reconnecter."),
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
              content: Text("Réservation pour le collègue libérée avec succès"),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchOccupants();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Impossible de libérer la place du collègue"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la libération: $e"),
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
    final dateStr = _formatDateIso(_selectedDate);
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

    await _storage.addRequestedDate(dateStr, workspaceId: wsId, workspaceName: deskName);
    _requestedDates = (await _storage.getRequestedDates()).toSet();
    _requestedWorkspacesMap = await _storage.getRequestedWorkspacesMap();

    final ignored = await _storage.getIgnoredDates();
    if (ignored.contains(dateStr)) {
      ignored.remove(dateStr);
      await _storage.saveIgnoredDates(ignored);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Bureau $deskName programmé (En attente) pour le ${_formatDateFrench(_selectedDate)}"),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  Future<void> _cancelDeskProgramming(Map<String, dynamic> workspace) async {
    final dateStr = _formatDateIso(_selectedDate);
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Programmation annulée pour le bureau $deskName (${_formatDateFrench(_selectedDate)})"),
          backgroundColor: Colors.grey.shade800,
        ),
      );
    }
  }

  Future<void> _showFreeDeskSheet(Map<String, dynamic> workspace) async {
    _selectionTimer?.cancel();
    final wsId = workspace['id']?.toString() ?? '';
    setState(() => _selectedDeskId = wsId);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final diffInDays = target.difference(today).inDays;
    final isPast = diffInDays < 0;
    final isBeyond13Days = diffInDays > 13;
    final hideWe = widget.hideWeekends ?? await _storage.getHideWeekends();
    if (!mounted) return;
    _hideWeekends = hideWe;
    final isWeekend = _selectedDate.weekday == DateTime.saturday ||
        _selectedDate.weekday == DateTime.sunday;
    final isWeekendBlocked = hideWe && isWeekend;

    final dateStr = _formatDateIso(_selectedDate);
    final hasMyBooking = _hasConfirmedReservationForDate(_selectedDate);
    final pendingWs = _requestedWorkspacesMap[dateStr] ?? _defaultWorkspaceId;
    final isPending = !hasMyBooking &&
        _requestedDates.contains(dateStr) &&
        (pendingWs == null ||
         pendingWs.toLowerCase() == wsId.toLowerCase() ||
         pendingWs.toLowerCase() == (workspace['name']?.toString() ?? '').toLowerCase());

    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;
    final roomName = workspace['roomName']?.toString() ?? _extractRoomName(workspace);
    final theme = Theme.of(context);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.desk, color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deskName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (roomName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              roomName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPending
                            ? Colors.blue.withValues(alpha: 0.2)
                            : Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isPending ? "En attente" : "Libre",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPending ? Colors.blue.shade800 : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          _formatDateFrench(_selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isWeekendBlocked) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade700.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_busy, color: Colors.orange.shade900, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Réservations fermées le weekend",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.brightness == Brightness.dark
                                  ? Colors.orange.shade200
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (isPast) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "La réservation directe n'est pas disponible pour une date passée.",
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.brightness == Brightness.dark
                                  ? Colors.amber.shade200
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (isPending) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade700.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.pending_actions, color: Colors.blue.shade700, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Programmation en attente",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Ce bureau sera réservé automatiquement par AutoRoomzio dès l'ouverture des créneaux (J-13).",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text("Annuler la programmation"),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _cancelDeskProgramming(workspace);
                    },
                  ),
                  const SizedBox(height: 8),
                ] else if (isBeyond13Days) ...[
                  if (!kIsWeb) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.schedule_rounded),
                      label: const Text("Programmer ce bureau (En attente)"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _programDeskInAdvance(workspace);
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text("Réserver pour un collègue"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "La réservation pour un collègue est limitée à J+13.",
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blueGrey.shade400.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blueGrey.shade700, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "La réservation directe n'est pas encore ouverte pour cette date (créneaux ouverts jusqu'à 13 jours à l'avance).",
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ] else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text("Réserver ce bureau pour moi"),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _reserveForMe(workspace);
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text("Réserver ce bureau pour un collègue"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _reserveForColleague(workspace);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fermer"),
                ),
              ],
            ),
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
        const SnackBar(content: Text("Les réservations sont fermées le weekend")),
      );
      return;
    }

    final dateStr = _formatDateIso(_selectedDate);
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

    final me = existingMe;
    if (me != null) {
      final oldWsId = me.workspaceId;
      final existingDesk = _allWorkspaces.firstWhere(
        (w) =>
            w['id']?.toString().toLowerCase() == oldWsId.toLowerCase() ||
            w['name']?.toString().toLowerCase() == oldWsId.toLowerCase(),
        orElse: () => <String, dynamic>{'name': oldWsId},
      );
      final existingDeskName = existingDesk['name']?.toString() ??
          existingDesk['workspaceName']?.toString() ??
          oldWsId;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Remplacer votre réservation ?"),
          content: Text(
            "Vous avez déjà réservé la place $existingDeskName pour cette journée.\n\n"
            "En réservant la place $deskName, votre place actuelle sera automatiquement libérée et remplacée.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Confirmer le remplacement"),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = existingMe != null
          ? "Remplacement de votre réservation..."
          : "Réservation en cours...";
    });

    try {
      String? token = _cachedAccessToken;
      if (token == null || token.isEmpty) {
        token = await _api.refreshMyToken() ?? await _storage.getRefreshToken();
        _cachedAccessToken = token;
      }

      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Session expirée. Veuillez vous reconnecter.")),
          );
        }
        return;
      }

      if (existingMe != null) {
        final oldWsId = existingMe.workspaceId;
        bool cancelSuccess = await _api.cancelReservation(dateStr, token, oldWsId);
        if (!cancelSuccess) {
          await _api.cancelBookingByDate(token, dateStr);
        }
      }

      final success = await _api.reserveWorkspace(dateStr, token, wsId);
      if (success) {
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
              content: Text(existingMe != null
                  ? "Réservation remplacée : Bureau $deskName réservé pour le ${_formatDateFrench(_selectedDate)}"
                  : "Bureau $deskName réservé avec succès pour le ${_formatDateFrench(_selectedDate)}"),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchOccupants();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Échec de la réservation du bureau $deskName"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la réservation: $e"),
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
        const SnackBar(content: Text("Les réservations sont fermées le weekend")),
      );
      return;
    }

    final dateStr = _formatDateIso(_selectedDate);
    final wsId = workspace['id']?.toString() ?? '';
    final deskName = workspace['name']?.toString() ??
        workspace['workspaceName']?.toString() ??
        wsId;

    final alreadySeatedMap = <String, String>{};
    for (final occ in _occupants.values) {
      final ws = _allWorkspaces.firstWhere(
        (w) =>
            w['id']?.toString().toLowerCase() == occ.workspaceId.toLowerCase() ||
            w['name']?.toString().toLowerCase() == occ.workspaceId.toLowerCase(),
        orElse: () => <String, dynamic>{'name': occ.workspaceId},
      );
      final seatedDeskName = ws['name']?.toString() ??
          ws['workspaceName']?.toString() ??
          occ.workspaceId;

      if (occ.occupantId != null && occ.occupantId!.isNotEmpty) {
        alreadySeatedMap[occ.occupantId!] = seatedDeskName;
        alreadySeatedMap[occ.occupantId!.toLowerCase()] = seatedDeskName;
      }
      if (occ.occupantName.isNotEmpty) {
        alreadySeatedMap[occ.occupantName] = seatedDeskName;
        alreadySeatedMap[occ.occupantName.toLowerCase()] = seatedDeskName;
      }
      if (occ.occupantEmail != null && occ.occupantEmail!.isNotEmpty) {
        alreadySeatedMap[occ.occupantEmail!] = seatedDeskName;
        alreadySeatedMap[occ.occupantEmail!.toLowerCase()] = seatedDeskName;
      }
    }

    final colleague = await showDialog<Colleague>(
      context: context,
      builder: (ctx) => ColleagueSelectionDialog(
        date: dateStr,
        deskName: deskName,
        apiService: _api,
        storageService: _storage,
        alreadySeatedColleagues: alreadySeatedMap,
      ),
    );

    if (colleague == null) return;

    setState(() {
      _isActionInProgress = true;
      _actionLoadingMessage = "Réservation pour ${colleague.name}...";
    });

    try {
      String? token = _cachedAccessToken;
      if (token == null || token.isEmpty) {
        token = await _api.refreshMyToken() ?? await _storage.getRefreshToken();
        _cachedAccessToken = token;
      }

      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Session expirée. Veuillez vous reconnecter.")),
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
        final delegatedMap = await _storage.getDelegatedBookingsMap();
        final eventId = result.eventId ?? '';
        delegatedMap[dateStr] = '$wsId|${colleague.name}|$deskName|$eventId|${colleague.id}';
        await _storage.saveDelegatedBookingsMap(delegatedMap);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.getLocalizedMessage(colleague.name)),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchOccupants();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.getLocalizedMessage(colleague.name)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la réservation: $e"),
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
    final dateStr = _formatDateIso(date);
    if (_formatDateIso(_selectedDate) == dateStr) {
      if (_occupants.values.any((o) => o.isMe)) return true;
    }
    return _bookedDates.contains(dateStr);
  }

  bool _isPendingReservationForDate(DateTime date) {
    if (_hasConfirmedReservationForDate(date)) return false;
    final dateStr = _formatDateIso(date);
    if (!_requestedDates.contains(dateStr)) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diffInDays = target.difference(today).inDays;
    return diffInDays > 13 || _requestedDates.contains(dateStr);
  }

  Set<String> _getPendingWorkspaceIdsForSelectedDate() {
    if (_hasConfirmedReservationForDate(_selectedDate)) return {};
    final dateStr = _formatDateIso(_selectedDate);
    if (!_requestedDates.contains(dateStr)) return {};
    final wsId = _requestedWorkspacesMap[dateStr] ?? _defaultWorkspaceId;
    if (wsId != null && wsId.isNotEmpty) {
      if (_occupants.containsKey(wsId) || _occupants.containsKey(wsId.toLowerCase())) {
        return {};
      }
      return {wsId.toLowerCase(), wsId};
    }
    return {};
  }

  List<_RoomSummary> get _roomSummaries {
    final Map<String, List<DeskOccupant>> roomOccupants = {};
    final Set<String> seenWorkspaceIds = {};

    for (final entry in _occupants.entries) {
      final occ = entry.value;
      if (!seenWorkspaceIds.add(occ.workspaceId.toLowerCase())) continue;

      final wsId = occ.workspaceId;
      final ws = _allWorkspaces.firstWhere(
        (w) =>
            w['id']?.toString().toLowerCase() == wsId.toLowerCase() ||
            w['name']?.toString().toLowerCase() == wsId.toLowerCase(),
        orElse: () => <String, dynamic>{'id': wsId},
      );
      final rName = _extractRoomName(ws);
      if (rName.isNotEmpty) {
        roomOccupants.putIfAbsent(rName, () => []).add(occ);
      }
    }

    final list = roomOccupants.entries.map((entry) {
      final rName = entry.key;
      final occs = entry.value;
      final favs = occs.where(_isOccupantFavorite).toList();
      return _RoomSummary(
        roomName: rName,
        totalOccupants: occs.length,
        favoriteOccupants: favs,
      );
    }).toList();

    list.sort((a, b) {
      // 1. Favorite colleague count (descending)
      final favComp = b.favoriteOccupants.length.compareTo(a.favoriteOccupants.length);
      if (favComp != 0) return favComp;
      // 2. Total occupant count (descending)
      final occComp = b.totalOccupants.compareTo(a.totalOccupants);
      if (occComp != 0) return occComp;
      // 3. Room name alphabetical
      return a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase());
    });

    return list;
  }

  Widget _buildRoomFilterBar() {
    final summaries = _roomSummaries;

    return Container(
      height: 48,
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            FilterChip(
              label: Text(
                  'Tous les bureaux (${_workspaces.isNotEmpty ? _workspaces.length : _allWorkspaces.length})'),
              selected: _focusedRoom == null,
              onSelected: (_) => setState(() => _focusedRoom = null),
            ),
            const SizedBox(width: 8),
            ...summaries.map((s) {
              final isSelected = _focusedRoom == s.roomName;
              if (s.hasFavorites) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                    label: Text('${s.roomName} (${s.favoriteOccupants.length})'),
                    selected: isSelected,
                    selectedColor: Colors.amber.withValues(alpha: 0.25),
                    checkmarkColor: Colors.amber.shade900,
                    onSelected: (selected) {
                      setState(() => _focusedRoom = selected ? s.roomName : null);
                    },
                  ),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('${s.roomName} (${s.totalOccupants})'),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _focusedRoom = selected ? s.roomName : null);
                    },
                  ),
                );
              }
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
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
          children: [
            _buildLegendItem(
              color: isDark ? const Color(0xFFD97706) : const Color(0xFFFBBF24),
              border: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
              label: "Collègue favori",
              starPrefix: true,
            ),
            const SizedBox(width: 14),
            _buildLegendItem(
              color: isDark ? const Color(0xFF15803D) : const Color(0xFF22C55E),
              border: isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534),
              label: "Mon bureau",
            ),
            const SizedBox(width: 14),
            _buildLegendItem(
              color: isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1),
              border: isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8),
              label: "Occupé",
            ),
            const SizedBox(width: 14),
            _buildLegendItem(
              color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE),
              border: isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD),
              label: "Libre",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required Color border,
    required String label,
    bool starPrefix = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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

  Widget _buildDateNavigationBar() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day) == today;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: "Jour précédent",
            onPressed: () => _changeDate(-1),
          ),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _formatDateFrench(_selectedDate),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_hasConfirmedReservationForDate(_selectedDate)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check_circle_outline, size: 11, color: Colors.green),
                            SizedBox(width: 3),
                            Text(
                              "Votre bureau",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_isPendingReservationForDate(_selectedDate)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.schedule, size: 11, color: Colors.blue),
                            SizedBox(width: 3),
                            Text(
                              "En attente",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isToday)
                TextButton(
                  onPressed: () {
                    setState(() => _selectedDate = DateTime.now());
                    _loadOccupancyForDate(DateTime.now());
                  },
                  child: const Text("Aujourd'hui", style: TextStyle(fontSize: 12)),
                ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: "Jour suivant",
                onPressed: () => _changeDate(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomSilhouette({
    required double titleWidth,
    required int deskCount,
    required double deskWidth,
    required double deskHeight,
    bool isRow = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room title / identifier silhouette
          Container(
            width: titleWidth,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 10),
          // Inner desk silhouette blocks
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: isRow
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        deskCount,
                        (_) => Container(
                          width: deskWidth,
                          height: deskHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        deskCount,
                        (_) => Container(
                          width: deskWidth,
                          height: deskHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF424242) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          const double margin = 16.0;
          const double gap = 14.0;

          if (w <= 0 || h <= 0) return const SizedBox.shrink();

          // Horizontal partition: 2 columns in upper section
          // Total width = margin + wLeft + gap + wRight + margin = w
          final double netW = (w - (2 * margin) - gap).clamp(0.0, double.infinity);
          final double wLeft = (netW * 0.52).roundToDouble();
          final double wRight = netW - wLeft;

          // Vertical partition: Upper section (Rooms 1..4) and Lower section (Room 5)
          // Total height = margin + upperH + gap + h5 + margin = h
          final double netH = (h - (2 * margin) - gap).clamp(0.0, double.infinity);
          final double h5 = (netH * 0.25).roundToDouble();
          final double upperH = netH - h5;

          // Left column vertical partition: Room 1 (top) and Room 3 (bottom)
          // Total left upper height = h1 + gap + h3 = upperH
          final double netUpperHLeft = (upperH - gap).clamp(0.0, double.infinity);
          final double h1 = (netUpperHLeft * 0.45).roundToDouble();
          final double h3 = netUpperHLeft - h1;

          // Right column vertical partition: Room 2 (top) and Room 4 (bottom)
          // Total right upper height = h2 + gap + h4 = upperH
          final double netUpperHRight = (upperH - gap).clamp(0.0, double.infinity);
          final double h2 = (netUpperHRight * 0.55).roundToDouble();
          final double h4 = netUpperHRight - h2;

          // Coordinates
          final double left1 = margin;
          final double top1 = margin;

          final double left2 = margin + wLeft + gap;
          final double top2 = margin;

          final double left3 = margin;
          final double top3 = margin + h1 + gap;

          final double left4 = margin + wLeft + gap;
          final double top4 = margin + h2 + gap;

          final double left5 = margin;
          final double top5 = margin + upperH + gap;
          final double w5 = (w - (2 * margin)).clamp(0.0, double.infinity);

          return ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // 1. Room 1 (Horizontal rectangle - North-West)
                Positioned(
                  left: left1,
                  top: top1,
                  width: wLeft,
                  height: h1,
                  child: _buildRoomSilhouette(
                    titleWidth: 70,
                    deskCount: 4,
                    deskWidth: 32,
                    deskHeight: 24,
                  ),
                ),
                // 2. Room 2 (Vertical rectangle - North-East)
                Positioned(
                  left: left2,
                  top: top2,
                  width: wRight,
                  height: h2,
                  child: _buildRoomSilhouette(
                    titleWidth: 55,
                    deskCount: 6,
                    deskWidth: 26,
                    deskHeight: 26,
                  ),
                ),
                // 3. Room 3 (Vertical rectangle - Mid-West)
                Positioned(
                  left: left3,
                  top: top3,
                  width: wLeft,
                  height: h3,
                  child: _buildRoomSilhouette(
                    titleWidth: 65,
                    deskCount: 4,
                    deskWidth: 32,
                    deskHeight: 26,
                  ),
                ),
                // 4. Room 4 (Square - Mid-East)
                Positioned(
                  left: left4,
                  top: top4,
                  width: wRight,
                  height: h4,
                  child: _buildRoomSilhouette(
                    titleWidth: 50,
                    deskCount: 4,
                    deskWidth: 28,
                    deskHeight: 28,
                  ),
                ),
                // 5. Room 5 (Horizontal rectangle - South)
                Positioned(
                  left: left5,
                  top: top5,
                  width: w5,
                  height: h5,
                  child: _buildRoomSilhouette(
                    titleWidth: 90,
                    deskCount: 6,
                    deskWidth: 36,
                    deskHeight: 22,
                    isRow: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Compute count of seated favorites deduplicated by workspaceId
    final Set<String> seenFavWsIds = {};
    final favoritesSeatedCount = _occupants.values.where((occ) {
      if (!_isOccupantFavorite(occ)) return false;
      return seenFavWsIds.add(occ.workspaceId.toLowerCase());
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Plan d'équipe"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Actualiser',
            onPressed: _refreshData,
          ),
          if (_floors.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _floorId,
                  icon: const Icon(Icons.arrow_drop_down),
                  items: _floors.map((f) {
                    final id = f['id']?.toString() ?? '';
                    final name = f['name']?.toString() ?? 'Étage $id';
                    return DropdownMenuItem(value: id, child: Text(name));
                  }).toList(),
                  onChanged: (newId) {
                    if (newId != null) _changeFloor(newId);
                  },
                ),
              ),
            )
          else if (_floors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  _floors.first['name']?.toString() ?? '',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
      body: ActionLoadingOverlay(
        isLoading: _isActionInProgress,
        message: _actionLoadingMessage,
        child: Column(
          children: [
            _buildDateNavigationBar(),
          if (_errorMessage == null) ...[
            _buildRoomFilterBar(),
            _buildLegend(),
          ],
          Expanded(
            child: _isLoading
                ? _buildMapSkeleton()
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 48),
                              const SizedBox(height: 12),
                              Text(_errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadInitialData,
                                child: const Text("Réessayer"),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          WorkspaceMapViewer(
                            features: _features,
                            workspaces: _workspaces,
                            allWorkspaces: _allWorkspaces,
                            occupants: _occupants,
                            favoriteIds: _favoriteIds,
                            favoriteNamesNormalized: _favoriteNamesNormalized,
                            favoriteWorkspaceIds: _favoriteWorkspaceIds,
                            selectedWorkspaceId: _selectedDeskId,
                            defaultWorkspaceId: _defaultWorkspaceId,
                            focusedRoom: _focusedRoom,
                            focusedWorkspaceId: _focusedWorkspaceId,
                            pendingWorkspaceIds: _getPendingWorkspaceIdsForSelectedDate(),
                            onBackgroundTapped: () {
                              _selectionTimer?.cancel();
                              if (_selectedDeskId != null) {
                                setState(() {
                                  _selectedDeskId = null;
                                });
                              }
                            },
                            onSelected: (workspace) {
                              _selectionTimer?.cancel();
                              _showFreeDeskSheet(workspace);
                            },
                            onOccupantTapped: (ws, occ) {
                              _selectionTimer?.cancel();
                              final wsId = ws['id']?.toString() ?? occ.workspaceId;
                              setState(() {
                                _focusedWorkspaceId = wsId;
                              });
                              _showOccupantDetails(ws, occ);
                            },
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
                                      horizontal: 12, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                      SizedBox(width: 8),
                                      Text("Mise à jour...",
                                          style: TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (_isOccupantsPanelExpanded)
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _isOccupantsPanelExpanded = false),
                              ),
                            ),
                          // Collègues présents summary panel
                          _buildOccupantsSummaryPanel(theme, favoritesSeatedCount),
                        ],
                      ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildOccupantsSummaryPanel(ThemeData theme, int favoritesSeatedCount) {
    final isDark = theme.brightness == Brightness.dark;
    final totalOccupantsCount = _occupants.length;

    // Collect list of seated occupants with workspace info
    final seatedList = _occupants.entries.map((entry) {
      final wsId = entry.key;
      final occ = entry.value;
      final ws = _allWorkspaces.firstWhere(
        (w) =>
            w['id']?.toString().toLowerCase() == wsId.toLowerCase() ||
            w['name']?.toString().toLowerCase() == wsId.toLowerCase(),
        orElse: () => <String, dynamic>{'id': wsId},
      );
      final rName = _extractRoomName(ws);
      final name = ws['name']?.toString() ?? wsId;
      final parts = name.split('-');
      final deskLabel = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : name;
      final isFav = _isOccupantFavorite(occ);
      return (occupant: occ, workspace: ws, roomName: rName, deskLabel: deskLabel, isFavorite: isFav);
    }).toList();

    // Sort seatedList: favorites first, then isMe, then alphabetical
    seatedList.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      if (a.occupant.isMe && !b.occupant.isMe) return -1;
      if (!a.occupant.isMe && b.occupant.isMe) return 1;
      return a.occupant.occupantName.toLowerCase().compareTo(b.occupant.occupantName.toLowerCase());
    });

    final query = _colleagueSearchQuery.toLowerCase();
    final filteredSeatedList = seatedList.where((item) {
      if (query.isEmpty) return true;
      final name = item.occupant.occupantName.toLowerCase();
      final room = item.roomName.toLowerCase();
      final desk = item.deskLabel.toLowerCase();
      return name.contains(query) || room.contains(query) || desk.contains(query);
    }).toList();

    return Positioned(
      bottom: 12,
      left: 16,
      right: 72, // Leave space for zoom buttons
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          size: 16,
                          color: favoritesSeatedCount > 0
                              ? Colors.amber.shade800
                              : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            favoritesSeatedCount > 0
                                ? "$favoritesSeatedCount collègue${favoritesSeatedCount > 1 ? 's' : ''} favori${favoritesSeatedCount > 1 ? 's' : ''} sur site"
                                : "Aucun favori assis ce jour-là",
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
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _isOccupantsPanelExpanded = !_isOccupantsPanelExpanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Collègues présents ($totalOccupantsCount)",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Icon(
                            _isOccupantsPanelExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_isOccupantsPanelExpanded) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _colleagueSearchController,
                  decoration: InputDecoration(
                    hintText: "Rechercher un collègue ou une salle...",
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _colleagueSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _colleagueSearchController.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                if (filteredSeatedList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Text(
                        _colleagueSearchQuery.isNotEmpty
                            ? "Aucun collègue trouvé pour « $_colleagueSearchQuery »"
                            : "Aucun occupant sur cet étage",
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filteredSeatedList.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filteredSeatedList[index];
                        final occ = item.occupant;
                        final isFav = item.isFavorite;
                        final isMe = occ.isMe;

                        Color badgeBg;
                        Color badgeBorder;
                        Color badgeText;
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

                        return InkWell(
                          onTap: () {
                            _selectionTimer?.cancel();
                            final wsId = item.workspace['id']?.toString() ?? occ.workspaceId;
                            setState(() => _focusedWorkspaceId = wsId);
                            _showOccupantDetails(item.workspace, occ);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                            child: Row(
                              children: [
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
                                    children: [
                                      Row(
                                        children: [
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
                                          if (isFav) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.star, size: 12, color: Colors.amber),
                                          ],
                                          if (isMe) ...[
                                            const SizedBox(width: 4),
                                            const Text(
                                              "(Moi)",
                                              style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        "${item.roomName.isNotEmpty ? item.roomName : 'Bureau'} • ${item.deskLabel}",
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.gps_fixed, size: 16),
                                  tooltip: "Centrer sur le plan",
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  onPressed: () {
                                    final wsId = item.workspace['id']?.toString() ?? occ.workspaceId;
                                    _highlightDeskTemporarily(wsId);
                                  },
                                ),
                                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        );
                      },
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
