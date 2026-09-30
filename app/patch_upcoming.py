import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        if (isElsewhere) {
          upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
        } else if (isBooked) {
          upcoming.add({"date": date, "source": "Calendrier", "isBooked": true});
        } else if (isRequested) {
          upcoming.add({"date": date, "source": "Calendrier", "isBooked": false});
        } else if (isOccupiedByOthers) {"""
        
good = """        if (isElsewhere) {
          // If the elsewhere booking is actually a delegation, DO NOT show it as a personal 'Ailleurs' booking
          // UNLESS delegated reservations are hidden, in which case we might want to hide it entirely?
          // Actually, if it's delegated, we already added it above. So we don't add it as 'Ailleurs'.
          if (!isDelegated) {
             upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
          }
        } 
        
        if (isBooked) {
          // Same logic: if my default desk is delegated, don't show my personal booking tile for it.
          if (!(isDelegated && _delegatedBookingsMap[dateStr]!.contains('Mon bureau'))) {
             upcoming.add({"date": date, "source": "Calendrier", "isBooked": true});
          }
        } else if (isRequested) {
          upcoming.add({"date": date, "source": "Calendrier", "isBooked": false});
        }
        
        if (!isBooked && !isElsewhere && !isDelegated && isOccupiedByOthers) {"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)