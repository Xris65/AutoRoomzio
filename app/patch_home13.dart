import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');

  final newBlock = '''child: TableCalendar(
                    enabledDayPredicate: (day) {
                      final normDay = DateTime(day.year, day.month, day.day);
                      if (_hideWeekends && (normDay.weekday == DateTime.saturday || normDay.weekday == DateTime.sunday)) {
                        return false;
                      }
                      for (final v in _vacations) {
                        final start = DateTime(v.start.year, v.start.month, v.start.day);
                        final end = DateTime(v.end.year, v.end.month, v.end.day);
                        if (!normDay.isBefore(start) && !normDay.isAfter(end)) {
                          return false;
                        }
                      }
                      return true;
                    },
                    firstDay:''';
                    
  content = content.replaceFirst('child: TableCalendar(\n                    firstDay:', newBlock);
  file.writeAsStringSync(content);
}
