import 'dart:io';
void main() {
  final file = File('lib/background_task.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');

  final regexp = RegExp(r'if \(vStart != null && vEnd != null\) \{.*?continue;\s*\}\s*\}', dotAll: true);
  final newBlock = '''      bool isVacation = false;
      for (final v in vacations) {
        final d = DateTime(targetDate.year, targetDate.month, targetDate.day);
        final start = DateTime.parse(v['start']!);
        final end = DateTime.parse(v['end']!);
        final startNorm = DateTime(start.year, start.month, start.day);
        final endNorm = DateTime(end.year, end.month, end.day);
        if (d.compareTo(startNorm) >= 0 && d.compareTo(endNorm) <= 0) {
          isVacation = true;
          break;
        }
      }
      
      if (isVacation) {
        debugPrint("🏖️ Vacation mode is ON for \, skipping automation.");
        continue;
      }''';
      
  content = content.replaceFirst(regexp, newBlock);
  file.writeAsStringSync(content);
}
