import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = r"final isBooked = _bookedDates\.contains\(dateStr\);\s*final isRequested = _requestedDates\.contains\(dateStr\);\s*final isIgnored = _ignoredDates\.contains\(dateStr\);\s*final isElsewhere = _bookedElsewhereMap\.containsKey\(dateStr\) && _showAllReservations;"
good1 = "final isBooked = _bookedDates.contains(dateStr) && _showAllReservations;\n      final isRequested = _requestedDates.contains(dateStr) && _showAllReservations;\n      final isIgnored = _ignoredDates.contains(dateStr) && _showAllReservations;\n      final isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;"
content = re.sub(bad1, good1, content)

bad2 = """        bool isBooked = _bookedDates.contains(dateStr);
        bool isRequested = _requestedDates.contains(dateStr);
        bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr);
          bool isDelegated = _delegatedBookingsMap.containsKey(dateStr);
          bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);
        bool isRecurring = _automationEnabled && _selectedDays.contains(date.weekday);"""
good2 = """        bool isBooked = _bookedDates.contains(dateStr) && _showAllReservations;
        bool isRequested = _requestedDates.contains(dateStr) && _showAllReservations;
        bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
          bool isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
          bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);
        bool isRecurring = _automationEnabled && _selectedDays.contains(date.weekday) && _showAllReservations;"""
content = content.replace(bad2, good2)

bad3 = """        if (isElsewhere) {
          if (_showAllReservations) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
          } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": false, "name": _bookedElsewhereMap[dateStr]});
            recurringProjectionsCount++;
          }
        }"""
        
good3 = """        if (isElsewhere) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
        }"""
content = content.replace(bad3, good3)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)