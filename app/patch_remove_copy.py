import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"\s*IconButton\(\s*icon: const Icon\(Icons\.copy\),[\s\S]*?Text\('JSON copi. !'\)\);\s*\}\s*\}\s*\),"

content = re.sub(bad, "", content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)