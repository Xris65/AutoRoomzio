import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix toggle leftovers
content = re.sub(r"                        final oldController = _pageController;\n", "", content)
content = re.sub(r"                        oldController\.dispose\(\);\n", "", content)

# Fix _buildNavItem leftover (wait, didn't I replace it already?)
content = re.sub(r"              _pageController\.jumpToPage\(index\);\n", "              setState(() => _currentIndex = index);\n", content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)