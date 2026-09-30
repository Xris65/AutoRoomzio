import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = 'label: const Text("Toutes mes réservations"),'
good = 'label: const Text("Mes places"),'

content = content.replace(bad, good)
content = content.replace('label: const Text("Toutes mes r\xc3\xa9servations"),', good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)