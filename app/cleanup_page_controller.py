import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove _pageController declaration and dispose
content = re.sub(r"  late PageController _pageController;\n", "", content)
content = re.sub(r"    _pageController = PageController\(initialPage: _currentIndex\);\n", "", content)
content = re.sub(r"    _pageController\.dispose\(\);\n", "", content)

# 2. Clean up the Settings toggles
toggle_auto_old = """                        final oldController = _pageController;
                        _pageController = PageController(initialPage: _currentIndex);
                        oldController.dispose();"""
content = content.replace(toggle_auto_old, "")

toggle_stats_old = """                        final oldController = _pageController;
                        _pageController = PageController(initialPage: _currentIndex);
                        oldController.dispose();"""
content = content.replace(toggle_stats_old, "")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)