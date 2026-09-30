import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"      if \(isElsewhere\) \{.*?recurringProjectionsCount\+\+;\s*\}"
good = """      if (isDelegated) {
        upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": delegateName});
      }
      
      if (isElsewhere) {
        upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
      } else if (isBooked) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": true});
      } else if (isRequested) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": false});
      } else if (isOccupiedByOthers) {
        if (isRecurring && recurringProjectionsCount < _projectionsCount) {
          upcoming.add({"date": date, "source": "Occupé", "isBooked": false, "name": _occupiedByOthers[dateStr]});
          recurringProjectionsCount++;
        }
      } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
        upcoming.add({"date": date, "source": "Récurrent", "isBooked": false});
        recurringProjectionsCount++;
      }"""
content = re.sub(bad, good, content, flags=re.DOTALL)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)