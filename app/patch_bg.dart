import 'dart:io';

void main() {
  final file = File('lib/background_task.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');

  content = content.replaceFirst(
    '''    final vacationData = await storage.getVacationDates();
    DateTime? vStart;
    DateTime? vEnd;
    if (vacationData['start'] != null && vacationData['end'] != null) {
      vStart = DateTime.parse(vacationData['start']!);
      vEnd = DateTime.parse(vacationData['end']!);
    }''',
    '''    final vacations = await storage.getVacations();'''
  );

  content = content.replaceFirst(
    '''      if (vStart != null && vEnd != null) {
        final d = DateTime(targetDate.year, targetDate.month, targetDate.day);
        final start = DateTime(vStart.year, vStart.month, vStart.day);
        final end = DateTime(vEnd.year, vEnd.month, vEnd.day);
        if (d.compareTo(start) >= 0 && d.compareTo(end) <= 0) {
          debugPrint("🏝️ Vacation mode is ON for \, skipping automation.");
          continue;
        }
      }''',
    '''      bool isVacation = false;
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
        debugPrint("🏝️ Vacation mode is ON for \, skipping automation.");
        continue;
      }'''
  );

  file.writeAsStringSync(content);
}
