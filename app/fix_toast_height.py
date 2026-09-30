import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16)",
    "margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16)"
)

# And also for the one in PopScope:
content = content.replace(
    "behavior: SnackBarBehavior.floating,\n            duration: Duration(seconds: 2),",
    "behavior: SnackBarBehavior.floating,\n            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),\n            duration: Duration(seconds: 2),"
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)