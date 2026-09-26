import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');
  
  content = content.replaceFirst('''    if (Platform.isAndroid) {
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
    }''', '');
    
  content = content.replaceFirst(
    '''  Future<void> _toggleAutomation(bool val) async {
    setState(() => _automationEnabled = val);
    await _storage.saveAutomationEnabled(val);

    if (val) {
      if (Platform.isAndroid) {
        final now = DateTime.now();''',
    '''  Future<void> _toggleAutomation(bool val) async {
    setState(() => _automationEnabled = val);
    await _storage.saveAutomationEnabled(val);

    if (val) {
      if (Platform.isAndroid) {
        final hasSeen = await _storage.getHasSeenOptimization();
        if (!hasSeen && mounted) {
          await _storage.saveHasSeenOptimization(true);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OptimizationScreen()),
          ).then((_) => _checkPermissionsStatus());
        }

        final now = DateTime.now();'''
  );

  content = content.replaceFirst(
    'if (Platform.isAndroid && _permissionStatus != 0)',
    'if (Platform.isAndroid && _automationEnabled)'
  );

  file.writeAsStringSync(content);
}
