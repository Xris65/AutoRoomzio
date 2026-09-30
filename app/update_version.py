import re

with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("version: 1.3.1+8", "version: 1.3.1")

with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    f.write(content)