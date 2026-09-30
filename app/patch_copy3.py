with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('\\"', '"')
with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)