import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Revert sort when adding
add_new = """setState(() {
                                _vacations.add(picked!);
                                _vacations.sort((a, b) => a.start.compareTo(b.start));
                              });"""
add_old = "setState(() => _vacations.add(picked!));"
content = content.replace(add_new, add_old)

# Revert sort when loading
load_new = """        _vacations = vacs.map((v) => DateTimeRange(
          start: DateTime.parse(v['start']!),
          end: DateTime.parse(v['end']!),
        )).toList()..sort((a, b) => a.start.compareTo(b.start));"""
load_old = """        _vacations = vacs.map((v) => DateTimeRange(
          start: DateTime.parse(v['start']!),
          end: DateTime.parse(v['end']!),
        )).toList();"""
content = content.replace(load_new, load_old)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)