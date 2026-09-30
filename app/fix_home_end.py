import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix Home Tab closing parentheses
home_end_bad = """                ],
              ),
            ),
          ),
        ),
        ),
        if (_isCalendarBusy)"""
home_end_good = """                ],
              ),
            ),
          ),
        ),
        ),
        ),
        if (_isCalendarBusy)"""
content = content.replace(home_end_bad, home_end_good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)