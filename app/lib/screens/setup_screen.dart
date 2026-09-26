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

  Future<void> _onSiteSelected(Map<String, dynamic> site) async {
    setState(() {
      _selectedSite = site;
      _selectedFloor = null;
      _selectedWorkspace = null;
      _floors = [];
      _workspaces = [];
      _loadingFloors = true;
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
      appBar: AppBar(title: const Text('Choisir votre bureau')),
      body: _loadingSites
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Bâtiment ──────────────────────────────────────
                      _sectionTitle('🏢 Bâtiment'),
                      ..._sites.map(
                        (site) => _SelectTile(
                          label: site['name']?.toString() ?? site['id'].toString(),
                          selected: _selectedSite?['id'] == site['id'],
                          onTap: () => _onSiteSelected(site),
                        ),
                      ),

                      // ── Étage ─────────────────────────────────────────
                      if (_selectedSite != null) ...[
                        const SizedBox(height: 24),
                        _sectionTitle('🏗️ Étage'),
                        if (_loadingFloors)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          ..._floors.map(
                            (floor) => _SelectTile(
                              label: floor['name']?.toString() ?? floor['id'].toString(),
                              selected: _selectedFloor?['id'] == floor['id'],
                              onTap: () => _onFloorSelected(floor),
                            ),
                          ),
                      ],

                      // ── Bureau ────────────────────────────────────────
                      if (_selectedFloor != null) ...[
                        const SizedBox(height: 24),
                        _sectionTitle('🪑 Bureau'),
                        if (_loadingWorkspaces)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          ..._workspaces.map(
                            (ws) => _SelectTile(
                              label: ws['name']?.toString() ?? ws['id'].toString(),
                              selected: _selectedWorkspace?['id'] == ws['id'],
                              onTap: () => setState(() => _selectedWorkspace = ws),
                            ),
                          ),
                      ],

                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _selectedWorkspace != null ? _confirm : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Confirmer', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
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
