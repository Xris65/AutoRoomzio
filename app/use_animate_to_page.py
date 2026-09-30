import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

nav_old = """            onTap: () {
              if (index == _currentIndex) return;
              _pageController.jumpToPage(index);
            },"""
nav_new = """            onTap: () {
              if (index == _currentIndex) return;
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            },"""
content = content.replace(nav_old, nav_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)