import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_calendar = """                    child: TableCalendar(
                      enabledDayPredicate: (day) {"""
new_calendar = """                    child: TableCalendar(
                      availableGestures: AvailableGestures.horizontalSwipe,
                      enabledDayPredicate: (day) {"""
content = content.replace(old_calendar, new_calendar)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)