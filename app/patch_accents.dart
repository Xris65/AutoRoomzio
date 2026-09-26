import 'dart:io';

void main() {
  final file = File('lib/screens/optimization_screen.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceAll('DAcmarrage', 'Démarrage');
  content = content.replaceAll('tAclAcphone', 'téléphone');
  content = content.replaceAll('nAccessiter', 'nécessiter');
  content = content.replaceAll('spAccifique', 'spécifique');
  content = content.replaceAll('VAcrifier', 'Vérifier');
  content = content.replaceAll('aprA"s', 'après');
  content = content.replaceAll('redAcmarrage', 'redémarrage');
  content = content.replaceAll('EmpA\\u00AAche', 'Empêche');
  content = content.replaceAll('arriA"re-plan', 'arrière-plan');
  content = content.replaceAll('DAcsactiver', 'Désactiver');
  content = content.replaceAll('tAche de fond', 'tâche de fond');
  content = content.replaceAll('exAcution', 'exécution');
  content = content.replaceAll('rAcservations', 'réservations');

  file.writeAsStringSync(content);
}
