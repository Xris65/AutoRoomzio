import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

switcher_old = """              body: AnimatedSwitcher("""
switcher_new = """              body: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity == null) return;
                  if (details.primaryVelocity! > 300) {
                    if (_currentIndex > 0) setState(() => _currentIndex--);
                  } else if (details.primaryVelocity! < -300) {
                    if (_currentIndex < tabs.length - 1) setState(() => _currentIndex++);
                  }
                },
                child: AnimatedSwitcher("""
content = content.replace(switcher_old, switcher_new)

switcher_end_old = """                  child: KeyedSubtree(
                    key: ValueKey(tabs[_currentIndex]['id']),
                    child: tabs[_currentIndex]['widget'] as Widget,
                  ),
                ),
                bottomNavigationBar: Container("""
switcher_end_new = """                  child: KeyedSubtree(
                    key: ValueKey(tabs[_currentIndex]['id']),
                    child: tabs[_currentIndex]['widget'] as Widget,
                  ),
                ),
              ),
              bottomNavigationBar: Container("""
content = content.replace(switcher_end_old, switcher_end_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)