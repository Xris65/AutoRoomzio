import 'dart:io';

void main() {
  final file = File('lib/storage_service.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst(
    '''  Future<void> clearAll() async {''',
    '''  Future<void> saveLastAutomationRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_automation_run', DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastAutomationRun() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('last_automation_run');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> clearAll() async {'''
  );

  file.writeAsStringSync(content);
}
