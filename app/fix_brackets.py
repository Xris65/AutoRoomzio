import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """                ),
              ),
              bottomNavigationBar: Container("""
good = """                ),
              ),
              ),
              bottomNavigationBar: Container("""
content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)