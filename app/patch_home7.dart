import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');

  content = content.replaceFirst('  DateTime? _vacationStart;', '  List<DateTimeRange> _vacations = [];');
  content = content.replaceFirst('  DateTime? _vacationEnd;', '');
  
  content = content.replaceFirst(
    '''      final vac = await _storage.getVacationDates();''',
    '''      final vacs = await _storage.getVacations();'''
  );

  content = content.replaceFirst(
    '''          _vacationStart = vac['start'] != null ? DateTime.tryParse(vac['start']!) : null;
          _vacationEnd = vac['end'] != null ? DateTime.tryParse(vac['end']!) : null;''',
    '''          _vacations = vacs.map((v) => DateTimeRange(
            start: DateTime.parse(v['start']!),
            end: DateTime.parse(v['end']!)
          )).toList();'''
  );

  file.writeAsStringSync(content);
}
