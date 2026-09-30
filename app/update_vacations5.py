import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("                            Padding(\n                              padding: const EdgeInsets.all(8.0),", "                            if (_vacationsEnabled) Padding(\n                              padding: const EdgeInsets.all(8.0),")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)