import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """        bool isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
        bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);"""
        
good1 = """        bool isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
        String delegateName = "Quelqu'un";
        if (isDelegated) {
           final parts = _delegatedBookingsMap[dateStr]!.split('|');
           delegateName = parts.length > 1 ? parts[1] : parts[0];
        }
        bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);"""
content = content.replace(bad1, good1)

bad2 = """          if (isDelegated) {
            upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": _delegatedBookingsMap[dateStr]});
          }"""
          
good2 = """          if (isDelegated) {
            upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": delegateName});
          }"""
content = content.replace(bad2, good2)

bad3 = """        if (isBooked) {
          if (source == 'Ailleurs' || source == 'Délégué') {
            await _api.cancelBookingByDate(token, dateStr);
          } else {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
        }"""
        
good3 = """        if (isBooked) {
          if (source == 'Délégué') {
            final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
            final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
            await _api.cancelReservation(dateStr, token, wsId);
          } else if (source == 'Ailleurs') {
            await _api.cancelBookingByDate(token, dateStr);
          } else {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
        }"""
content = content.replace(bad3, good3)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)