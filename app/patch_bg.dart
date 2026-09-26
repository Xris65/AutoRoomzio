import 'dart:io';

void main() {
  final file = File('lib/background_task.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst(
    '''    final token = await api.refreshMyToken();
    if (token == null) {''',
    '''    // Health Check: on enregistre que la tAche a bien pu dAcmarrer
    await storage.saveLastAutomationRun();

    final token = await api.refreshMyToken();
    if (token == null) {'''
  );
  
  // also fix corrupted accents in background_task.dart
  content = content.replaceAll('dY"?', '📅'); // if it was corrupted emojis
  content = content.replaceAll('s,?', '❌');
  content = content.replaceAll('dYs?', '🚀');
  content = content.replaceAll('RAcservation rAcussie', 'Réservation réussie');
  content = content.replaceAll('vient de rAcserver', 'vient de réserver');
  content = content.replaceAll('tAche', 'tâche');
  content = content.replaceAll('dAcmarrer', 'démarrer');

  file.writeAsStringSync(content);
}
