import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_main = """void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    try {
      await NotificationService().init();
    } catch (e, stack) {
      debugPrint('Notification init failed: $e\\n$stack');
    }

    if (Platform.isAndroid) {
      try {
        Workmanager().initialize(callbackDispatcher);
        final storage = StorageService();
        final automationEnabled = await storage.getAutomationEnabled();
        if (automationEnabled) {
          final autoTimeMap = await storage.getAutomationTime();
          final now = DateTime.now();
          var targetDate = DateTime(now.year, now.month, now.day,
              autoTimeMap['hour']!, autoTimeMap['minute']!);
          if (targetDate.isBefore(now)) {
            targetDate = targetDate.add(const Duration(days: 1));
          }
          final delay = targetDate.difference(now);
          Workmanager().registerPeriodicTask(
            "1",
            "autoReservationTask",
            frequency: const Duration(hours: 24),
            initialDelay: delay,
            existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
            constraints: Constraints(networkType: NetworkType.connected),
          );
        }
      } catch (e, stack) {
        debugPrint('Workmanager init failed: $e\\n$stack');
      }
    }

    final modeIndex = await StorageService().getThemeModeIndex();
    themeNotifier.value = modeIndex == 1 ? ThemeMode.light : (modeIndex == 2 ? ThemeMode.dark : ThemeMode.system);
    
    final colorIndex = await StorageService().getThemeColorIndex();
    themeColorNotifier.value = colorIndex;

    final fontIndex = await StorageService().getFontFamilyIndex();
    fontNotifier.value = fontIndex;

    runApp(const MyApp());
  } catch (e, stack) {
    runApp(MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text('CRITICAL STARTUP ERROR:\\n$e\\n\\n$stack', style: const TextStyle(color: Colors.red)),
          ),
        ),
      ),
    ));
  }
}"""

pattern = r"void main\(\) async \{.*?\n\}\n"
content = re.sub(pattern, new_main + "\n", content, flags=re.DOTALL)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)