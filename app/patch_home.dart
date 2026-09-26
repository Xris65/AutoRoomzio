import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst(
    '''    if (val) {
      if (Platform.isAndroid) {
        // Au lieu de demander brusquement, on ouvre l'écran d'optimisation
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OptimizationScreen()),
          );
        }
      }
      if (mounted) {
        _showTopToast('Automatisation activée', isSuccess: true);
      }
      _checkAndScheduleNow();
    }''',
    '''    if (val) {
      if (mounted) {
        _showTopToast('Automatisation activée', isSuccess: true);
      }
      _checkAndScheduleNow();
    }'''
  );

  file.writeAsStringSync(content);
}
