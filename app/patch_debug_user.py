import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = "      final myUserId = await _api.getCurrentUserId(token);"
good = "      final myUserId = await _api.getCurrentUserId(token);\n      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DEBUG User ID: $myUserId')));"

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)