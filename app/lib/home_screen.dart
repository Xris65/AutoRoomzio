import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  final _tokenController = TextEditingController();
  final _floorIdController = TextEditingController();
  final _workspaceIdController = TextEditingController();
  
  List<int> _selectedDays = [];
  bool _isLoading = true;

  final Map<int, String> _weekDays = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final token = await _storage.getRefreshToken();
    final floorId = await _storage.getFloorId();
    final workspaceId = await _storage.getWorkspaceId();
    final days = await _storage.getDays();

    if (mounted) {
      setState(() {
        _tokenController.text = token ?? '';
        _floorIdController.text = floorId ?? '';
        _workspaceIdController.text = workspaceId ?? '';
        _selectedDays = days;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveData() async {
    await _storage.saveRefreshToken(_tokenController.text);
    await _storage.saveFloorId(_floorIdController.text);
    await _storage.saveWorkspaceId(_workspaceIdController.text);
    await _storage.saveDays(_selectedDays);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    }
    
    // Register the background task after saving
    Workmanager().registerPeriodicTask(
      "1",
      "autoReservationTask",
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Roomz'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Authentication', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Refresh Token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            
            const Text('Workspace Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _floorIdController,
              decoration: const InputDecoration(
                labelText: 'Floor ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _workspaceIdController,
              decoration: const InputDecoration(
                labelText: 'Workspace ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            const Text('Days to Book', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._weekDays.entries.map((entry) {
              return CheckboxListTile(
                title: Text(entry.value),
                value: _selectedDays.contains(entry.key),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedDays.add(entry.key);
                    } else {
                      _selectedDays.remove(entry.key);
                    }
                  });
                },
              );
            }),
            
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveData,
                child: const Text('Save & Start Automation'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
