import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
import '../main.dart'; // for themeNotifier

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  final _api = RoomzApiService();

  List<int> _selectedDays = [];
  String? _workspaceName;
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<int, String> _weekDays = {
    1: 'Lundi',
    2: 'Mardi',
    3: 'Mercredi',
    4: 'Jeudi',
    5: 'Vendredi',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final days = await _storage.getDays();
    final name = await _storage.getWorkspaceName();
    if (mounted) {
      setState(() {
        _selectedDays = days;
        _workspaceName = name;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAndActivate() async {
    setState(() => _isSaving = true);
    await _storage.saveDays(_selectedDays);

    if (Platform.isAndroid) {
      Workmanager().registerPeriodicTask(
        "1",
        "autoReservationTask",
        frequency: const Duration(hours: 24),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Automatisation activée !'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _changeWorkspace() async {
    final token = await _api.refreshMyToken();
    if (!mounted) return;
    if (token == null) {
      _logout();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SetupScreen(accessToken: token)),
    ).then((_) => _loadData());
  }

  Future<void> _logout() async {
    await _storage.clearAll();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paramètres',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, _) {
                    final isDark = currentMode == ThemeMode.dark || 
                        (currentMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);
                    return SwitchListTile(
                      title: const Text('Mode sombre'),
                      secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
                      value: currentMode == ThemeMode.dark,
                      onChanged: (val) {
                        themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                        _storage.saveDarkMode(val);
                      },
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Version'),
                  trailing: const Text('1.0.0'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoRoomzio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: _showSettings,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Current workspace card ───────────────────────────────────
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _changeWorkspace,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.desk, color: Colors.blue, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Bureau sélectionné', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(
                              _workspaceName ?? 'Aucun bureau configuré',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _workspaceName != null ? Theme.of(context).colorScheme.onSurface : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Day selection ────────────────────────────────────────────
            const Text(
              '📅 Jours de présence au bureau',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._weekDays.entries.map(
              (entry) => CheckboxListTile(
                title: Text(entry.value),
                value: _selectedDays.contains(entry.key),
                activeColor: Colors.blue,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedDays.add(entry.key);
                      _selectedDays.sort();
                    } else {
                      _selectedDays.remove(entry.key);
                    }
                  });
                },
              ),
            ),

            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_isSaving || _workspaceName == null || _selectedDays.isEmpty)
                    ? null
                    : _saveAndActivate,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Activer l\'automatisation', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            if (_workspaceName == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Configurez d\'abord votre bureau via le bouton "Changer".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
