import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../api_service.dart';
import '../storage_service.dart';
import '../utils/error_sanitizer.dart';
import '../utils/workspace_helpers.dart';
import '../widgets/web_pairing_dialog.dart';
import '../widgets/workspace_map_viewer.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SetupScreen extends StatefulWidget {
  final String accessToken;
  final RoomzApiService? apiService;
  final StorageService? storageService;
  final bool pickOnly;
  final String? titleOverride;

  const SetupScreen({
    super.key,
    required this.accessToken,
    this.apiService,
    this.storageService,
    this.pickOnly = false,
    this.titleOverride,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final RoomzApiService _api;
  late final StorageService _storage;

  List<Map<String, dynamic>> _sites = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _floors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _floorFeatures = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _allWorkspaces = <Map<String, dynamic>>[];
  bool _showMap = true;

  Map<String, dynamic>? _selectedSite;
  Map<String, dynamic>? _selectedFloor;
  Map<String, dynamic>? _selectedWorkspace;

  bool _loadingSites = true;
  bool _loadingFloors = false;
  bool _loadingWorkspaces = false;
  String? _errorMessage;

  int _currentStep = 0;
  String? _selectedRoomPrefix;
  Map<String, List<Map<String, dynamic>>> _rooms =
      <String, List<Map<String, dynamic>>>{};

  // Search queries
  String _siteSearch = '';
  String _floorSearch = '';
  String _roomSearch = '';

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? RoomzApiService();
    _storage = widget.storageService ?? StorageService();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loadingSites = true);

    try {
      List<Map<String, dynamic>> sites = <Map<String, dynamic>>[];
      try {
        sites = await _api.getSites(widget.accessToken);
        if (sites.isNotEmpty) {
          await _storage.saveCachedSites(sites);
        } else {
          sites = await _storage.getCachedSites();
        }
      } catch (_) {
        sites = await _storage.getCachedSites();
      }

      final String? savedSiteId = await _storage.getSiteId();
      final String? savedFloorId = await _storage.getFloorId();
      final String? savedWorkspaceId = await _storage.getWorkspaceId();

      Map<String, dynamic>? initialSite;
      Map<String, dynamic>? initialFloor;
      Map<String, dynamic>? initialWorkspace;
      String? initialRoomPrefix;
      List<Map<String, dynamic>> initialFloors = <Map<String, dynamic>>[];
      final Map<String, List<Map<String, dynamic>>> initialRooms =
          <String, List<Map<String, dynamic>>>{};

      if (savedSiteId != null) {
        try {
          initialSite = sites.firstWhere(
            (Map<String, dynamic> s) => s['id']?.toString() == savedSiteId,
          );
          try {
            initialFloors =
                await _api.getFloors(widget.accessToken, savedSiteId);
            if (initialFloors.isNotEmpty) {
              await _storage.saveCachedFloors(savedSiteId, initialFloors);
            } else {
              initialFloors = await _storage.getCachedFloors(savedSiteId);
            }
          } catch (_) {
            initialFloors = await _storage.getCachedFloors(savedSiteId);
          }

          if (savedFloorId != null) {
            initialFloor = initialFloors.firstWhere(
              (Map<String, dynamic> f) => f['id']?.toString() == savedFloorId,
            );
            List<Map<String, dynamic>> allWs = <Map<String, dynamic>>[];
            dynamic initialFeatures;
            try {
              final List<Object?> results =
                  await Future.wait<Object?>(<Future<Object?>>[
                _api.getAllWorkspaces(
                  widget.accessToken,
                  savedSiteId,
                  savedFloorId,
                ),
                _api.getFloorPlanData(
                  widget.accessToken,
                  savedSiteId,
                  savedFloorId,
                ),
              ]);
              final Object? rawWs = results[0];
              allWs = rawWs is List<dynamic>
                  ? rawWs.whereType<Map<String, dynamic>>().toList()
                  : <Map<String, dynamic>>[];
              initialFeatures = results[1];
              if (allWs.isNotEmpty) {
                await _storage.saveFloorWorkspaces(savedFloorId, allWs);
              } else {
                allWs = await _storage.getFloorWorkspaces(savedFloorId);
              }
              if ((initialFeatures is List<dynamic> &&
                      initialFeatures.isNotEmpty) ||
                  (initialFeatures is Map<dynamic, dynamic> &&
                      initialFeatures.isNotEmpty)) {
                await _storage.saveFloorPlanData(savedFloorId, initialFeatures);
              } else {
                initialFeatures = await _storage.getFloorPlanData(savedFloorId);
              }
            } catch (_) {
              allWs = await _storage.getFloorWorkspaces(savedFloorId);
              initialFeatures = await _storage.getFloorPlanData(savedFloorId);
            }

            final List<Map<String, dynamic>> workspaces =
                allWs.where(isBookableWorkspace).toList();

            if (mounted) {
              _floorFeatures =
                  parseFloorFeaturesWithFallback(initialFeatures, allWs);
              _allWorkspaces = allWs;
            }

            for (final Map<String, dynamic> ws in workspaces) {
              final String roomName = extractRoomName(ws, trim: false);
              initialRooms
                  .putIfAbsent(roomName, () => <Map<String, dynamic>>[])
                  .add(ws);

              if (ws['id']?.toString() == savedWorkspaceId) {
                initialWorkspace = ws;
                initialRoomPrefix = roomName;
              }
            }
          }
        } catch (_) {
          // If pre-fill fails (e.g., ID no longer exists), ignore and fallback to empty
        }
      }

      if (mounted) {
        setState(() {
          _sites = sites;

          if (initialSite != null) {
            _selectedSite = initialSite;
            _floors = initialFloors;
            _currentStep = 1;
          }

          if (initialFloor != null) {
            _selectedFloor = initialFloor;
            _rooms = initialRooms;
            _currentStep = 2;
          }

          if (initialWorkspace != null && initialRoomPrefix != null) {
            _selectedRoomPrefix = initialRoomPrefix;
            _selectedWorkspace = initialWorkspace;
            _currentStep = 3;
          }

          _loadingSites = false;
          if (sites.isEmpty) {
            _errorMessage =
                'Aucun bâtiment trouvé. Vérifiez votre compte MyRoomz.';
          } else {
            _errorMessage = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorSanitizer.sanitize(e);
          _loadingSites = false;
        });
      }
    }
  }

  Future<void> _onSiteSelected(Map<String, dynamic> site) async {
    final String siteId = site['id']?.toString() ?? '';
    if (!widget.pickOnly) {
      await _storage.saveSiteId(siteId);
    }
    setState(() {
      _selectedSite = site;
      _selectedFloor = null;
      _selectedRoomPrefix = null;
      _selectedWorkspace = null;
      _floors = <Map<String, dynamic>>[];
      _rooms = <String, List<Map<String, dynamic>>>{};
      _floorSearch = ''; // Reset next step search
      _loadingFloors = true;
      _currentStep = 1;
    });
    List<Map<String, dynamic>> floors = <Map<String, dynamic>>[];
    try {
      floors = await _api.getFloors(widget.accessToken, siteId);
      if (floors.isNotEmpty) {
        await _storage.saveCachedFloors(siteId, floors);
      } else {
        floors = await _storage.getCachedFloors(siteId);
      }
    } catch (_) {
      floors = await _storage.getCachedFloors(siteId);
    }
    if (mounted) {
      setState(() {
        _floors = floors;
        _loadingFloors = false;
      });
    }
  }

  Future<void> _onFloorSelected(Map<String, dynamic> floor) async {
    final String floorId = floor['id']?.toString() ?? '';
    if (!widget.pickOnly) {
      await _storage.saveFloorId(floorId);
    }
    setState(() {
      _selectedFloor = floor;
      _selectedRoomPrefix = null;
      _selectedWorkspace = null;
      _rooms = <String, List<Map<String, dynamic>>>{};
      _roomSearch = ''; // Reset next step search
      _loadingWorkspaces = true;
      _currentStep = 2;
    });

    final String siteId = _selectedSite!['id']?.toString() ?? '';

    List<Map<String, dynamic>> allWs = <Map<String, dynamic>>[];
    dynamic features;
    try {
      final List<Object?> results =
          await Future.wait<Object?>(<Future<Object?>>[
        _api.getAllWorkspaces(widget.accessToken, siteId, floorId),
        _api.getFloorPlanData(widget.accessToken, siteId, floorId),
      ]);
      final Object? rawWs = results[0];
      allWs = rawWs is List<dynamic>
          ? rawWs.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      features = results[1];
      if (allWs.isNotEmpty) {
        await _storage.saveFloorWorkspaces(floorId, allWs);
      } else {
        allWs = await _storage.getFloorWorkspaces(floorId);
      }
      if ((features is List<dynamic> && features.isNotEmpty) ||
          (features is Map<dynamic, dynamic> && features.isNotEmpty)) {
        await _storage.saveFloorPlanData(floorId, features);
      } else {
        features = await _storage.getFloorPlanData(floorId);
      }
    } catch (_) {
      allWs = await _storage.getFloorWorkspaces(floorId);
      features = await _storage.getFloorPlanData(floorId);
    }

    final List<Map<String, dynamic>> bookable =
        allWs.where(isBookableWorkspace).toList();

    final Map<String, List<Map<String, dynamic>>> grouped =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> ws in bookable) {
      final String roomName = extractRoomName(ws, trim: false);
      grouped.putIfAbsent(roomName, () => <Map<String, dynamic>>[]).add(ws);
    }

    if (mounted) {
      setState(() {
        _rooms = grouped;
        _floorFeatures = parseFloorFeaturesWithFallback(features, allWs);
        _allWorkspaces = allWs;
        _loadingWorkspaces = false;
      });
    }
  }

  Future<void> _confirm(Map<String, dynamic> ws) async {
    setState(() => _selectedWorkspace = ws);

    if (_selectedFloor == null || _selectedSite == null) {
      return;
    }

    final String siteId = _selectedSite!['id']?.toString() ?? '';
    final String floorId = _selectedFloor!['id']?.toString() ?? '';
    final String wsId = ws['id']?.toString() ?? '';
    final String wsName = ws['name']?.toString() ?? wsId;

    if (widget.pickOnly) {
      if (!mounted) return;
      Navigator.of(context).pop(<String, String>{
        'siteId': siteId,
        'floorId': floorId,
        'workspaceId': wsId,
        'workspaceName': wsName,
      });
      return;
    }

    await _storage.saveSiteId(siteId);
    await _storage.saveFloorId(floorId);
    await _storage.saveMapSelectedFloorId(floorId);
    await _storage.saveWorkspaceId(wsId);
    await _storage.saveWorkspaceName(wsName);

    if (!mounted) return;

    // If launched from HomeScreen (can pop), just return.
    // If launched from LoginScreen (replaced root), push new HomeScreen.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    }
  }

  Widget _buildMapSkeletonContent() {
    return Column(
      children: <Widget>[
        Container(
          height: 40,
          width: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 350,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 40,
                left: 30,
                child: Container(width: 50, height: 20, color: Colors.white),
              ),
              Positioned(
                top: 40,
                left: 90,
                child: Container(width: 50, height: 20, color: Colors.white),
              ),
              Positioned(
                top: 100,
                right: 40,
                child: Container(width: 30, height: 60, color: Colors.white),
              ),
              Positioned(
                top: 180,
                right: 40,
                child: Container(width: 30, height: 60, color: Colors.white),
              ),
              Positioned(
                bottom: 60,
                left: 50,
                child: Container(width: 80, height: 30, color: Colors.white),
              ),
              Positioned(
                bottom: 120,
                left: 150,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                bottom: 180,
                left: 80,
                child: Container(width: 40, height: 20, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapSkeleton() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final Color highlightColor =
        isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: _buildMapSkeletonContent(),
    );
  }

  Widget _buildFullSkeleton() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final Color highlightColor =
        isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 150, height: 20, color: Colors.white),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(left: 13, top: 12, bottom: 12),
            width: 2,
            height: 30,
            color: Colors.white,
          ),
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 100, height: 20, color: Colors.white),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(left: 13, top: 12, bottom: 12),
            width: 2,
            height: 30,
            color: Colors.white,
          ),
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 120, height: 20, color: Colors.white),
            ],
          ),
          const SizedBox(height: 24),
          _buildMapSkeletonContent(),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _storage.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(ignoreUrlToken: true),
        settings: const RouteSettings(name: '/'),
      ),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _showWebPairing() async {
    await showWebPairingDialog(
      context,
      storage: _storage,
      siteId: _selectedSite?['id']?.toString(),
      floorId: _selectedFloor?['id']?.toString(),
      workspaceId: _selectedWorkspace?['id']?.toString(),
      workspaceName: _selectedWorkspace?['name']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> filteredSites =
        _sites.where((Map<String, dynamic> s) {
      final String name =
          s['name']?.toString() ?? s['id']?.toString() ?? '';
      return name.toLowerCase().contains(_siteSearch.toLowerCase());
    }).toList();

    final List<Map<String, dynamic>> filteredFloors =
        _floors.where((Map<String, dynamic> f) {
      final String name =
          f['name']?.toString() ?? f['id']?.toString() ?? '';
      return name.toLowerCase().contains(_floorSearch.toLowerCase());
    }).toList();

    final List<String> filteredRooms = _rooms.keys.where((String r) {
      return r.toLowerCase().contains(_roomSearch.toLowerCase());
    }).toList();

    final bool isMapActive = _currentStep >= 2 && _showMap;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titleOverride ?? 'Configuration'),
        actions: widget.pickOnly
            ? null
            : <Widget>[
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Lier un appareil Web',
                  onPressed: _showWebPairing,
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Se déconnecter',
                  onPressed: _logout,
                ),
              ],
      ),
      body: _loadingSites
          ? _buildFullSkeleton()
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : Stepper(
                  physics: isMapActive
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  key: ValueKey<String>('stepper_${_currentStep}_$isMapActive'),
                  currentStep: _showMap && _currentStep > 2 ? 2 : _currentStep,
                  onStepTapped: (int step) {
                    if (step == 0) setState(() => _currentStep = 0);
                    if (step == 1 && _selectedSite != null) {
                      setState(() => _currentStep = 1);
                    }
                    if (step == 2 && _selectedFloor != null) {
                      setState(() => _currentStep = 2);
                    }
                    if (step == 3 && _selectedRoomPrefix != null) {
                      setState(() => _currentStep = 3);
                    }
                  },
                  controlsBuilder:
                      (BuildContext context, ControlsDetails details) {
                    return const SizedBox.shrink(); // Hide default buttons completely
                  },
                  steps: <Step>[
                    Step(
                      title: const Text('Bâtiment'),
                      subtitle: _selectedSite != null && _currentStep != 0
                          ? Text(_selectedSite!['name']?.toString() ?? '')
                          : null,
                      state: _selectedSite != null
                          ? StepState.complete
                          : StepState.editing,
                      isActive: _currentStep >= 0,
                      content: Column(
                        children: <Widget>[
                          if (_sites.length > 5)
                            _buildSearchBar(
                              'Rechercher un bâtiment...',
                              (String v) => setState(() => _siteSearch = v),
                            ),
                          ...filteredSites.map(
                            (Map<String, dynamic> site) => _SelectTile(
                              label: site['name']?.toString() ??
                                  site['id']?.toString() ??
                                  '',
                              selected: _selectedSite?['id']?.toString() ==
                                  site['id']?.toString(),
                              onTap: () => _onSiteSelected(site),
                            ),
                          ),
                          if (filteredSites.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Aucun résultat'),
                            ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Étage'),
                      subtitle: _selectedFloor != null && _currentStep != 1
                          ? Text(_selectedFloor!['name']?.toString() ?? '')
                          : null,
                      state: _selectedFloor != null
                          ? StepState.complete
                          : StepState.editing,
                      isActive: _currentStep >= 1,
                      content: _loadingFloors
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            )
                          : Column(
                              children: <Widget>[
                                if (_floors.length > 5)
                                  _buildSearchBar(
                                    'Rechercher un étage...',
                                    (String v) =>
                                        setState(() => _floorSearch = v),
                                  ),
                                ...filteredFloors.map(
                                  (Map<String, dynamic> floor) => _SelectTile(
                                    label: floor['name']?.toString() ??
                                        floor['id']?.toString() ??
                                        '',
                                    selected:
                                        _selectedFloor?['id']?.toString() ==
                                            floor['id']?.toString(),
                                    onTap: () => _onFloorSelected(floor),
                                  ),
                                ),
                                if (filteredFloors.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('Aucun résultat'),
                                  ),
                              ],
                            ),
                    ),
                    Step(
                      title:
                          Text(_showMap ? 'Place (Plan 2D)' : 'Zone / Salle'),
                      subtitle: _selectedWorkspace != null && _currentStep != 2
                          ? Text(
                              _showMap
                                  ? (_selectedWorkspace!['name']?.toString() ??
                                      '')
                                  : (_selectedRoomPrefix ?? ''),
                            )
                          : null,
                      state: (_showMap
                              ? _selectedWorkspace != null
                              : _selectedRoomPrefix != null)
                          ? StepState.complete
                          : StepState.editing,
                      isActive: _currentStep >= 2,
                      content: _loadingWorkspaces
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: _buildMapSkeleton(),
                            )
                          : Column(
                              children: <Widget>[
                                if (_floorFeatures.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SegmentedButton<bool>(
                                      segments: const <ButtonSegment<bool>>[
                                        ButtonSegment<bool>(
                                          value: true,
                                          label: Text('Plan 2D'),
                                          icon: Icon(Icons.map),
                                        ),
                                        ButtonSegment<bool>(
                                          value: false,
                                          label: Text('Liste'),
                                          icon: Icon(Icons.list),
                                        ),
                                      ],
                                      selected: <bool>{_showMap},
                                      onSelectionChanged: (Set<bool> val) =>
                                          setState(() {
                                        _showMap = val.first;
                                        if (_showMap && _currentStep > 2) {
                                          _currentStep =
                                              2; // Prevent Stepper index out of bounds
                                        }
                                      }),
                                    ),
                                  ),
                                if (_showMap)
                                  LayoutBuilder(
                                    builder: (
                                      BuildContext context,
                                      BoxConstraints constraints,
                                    ) {
                                      // Use 55% of screen height, min 300, max 600
                                      final double screenH =
                                          MediaQuery.of(context).size.height;
                                      final double mapH =
                                          (screenH * 0.55).clamp(300.0, 600.0);
                                      return Transform.translate(
                                        offset: const Offset(-24, 0),
                                        child: SizedBox(
                                          height: mapH,
                                          child: WorkspaceMapViewer(
                                            features: _floorFeatures,
                                            workspaces: _rooms.values
                                                .expand(
                                                  (List<Map<String, dynamic>>
                                                          x) =>
                                                      x,
                                                )
                                                .toList(),
                                            allWorkspaces: _allWorkspaces,
                                            selectedWorkspaceId:
                                                _selectedWorkspace?['id']
                                                    ?.toString(),
                                            containerHeight: mapH,
                                            onSelected:
                                                (Map<String, dynamic> ws) {
                                              final String roomName =
                                                  extractRoomName(
                                                ws,
                                                trim: false,
                                              );
                                              setState(() {
                                                _selectedRoomPrefix = roomName;
                                              });
                                              _confirm(ws);
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                else ...<Widget>[
                                  if (_rooms.length > 5)
                                    _buildSearchBar(
                                      'Rechercher une salle...',
                                      (String v) =>
                                          setState(() => _roomSearch = v),
                                    ),
                                  ...filteredRooms.map((String roomName) {
                                    final int count = _rooms[roomName]!.length;
                                    return _SelectTile(
                                      label:
                                          "$roomName ($count place${count > 1 ? 's' : ''})",
                                      selected: _selectedRoomPrefix == roomName,
                                      onTap: () {
                                        setState(() {
                                          _selectedRoomPrefix = roomName;
                                          _selectedWorkspace = null;
                                          _currentStep = 3;
                                        });
                                      },
                                    );
                                  }),
                                  if (filteredRooms.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('Aucun résultat'),
                                    ),
                                ],
                              ],
                            ),
                    ),
                    if (!_showMap)
                      Step(
                        title: const Text('Place exacte'),
                        subtitle: _selectedWorkspace != null &&
                                _currentStep != 3
                            ? Text(
                                _selectedWorkspace!['name']?.toString() ?? '',
                              )
                            : null,
                        state: _selectedWorkspace != null
                            ? StepState.complete
                            : StepState.editing,
                        isActive: _currentStep >= 3,
                        content: Column(
                          children: <Widget>[
                            if (_floorFeatures.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: SegmentedButton<bool>(
                                  segments: const <ButtonSegment<bool>>[
                                    ButtonSegment<bool>(
                                      value: true,
                                      label: Text('Plan 2D'),
                                      icon: Icon(Icons.map),
                                    ),
                                    ButtonSegment<bool>(
                                      value: false,
                                      label: Text('Liste'),
                                      icon: Icon(Icons.list),
                                    ),
                                  ],
                                  selected: <bool>{_showMap},
                                  onSelectionChanged: (Set<bool> val) =>
                                      setState(() {
                                    _showMap = val.first;
                                    if (_showMap && _currentStep > 2) {
                                      _currentStep =
                                          2; // Prevent Stepper index out of bounds
                                    }
                                  }),
                                ),
                              ),
                            ...(_selectedRoomPrefix != null
                                    ? (_rooms[_selectedRoomPrefix!] ??
                                        <Map<String, dynamic>>[])
                                    : <Map<String, dynamic>>[])
                                .map((Map<String, dynamic> ws) {
                              final String name = ws['name']?.toString() ??
                                  ws['id']?.toString() ??
                                  '';
                              final int lastDash = name.lastIndexOf('-');
                              String shortName = name;
                              if (lastDash > 0 && lastDash < name.length - 1) {
                                final String suffix =
                                    name.substring(lastDash + 1);
                                if (suffix.length <= 4) {
                                  shortName = 'Place $suffix';
                                }
                              }
                              return _SelectTile(
                                label: shortName,
                                selected:
                                    _selectedWorkspace?['id']?.toString() ==
                                        ws['id']?.toString(),
                                onTap: () => _confirm(ws),
                              );
                            }),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildSearchBar(String hint, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: selected ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      color: selected ? colorScheme.primaryContainer : null,
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colorScheme.onPrimaryContainer : null,
          ),
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}
