import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix _buildNavItem
content = re.sub(r"\s*_pageController\.jumpToPage\(index\);\n", "\n              setState(() => _currentIndex = index);\n", content)

# Fix oldController
content = re.sub(r"\s*final oldController = _pageController;\n", "\n", content)

# Fix line 473
content = re.sub(r"\s*_pageController\.dispose\(\);\n", "\n", content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)