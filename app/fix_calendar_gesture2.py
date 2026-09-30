import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("child: TableCalendar(", "child: TableCalendar(\n                      availableGestures: AvailableGestures.horizontalSwipe,")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)