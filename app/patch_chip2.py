import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'label:\s*const\s*Text\("Toutes mes.*?\"\)', 'label: const Text("Mes places")', content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)