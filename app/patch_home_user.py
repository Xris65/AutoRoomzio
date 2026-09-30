import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """      final myUserId = await _api.getCurrentUserId(token);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DEBUG User ID: $myUserId')));
      final currentBookings = await _api.getMyReservations(token, _workspaceId!);"""

good = """      final currentBookings = await _api.getMyReservations(token, _workspaceId!);
      final myUserId = currentBookings.myUserId ?? await _api.getCurrentUserId(token);"""

content = content.replace(bad, good)
content = content.replace(bad.replace("      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DEBUG User ID: $myUserId')));\n", ""), good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)