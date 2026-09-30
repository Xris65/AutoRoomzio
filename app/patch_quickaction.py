import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = r"icon: Icon\(isBooked \? Icons\.delete_outline : Icons\.block, size: 20\),\s*color: Colors\.redAccent,\s*tooltip: isBooked \? 'Supprimer' : 'Bloquer',\s*onPressed: \(\) => _quickAction\(date, isBooked, source\),"
good1 = "icon: Icon(isBooked || source == 'Délégué' || source == 'Ailleurs' ? Icons.delete_outline : Icons.block, size: 20),\n                      color: Colors.redAccent,\n                      tooltip: isBooked || source == 'Délégué' || source == 'Ailleurs' ? 'Supprimer' : 'Bloquer',\n                      onPressed: () => _quickAction(date, isBooked || source == 'Délégué' || source == 'Ailleurs', source),"
content = re.sub(bad1, good1, content)

bad2 = """        if (isBooked) {
          if (source == 'Ailleurs') {
            await _api.cancelBookingByDate(token, dateStr);
          } else {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
          
        }
  
        setState(() {
          if (isBooked) {
            if (source == 'Ailleurs') {
              _bookedElsewhereMap.remove(dateStr);
            } else {
              _bookedDates.remove(dateStr);
              _occupiedByOthers.remove(dateStr);
              _requestedDates.remove(dateStr);
            }
          } else {
            _ignoredDates.add(dateStr);
          }
        });"""

good2 = """        if (isBooked) {
          if (source == 'Ailleurs' || source == 'Délégué') {
            await _api.cancelBookingByDate(token, dateStr);
          } else {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
        }
  
        setState(() {
          if (isBooked) {
            if (source == 'Ailleurs') {
              _bookedElsewhereMap.remove(dateStr);
            } else if (source == 'Délégué') {
              _delegatedBookingsMap.remove(dateStr);
            } else {
              _bookedDates.remove(dateStr);
              _occupiedByOthers.remove(dateStr);
              _requestedDates.remove(dateStr);
            }
          } else {
            _ignoredDates.add(dateStr);
          }
        });"""
content = content.replace(bad2, good2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)