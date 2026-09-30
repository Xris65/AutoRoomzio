import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace PageView with AnimatedSwitcher
pageview_old = """              body: PageView(
                key: ValueKey(tabs.length),
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                children: tabs.map((t) => KeyedSubtree(key: ValueKey(t['id']), child: t['widget'] as Widget)).toList(),
              ),"""
pageview_new = """              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: KeyedSubtree(
                  key: ValueKey(tabs[_currentIndex]['id']),
                  child: tabs[_currentIndex]['widget'] as Widget,
                ),
              ),"""
content = content.replace(pageview_old, pageview_new)

# Update Bottom Nav Bar onTap to just set state
nav_old = """            onTap: () {
              if (index == _currentIndex) return;
              _pageController.jumpToPage(index);
            },"""
nav_new = """            onTap: () {
              if (index == _currentIndex) return;
              setState(() => _currentIndex = index);
            },"""
content = content.replace(nav_old, nav_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)