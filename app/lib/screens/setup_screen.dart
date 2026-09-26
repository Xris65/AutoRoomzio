import 'package:flutter/material.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'home_screen.dart';
import '../widgets/workspace_map_viewer.dart';

class SetupScreen extends StatefulWidget {
  final String accessToken;
  const SetupScreen({super.key, required this.accessToken});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _api = RoomzApiService();
  final _storage = StorageService();

  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _floorFeatures = [];
  List<Map<String, dynamic>> _allWorkspaces = [];
  bool _showMap = true;

  Map<String, dynamic>? _selectedSite;
  Map<String, dynamic>? _selectedFloor;
  Map<String, dynamic>? _selectedWorkspace;

  bool _loadingSites = true;
  bool _loadingFloors = false;
  bool _loadingWorkspaces = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loadingSites = true);
    
    try {
      final sites = await _api.getSites(widget.accessToken);
      
      final savedSiteId = await _storage.getSiteId();
      final savedFloorId = await _storage.getFloorId();
      final savedWorkspaceId = await _storage.getWorkspaceId();

      Map<String, dynamic>? initialSite;
      Map<String, dynamic>? initialFloor;
      Map<String, dynamic>? initialWorkspace;
      String? initialRoomPrefix;
      List<Map<String, dynamic>> initialFloors = [];
      Map<String, List<Map<String, dynamic>>> initialRooms = {};

      if (savedSiteId != null) {
        try {
          initialSite = sites.firstWhere((s) => s['id'].toString() == savedSiteId);
          initialFloors = await _api.getFloors(widget.accessToken, savedSiteId);
          
          if (savedFloorId != null) {
            initialFloor = initialFloors.firstWhere((f) => f['id'].toString() == savedFloorId);
            final allWs = await _api.getAllWorkspaces(widget.accessToken, savedSiteId, savedFloorId);
            final workspaces = allWs.where((ws) {
              if (ws['isReservable'] == false) return false;
              if (ws['bookable'] == false) return false;
              if (ws['isBookable'] == false) return false;
              if (ws['type'] == 'Room') return false;
              if (ws['type'] == 1) return false;
              return true;
            }).toList();
            final initialFeatures = await _api.getFloorPlanData(widget.accessToken, savedSiteId, savedFloorId);
            
            if (mounted) {
               _floorFeatures = initialFeatures;
               _allWorkspaces = allWs;
            }
            
            for (final ws in workspaces) {
              final String name = ws['name']?.toString() ?? ws['id'].toString();
              final lastDash = name.lastIndexOf('-');
              String roomName = name;
              if (lastDash > 0 && lastDash < name.length - 1) {
                final suffix = name.substring(lastDash + 1);
                if (suffix.length <= 4 && !suffix.contains(' ')) {
                  roomName = name.substring(0, lastDash);
                }
              }
              initialRooms.putIfAbsent(roomName, () => []).add(ws);
              
              if (ws['id'].toString() == savedWorkspaceId) {
                initialWorkspace = ws;
                initialRoomPrefix = roomName;
              }
            }
          }
        } catch (e) {
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
            _errorMessage = 'Aucun bâtiment trouvé. Vérifiez votre compte MyRoomz.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Erreur de chargement: $e";
          _loadingSites = false;
        });
      }
    }
  }

  int _currentStep = 0;
  String? _selectedRoomPrefix;
  Map<String, List<Map<String, dynamic>>> _rooms = {};

  // Search queries
  String _siteSearch = '';
  String _floorSearch = '';
  String _roomSearch = '';

  Future<void> _onSiteSelected(Map<String, dynamic> site) async {
    setState(() {
      _selectedSite = site;
      _selectedFloor = null;
      _selectedRoomPrefix = null;
      _selectedWorkspace = null;
      _floors = [];
      _rooms = {};
      _floorSearch = ''; // Reset next step search
      _loadingFloors = true;
      _currentStep = 1;
    });
    final floors = await _api.getFloors(widget.accessToken, site['id'].toString());
    if (mounted) {
      setState(() {
        _floors = floors;
        _loadingFloors = false;
      });
    }
  }

  Future<void> _onFloorSelected(Map<String, dynamic> floor) async {
    setState(() {
      _selectedFloor = floor;
      _selectedRoomPrefix = null;
      _selectedWorkspace = null;
      _rooms = {};
      _roomSearch = ''; // Reset next step search
      _loadingWorkspaces = true;
      _currentStep = 2;
    });
    
    final siteId = _selectedSite!['id'].toString();
    final floorId = floor['id'].toString();
    
    // Un seul appel API, on filtre localement
    final allWs = await _api.getAllWorkspaces(widget.accessToken, siteId, floorId);
    final features = await _api.getFloorPlanData(widget.accessToken, siteId, floorId);

    final bookable = allWs.where((ws) {
      if (ws['isReservable'] == false) return false;
      if (ws['bookable'] == false) return false;
      if (ws['isBookable'] == false) return false;
      if (ws['type'] == 'Room') return false;
      if (ws['type'] == 1) return false;
      return true;
    }).toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final ws in bookable) {
      final String name = ws['name']?.toString() ?? ws['id'].toString();
      final lastDash = name.lastIndexOf('-');
      String roomName = name;
      if (lastDash > 0 && lastDash < name.length - 1) {
        final suffix = name.substring(lastDash + 1);
        if (suffix.length <= 4 && !suffix.contains(' ')) {
          roomName = name.substring(0, lastDash);
        }
      }
      grouped.putIfAbsent(roomName, () => []).add(ws);
    }

    if (mounted) {
      setState(() {
        _rooms = grouped;
        _floorFeatures = features;
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
    await _storage.saveSiteId(_selectedSite!['id'].toString());
    await _storage.saveFloorId(_selectedFloor!['id'].toString());
    await _storage.saveWorkspaceId(ws['id'].toString());
    await _storage.saveWorkspaceName(
      ws['name']?.toString() ?? ws['id'].toString(),
    );

    if (!mounted) return;
    
    // If launched from HomeScreen (can pop), just return. 
    // If launched from LoginScreen (replaced root), push new HomeScreen.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredSites = _sites.where((s) {
      final name = s['name']?.toString() ?? s['id'].toString();
      return name.toLowerCase().contains(_siteSearch.toLowerCase());
    }).toList();

    final filteredFloors = _floors.where((f) {
      final name = f['name']?.toString() ?? f['id'].toString();
      return name.toLowerCase().contains(_floorSearch.toLowerCase());
    }).toList();

    final filteredRooms = _rooms.keys.where((r) {
      return r.toLowerCase().contains(_roomSearch.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: _loadingSites
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              : Stepper(
                  key: ValueKey(_showMap),
                  currentStep: _showMap && _currentStep > 2 ? 2 : _currentStep,
                  onStepTapped: (step) {
                    if (step == 0) setState(() => _currentStep = 0);
                    if (step == 1 && _selectedSite != null) setState(() => _currentStep = 1);
                    if (step == 2 && _selectedFloor != null) setState(() => _currentStep = 2);
                    if (step == 3 && _selectedRoomPrefix != null) setState(() => _currentStep = 3);
                  },
                  controlsBuilder: (context, details) {
                    return const SizedBox.shrink(); // Hide default buttons completely
                  },
                  steps: [
                    Step(
                      title: const Text('Bâtiment'),
                      subtitle: _selectedSite != null && _currentStep != 0
                          ? Text(_selectedSite!['name']?.toString() ?? '')
                          : null,
                      state: _selectedSite != null ? StepState.complete : StepState.editing,
                      isActive: _currentStep >= 0,
                      content: Column(
                        children: [
                          if (_sites.length > 5)
                            _buildSearchBar('Rechercher un bâtiment...', (v) => setState(() => _siteSearch = v)),
                          ...filteredSites.map((site) => _SelectTile(
                            label: site['name']?.toString() ?? site['id'].toString(),
                            selected: _selectedSite?['id'] == site['id'],
                            onTap: () => _onSiteSelected(site),
                          )),
                          if (filteredSites.isEmpty)
                            const Padding(padding: EdgeInsets.all(16), child: Text('Aucun résultat')),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Étage'),
                      subtitle: _selectedFloor != null && _currentStep != 1
                          ? Text(_selectedFloor!['name']?.toString() ?? '')
                          : null,
                      state: _selectedFloor != null ? StepState.complete : StepState.editing,
                      isActive: _currentStep >= 1,
                      content: _loadingFloors
                          ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                          : Column(
                              children: [
                                if (_floors.length > 5)
                                  _buildSearchBar('Rechercher un étage...', (v) => setState(() => _floorSearch = v)),
                                ...filteredFloors.map((floor) => _SelectTile(
                                  label: floor['name']?.toString() ?? floor['id'].toString(),
                                  selected: _selectedFloor?['id'] == floor['id'],
                                  onTap: () => _onFloorSelected(floor),
                                )),
                                if (filteredFloors.isEmpty)
                                  const Padding(padding: EdgeInsets.all(16), child: Text('Aucun résultat')),
                              ],
                            ),
                    ),
                    Step(
                      title: Text(_showMap ? 'Place (Plan 2D)' : 'Zone / Salle'),
                      subtitle: _selectedWorkspace != null && _currentStep != 2
                          ? Text(_showMap ? (_selectedWorkspace!['name']?.toString() ?? '') : (_selectedRoomPrefix ?? ''))
                          : null,
                      state: (_showMap ? _selectedWorkspace != null : _selectedRoomPrefix != null) ? StepState.complete : StepState.editing,
                      isActive: _currentStep >= 2,
                      content: _loadingWorkspaces
                          ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                          : Column(
                              children: [
                                if (_floorFeatures.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment(value: true, label: Text('Plan 2D'), icon: Icon(Icons.map)),
                                        ButtonSegment(value: false, label: Text('Liste'), icon: Icon(Icons.list)),
                                      ],
                                      selected: {_showMap},
                                      onSelectionChanged: (val) => setState(() {
                                        _showMap = val.first;
                                        if (_showMap && _currentStep > 2) {
                                          _currentStep = 2; // Prevent Stepper index out of bounds
                                        }
                                      }),
                                    ),
                                  ),
                                if (_showMap)
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      // Use 55% of screen height, min 300, max 600
                                      final screenH = MediaQuery.of(context).size.height;
                                      final mapH = (screenH * 0.55).clamp(300.0, 600.0);
                                      return SizedBox(
                                        height: mapH,
                                        child: WorkspaceMapViewer(
                                          features: _floorFeatures,
                                          workspaces: _rooms.values.expand((x) => x).toList(),
                                          allWorkspaces: _allWorkspaces,
                                          selectedWorkspaceId: _selectedWorkspace?['id'],
                                          containerHeight: mapH,
                                          onSelected: (ws) {
                                            // Auto select room prefix and workspace
                                            final String name = ws['name']?.toString() ?? ws['id'].toString();
                                            final lastDash = name.lastIndexOf('-');
                                            String roomName = name;
                                            if (lastDash > 0 && lastDash < name.length - 1) {
                                              final suffix = name.substring(lastDash + 1);
                                              if (suffix.length <= 4 && !suffix.contains(' ')) {
                                                roomName = name.substring(0, lastDash);
                                              }
                                            }
                                            setState(() {
                                              _selectedRoomPrefix = roomName;
                                            });
                                            _confirm(ws);
                                          },
                                        ),
                                      );
                                    },
                                  )
                                else ...[
                                  if (_rooms.length > 5)
                                    _buildSearchBar('Rechercher une salle...', (v) => setState(() => _roomSearch = v)),
                                  ...filteredRooms.map((roomName) {
                                    final count = _rooms[roomName]!.length;
                                    return _SelectTile(
                                      label: "$roomName ($count place${count > 1 ? 's' : ''})",
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
                                    const Padding(padding: EdgeInsets.all(16), child: Text('Aucun résultat')),
                                ],
                              ],
                            ),
                    ),
                    if (!_showMap)
                      Step(
                        title: const Text('Place exacte'),
                        subtitle: _selectedWorkspace != null && _currentStep != 3
                            ? Text(_selectedWorkspace!['name']?.toString() ?? '')
                            : null,
                        state: _selectedWorkspace != null ? StepState.complete : StepState.editing,
                        isActive: _currentStep >= 3,
                        content: Column(
                          children: [
                            if (_floorFeatures.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(value: true, label: Text('Plan 2D'), icon: Icon(Icons.map)),
                                    ButtonSegment(value: false, label: Text('Liste'), icon: Icon(Icons.list)),
                                  ],
                                  selected: {_showMap},
                                  onSelectionChanged: (val) => setState(() {
                                    _showMap = val.first;
                                    if (_showMap && _currentStep > 2) {
                                      _currentStep = 2; // Prevent Stepper index out of bounds
                                    }
                                  }),
                                ),
                              ),
                            ...(_selectedRoomPrefix != null ? _rooms[_selectedRoomPrefix!] ?? [] : []).map((ws) {
                                final name = ws['name']?.toString() ?? ws['id'].toString();
                                final lastDash = name.lastIndexOf('-');
                                String shortName = name;
                                if (lastDash > 0 && lastDash < name.length - 1) {
                                  final suffix = name.substring(lastDash + 1);
                                  if (suffix.length <= 4) shortName = "Place $suffix";
                                }
                                return _SelectTile(
                                  label: shortName,
                                  selected: _selectedWorkspace?['id'] == ws['id'],
                                  onTap: () => _confirm(ws),
                                );
                              }).toList(),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildSearchBar(String hint, Function(String) onChanged) {
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

  const _SelectTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
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
        trailing: selected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
        onTap: onTap,
      ),
    );
  }
}


