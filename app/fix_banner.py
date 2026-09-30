import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_banner_condition = "if (_vacations.any((v) => DateTime.now().isAfter(v.start.subtract(const Duration(days: 1))) && DateTime.now().isBefore(v.end.add(const Duration(days: 1)))))"
new_banner_condition = "if (_showAutomation && _vacations.any((v) => DateTime.now().isAfter(v.start.subtract(const Duration(days: 1))) && DateTime.now().isBefore(v.end.add(const Duration(days: 1)))))"

content = content.replace(old_banner_condition, new_banner_condition)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)