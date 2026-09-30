import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"      final isElsewhere = _bookedElsewhereMap\.containsKey\(dateStr\) && _showAllReservations;\s*final isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers\.containsKey\(dateStr\);\s*final differenceInDays = day\.difference\(today\)\.inDays;"

good = """      final isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
      final isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
      final isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);
      final differenceInDays = day.difference(today).inDays;"""

content = re.sub(bad, good, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)