import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "child: AnimatedSwitcher(",
    "child: SizedBox.expand(child: AnimatedSwitcher("
)

# And add the closing parenthesis for SizedBox.expand
content = content.replace(
    "                  child: tabs[_currentIndex]['widget'] as Widget,\n                ),\n              ),\n              ),",
    "                  child: tabs[_currentIndex]['widget'] as Widget,\n                ),\n              ),\n              ),\n              ),"
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)