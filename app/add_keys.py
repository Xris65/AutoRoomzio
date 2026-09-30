import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_children = "children: tabs.map((t) => t['widget'] as Widget).toList(),"
new_children = "children: tabs.map((t) => KeyedSubtree(key: PageStorageKey(t['id']), child: t['widget'] as Widget)).toList(),"
content = content.replace(old_children, new_children)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)