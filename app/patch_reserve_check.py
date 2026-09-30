import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """      try {
        if (action == 'reserve') {
          setState(() {"""

good = """      try {
        if (action == 'reserve') {
          if (_bookedDates.contains(dateStr) || _bookedElsewhereMap.containsKey(dateStr)) {
            if (mounted) _showTopToast('Place déjà réservée (filtre désactivé)', isError: true);
            return;
          }
          setState(() {"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)