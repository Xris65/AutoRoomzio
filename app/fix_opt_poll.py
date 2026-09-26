import re

with open('lib/screens/optimization_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove manual dialog from _requestBattery
old_req_batt = """  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _checkPermissions();
    if (_isBatteryOptimized) {
      if (!mounted) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Vérification manuelle"),
          content: const Text("Sur certains téléphones (Xiaomi, Huawei, etc.), la détection automatique échoue. Avez-vous bien sélectionné 'Pas de restriction' ou désactivé l'optimisation pour AutoRoomzio ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui, c'est fait")),
          ],
        )
      );
      if (result == true) {
        final storage = StorageService();
        await storage.saveBatteryVerified(true);
        setState(() => _isBatteryOptimized = false);
      }
    }
  }"""

new_req_batt = """  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    _checkPermissions();
  }"""

content = content.replace(old_req_batt, new_req_batt)

# 2. Add Timer to state
timer_import = "import 'dart:async';\nimport 'dart:io';"
content = content.replace("import 'dart:io';", timer_import)

old_state_start = """class _OptimizationScreenState extends State<OptimizationScreen> with WidgetsBindingObserver {

  bool _isBatteryOptimized = true;"""

new_state_start = """class _OptimizationScreenState extends State<OptimizationScreen> with WidgetsBindingObserver {

  bool _isBatteryOptimized = true;
  Timer? _pollingTimer;"""

content = content.replace(old_state_start, new_state_start)

old_init = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }"""

new_init = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    // Poll permissions in case system dialogs hide the lifecycle events
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _checkPermissions();
    });
  }"""

content = content.replace(old_init, new_init)

old_dispose = """  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }"""

new_dispose = """  @override
  void dispose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }"""

content = content.replace(old_dispose, new_dispose)

with open('lib/screens/optimization_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)