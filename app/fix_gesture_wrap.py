import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# I will use regex to wrap AnimatedSwitcher in GestureDetector inside the Scaffold
pattern = r"body:\s*AnimatedSwitcher\(([\s\S]*?)child:\s*KeyedSubtree\([\s\S]*?child:\s*tabs\[_currentIndex\]\['widget'\]\s*as\s*Widget,\s*\),\s*\),"

replacement = """body: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity == null) return;
                  if (details.primaryVelocity! > 300) {
                    if (_currentIndex > 0) setState(() => _currentIndex--);
                  } else if (details.primaryVelocity! < -300) {
                    if (_currentIndex < tabs.length - 1) setState(() => _currentIndex++);
                  }
                },
                child: AnimatedSwitcher(\\1child: KeyedSubtree(
                  key: ValueKey(tabs[_currentIndex]['id']),
                  child: tabs[_currentIndex]['widget'] as Widget,
                ),
              ),
              ),"""

content = re.sub(pattern, replacement, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)