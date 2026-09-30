import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Sort when loading
load_old = """        _vacations = vacs.map((v) => DateTimeRange(
          start: DateTime.parse(v['start']!),
          end: DateTime.parse(v['end']!),
        )).toList();"""
load_new = """        _vacations = vacs.map((v) => DateTimeRange(
          start: DateTime.parse(v['start']!),
          end: DateTime.parse(v['end']!),
        )).toList()..sort((a, b) => a.start.compareTo(b.start));"""
content = content.replace(load_old, load_new)

# Sort when adding
add_old = """                                setState(() => _vacations.add(picked!));
                                _storage.saveVacations(_vacations.map((v) => {'start': v.start.toIso8601String(), 'end': v.end.toIso8601String()}).toList());"""
add_new = """                                setState(() {
                                  _vacations.add(picked!);
                                  _vacations.sort((a, b) => a.start.compareTo(b.start));
                                });
                                _storage.saveVacations(_vacations.map((v) => {'start': v.start.toIso8601String(), 'end': v.end.toIso8601String()}).toList());"""
content = content.replace(add_old, add_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)