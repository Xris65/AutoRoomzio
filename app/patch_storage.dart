import 'dart:io';

void main() {
  final file = File('lib/storage_service.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst(
    '''  Future<void> clearAll() async {''',
    '''  Future<void> saveHasSeenOptimization(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_optimization', val);
  }

  Future<bool> getHasSeenOptimization() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_seen_optimization') ?? false;
  }

  Future<void> saveAutostartVerified(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autostart_verified', val);
  }

  Future<bool> getAutostartVerified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('autostart_verified') ?? false;
  }

  Future<void> clearAll() async {'''
  );
  file.writeAsStringSync(content);
}
