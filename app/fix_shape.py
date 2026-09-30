import re

with open('lib/screens/setup_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("child: Container(width: 40, height: 40, shape: BoxShape.circle, color: Colors.white)),", "child: Container(width: 40, height: 40, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),")

with open('lib/screens/setup_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)