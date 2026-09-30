import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("                          ..._vacations.map((v) {", "                          if (_vacationsEnabled) ..._vacations.map((v) {")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)