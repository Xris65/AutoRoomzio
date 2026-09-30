import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add http import
if "import 'package:http/http.dart' as http;" not in content:
    content = content.replace("import 'package:http/http.dart';", "import 'package:http/http.dart' as http;")
    if "import 'package:http/http.dart' as http;" not in content:
        content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:http/http.dart' as http;")

# Fix the broken string
broken = "content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\n\nVoulez-vous la télécharger et l'installer maintenant ?'),"
fixed = "content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\\n\\nVoulez-vous la télécharger et l\\'installer maintenant ?'),"
content = content.replace(broken, fixed)

# Check for the other one
broken2 = "content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\n\nVoulez-vous la télécharger et l\\'installer maintenant ?'),"
content = content.replace(broken2, fixed)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)