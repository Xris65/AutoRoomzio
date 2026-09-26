import 'dart:io';

void main() {
  final file = File('lib/storage_service.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');
  
  if (!content.contains('dart:convert')) {
    content = "import 'dart:convert';\n" + content;
  }
  
  content = content.replaceFirst(
    '''  Future<void> saveVacationDates(String? start, String? end) async {
    final prefs = await SharedPreferences.getInstance();
    if (start == null || end == null) {
      await prefs.remove('vacation_start');
      await prefs.remove('vacation_end');
    } else {
      await prefs.setString('vacation_start', start);
      await prefs.setString('vacation_end', end);
    }
  }

  Future<Map<String, String?>> getVacationDates() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'start': prefs.getString('vacation_start'),
      'end': prefs.getString('vacation_end'),
    };
  }''',
    '''  Future<void> saveVacations(List<Map<String, String>> vacations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vacation_periods', jsonEncode(vacations));
  }

  Future<List<Map<String, String>>> getVacations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('vacation_periods');
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        return decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (e) {
        return [];
      }
    } else {
      // Backward compatibility
      final oldStart = prefs.getString('vacation_start');
      final oldEnd = prefs.getString('vacation_end');
      if (oldStart != null && oldEnd != null) {
        return [{'start': oldStart, 'end': oldEnd}];
      }
      return [];
    }
  }

  // Gardé provisoirement pour compatibilité le temps de la migration complète
  Future<void> saveVacationDates(String? start, String? end) async {}
  Future<Map<String, String?>> getVacationDates() async { return {}; }'''
  );

  file.writeAsStringSync(content);
}
