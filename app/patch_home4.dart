import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst(
    '''    final autostart = await _storage.getAutostartVerified();

    int okCount = 0;
    if (batteryOpt) okCount++;
    if (notif) okCount++;
    if (autostart) okCount++;''',
    '''    bool autostart = await _storage.getAutostartVerified();

    // HEALTH CHECK
    if (autostart && _automationEnabled) {
      final lastRun = await _storage.getLastAutomationRun();
      if (lastRun != null) {
        final hoursSinceLastRun = DateTime.now().difference(lastRun).inHours;
        // Si l'autostart est activé depuis plus de 48h mais n'a pas tourné
        if (hoursSinceLastRun > 48) {
          autostart = false;
          await _storage.saveAutostartVerified(false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("L'automatisation semble avoir été bloquée par le système en arrière-plan. Veuillez vérifier l'autostart."),
                backgroundColor: Colors.redAccent,
              )
            );
          }
        }
      }
    }

    int okCount = 0;
    if (batteryOpt) okCount++;
    if (notif) okCount++;
    if (autostart) okCount++;'''
  );

  file.writeAsStringSync(content);
}
