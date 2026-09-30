import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix jumpToPage for auto toggle
old_auto_jump = """                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(_currentIndex);
                      }"""
new_auto_jump = """                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(_currentIndex);
                        }
                      });"""
content = content.replace(old_auto_jump, new_auto_jump)

# Fix jumpToPage for stats toggle
# (It will replace both since they are identical strings, let's make sure it does)
# Wait, string replace replaces all occurrences by default in python!
# So replacing old_auto_jump with new_auto_jump handles both if they are exactly the same string.

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)