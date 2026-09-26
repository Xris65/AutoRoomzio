import 'package:flutter/material.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'home_screen.dart';

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
  List<Map<String, dynamic>> _workspaces = [];

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
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() => _loadingSites = true);
    final sites = await _api.getSites(widget.accessToken);
    if (mounted) {
      setState(() {
        _sites = sites;
        _loadingSites = false;
        if (sites.isEmpty) {
          _errorMessage = 'Aucun bâtiment trouvé. Vérifiez votre compte MyRoomz.';
        }
      });
    }
  }

  int _currentStep = 0;

  Future<void> _onSiteSelected(Map<String, dynamic> site) async {
    setState(() {
      _selectedSite = site;
      _selectedFloor = null;
      _selectedWorkspace = null;
      _floors = [];
      _workspaces = [];
      _loadingFloors = true;
      _currentStep = 1; // Move to floor step
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
      _selectedWorkspace = null;
      _workspaces = [];
      _loadingWorkspaces = true;
      _currentStep = 2; // Move to workspace step
    });
    final workspaces = await _api.getWorkspaces(widget.accessToken, floor['id'].toString());
    if (mounted) {
      setState(() {
        _workspaces = workspaces;
        _loadingWorkspaces = false;
      });
    }
  }

  Future<void> _confirm() async {
    if (_selectedWorkspace == null || _selectedFloor == null || _selectedSite == null) {
      return;
    }
    await _storage.saveSiteId(_selectedSite!['id'].toString());
    await _storage.saveFloorId(_selectedFloor!['id'].toString());
    await _storage.saveWorkspaceId(_selectedWorkspace!['id'].toString());
    await _storage.saveWorkspaceName(
      _selectedWorkspace!['name']?.toString() ?? _selectedWorkspace!['id'].toString(),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  currentStep: _currentStep,
                  onStepTapped: (step) {
                    // Only allow tapping previous completed steps
                    if (step == 0) setState(() => _currentStep = 0);
                    if (step == 1 && _selectedSite != null) setState(() => _currentStep = 1);
                    if (step == 2 && _selectedFloor != null) setState(() => _currentStep = 2);
                  },
                  controlsBuilder: (context, details) {
                    // Hide default Continue/Cancel buttons, we use list selection
                    if (_currentStep == 2 && _selectedWorkspace != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: ElevatedButton(
                          onPressed: _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: const Text('Confirmer ce bureau', style: TextStyle(fontSize: 16)),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
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
                        children: _sites.map((site) => _SelectTile(
                          label: site['name']?.toString() ?? site['id'].toString(),
                          selected: _selectedSite?['id'] == site['id'],
                          onTap: () => _onSiteSelected(site),
                        )).toList(),
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
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            )
                          : Column(
                              children: _floors.map((floor) => _SelectTile(
                                label: floor['name']?.toString() ?? floor['id'].toString(),
                                selected: _selectedFloor?['id'] == floor['id'],
                                onTap: () => _onFloorSelected(floor),
                              )).toList(),
                            ),
                    ),
                    Step(
                      title: const Text('Bureau'),
                      subtitle: _selectedWorkspace != null && _currentStep != 2
                          ? Text(_selectedWorkspace!['name']?.toString() ?? '')
                          : null,
                      state: _selectedWorkspace != null ? StepState.complete : StepState.editing,
                      isActive: _currentStep >= 2,
                      content: _loadingWorkspaces
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            )
                          : Column(
                              children: _workspaces.map((ws) => _SelectTile(
                                label: ws['name']?.toString() ?? ws['id'].toString(),
                                selected: _selectedWorkspace?['id'] == ws['id'],
                                onTap: () => setState(() => _selectedWorkspace = ws),
                              )).toList(),
                            ),
                    ),
                  ],
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
    return Card(
      color: selected ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: selected ? const BorderSide(color: Colors.blue, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        title: Text(label),
        trailing: selected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
        onTap: onTap,
      ),
    );
  }
}
