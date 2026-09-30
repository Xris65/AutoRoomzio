import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

pageview_old = """              body: PageView(
                controller: _pageController,
                onPageChanged: (index) {"""
pageview_new = """              body: PageView(
                key: ValueKey(tabs.length),
                controller: _pageController,
                onPageChanged: (index) {"""
content = content.replace(pageview_old, pageview_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)