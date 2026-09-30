import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

add_old = r"setState\(\(\) => _vacations\.add\(picked!\)\);"
add_new = """setState(() {
                                _vacations.add(picked!);
                                _vacations.sort((a, b) => a.start.compareTo(b.start));
                              });"""
content = re.sub(add_old, add_new, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)