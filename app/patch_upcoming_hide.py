import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad2 = r"bool isBooked = _bookedDates\.contains\(dateStr\);\s*bool isRequested = _requestedDates\.contains\(dateStr\);\s*bool isElsewhere = _bookedElsewhereMap\.containsKey\(dateStr\);\s*bool isDelegated = _delegatedBookingsMap\.containsKey\(dateStr\);\s*bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers\.containsKey\(dateStr\);\s*bool isRecurring = _automationEnabled && _selectedDays\.contains\(date\.weekday\);"
good2 = "bool isBooked = _bookedDates.contains(dateStr) && _showAllReservations;\n        bool isRequested = _requestedDates.contains(dateStr) && _showAllReservations;\n        bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;\n        bool isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;\n        bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);\n        bool isRecurring = _automationEnabled && _selectedDays.contains(date.weekday) && _showAllReservations;"
content = re.sub(bad2, good2, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)