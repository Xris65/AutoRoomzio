import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('package:permission_handler/permission_handler.dart')) {
    content = content.replaceFirst('import ''package:package_info_plus/package_info_plus.dart'';', 'import ''package:package_info_plus/package_info_plus.dart'';\nimport ''package:permission_handler/permission_handler.dart'';');
  }

  content = content.replaceFirst(
    '''      // Load from cache first, then fetch background
      _syncCalendar(background: true);
    }
  }

  Future<void> _logout() async {''',
    '''      // Load from cache first, then fetch background
      _syncCalendar(background: true);

      // Check optimization screen
      if (Platform.isAndroid) {
        final hasSeen = await _storage.getHasSeenOptimization();
        if (!hasSeen && mounted) {
          await _storage.saveHasSeenOptimization(true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OptimizationScreen()),
              ).then((_) => _checkPermissionsStatus());
            }
          });
        }
      }
      _checkPermissionsStatus();
    }
  }
  
  int _permissionStatus = 0; // 0 = Unknown, 1 = Ok (Green), 2 = Warning (Yellow), 3 = Error (Red)

  Future<void> _checkPermissionsStatus() async {
    if (!Platform.isAndroid) return;
    final batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;
    final autostart = await _storage.getAutostartVerified();

    int okCount = 0;
    if (batteryOpt) okCount++;
    if (notif) okCount++;
    if (autostart) okCount++;

    if (mounted) {
      setState(() {
        if (okCount == 3) {
          _permissionStatus = 1;
        } else if (okCount > 0) {
          _permissionStatus = 2;
        } else {
          _permissionStatus = 3;
        }
      });
    }
  }

  Future<void> _logout() async {'''
  );
  
  // Also we need to re-check when the app is resumed.
  content = content.replaceFirst(
    '''  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _syncCalendar(background: true);
    }
  }''',
    '''  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _syncCalendar(background: true);
      _checkPermissionsStatus();
    }
  }'''
  );

  final String fromAppBar = "        appBar: AppBar(\n          title: const Text('AutoRoomzio'),\n          actions: [\n            IconButton(";
  
  final String toAppBar = "        appBar: AppBar(\n          title: const Text('AutoRoomzio'),\n          actions: [\n            if (Platform.isAndroid && _permissionStatus != 0)\n              IconButton(\n                icon: Icon(\n                  Icons.shield_rounded, \n                  color: _permissionStatus == 1 ? Colors.green : (_permissionStatus == 2 ? Colors.orange : Colors.red.shade300)\n                ),\n                tooltip: 'Statut des permissions',\n                onPressed: () {\n                  Navigator.of(context).push(\n                    MaterialPageRoute(builder: (_) => const OptimizationScreen()),\n                  ).then((_) => _checkPermissionsStatus());\n                },\n              ),\n            IconButton(";

  content = content.replaceFirst(fromAppBar, toAppBar);

  file.writeAsStringSync(content);
}
