import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_clean = "String releaseNotes = data['body'] ?? 'Améliorations et corrections diverses.';"
good_clean = """String releaseNotes = data['body'] ?? 'Améliorations et corrections diverses.';
          releaseNotes = releaseNotes.replaceAll(RegExp(r'\\*\\*'), '').replaceAll(RegExp(r'###\\s?'), '');"""

content = content.replace(bad_clean, good_clean)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)