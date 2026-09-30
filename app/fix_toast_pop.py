import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'content: Text("Appuyez A nouveau pour quitter"),\n              duration: Duration(seconds: 2),',
    'content: Text("Appuyez à nouveau pour quitter"),\n              behavior: SnackBarBehavior.floating,\n              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),\n              duration: Duration(seconds: 2),'
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)