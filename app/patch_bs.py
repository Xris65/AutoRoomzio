import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        if (isBooked) {
          if (source == 'Ailleurs') {
            await _api.cancelBookingByDate(token, dateStr);
          } else {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
          
        }"""
        
good = """        if (isBooked) {
          if (source == 'Ailleurs') {
            await _api.cancelBookingByDate(token, dateStr, delegated: false);
          } else if (source == 'Délégué' || source == 'DÃ©lÃ©guÃ©') {
            await _api.cancelBookingByDate(token, dateStr, delegated: true);
          } else {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
        }"""

content = content.replace(bad, good)
content = content.replace(bad.replace("Délégué", "DÃ©lÃ©guÃ©"), good)

bad_remove = """          if (isBooked) {
            if (source == 'Ailleurs') {
              _bookedElsewhereMap.remove(dateStr);
            } else {
              _bookedDates.remove(dateStr);
              _occupiedByOthers.remove(dateStr);
              _requestedDates.remove(dateStr);
            }
          }"""

good_remove = """          if (isBooked) {
            if (source == 'Ailleurs') {
              _bookedElsewhereMap.remove(dateStr);
            } else if (source == 'Délégué' || source == 'DÃ©lÃ©guÃ©') {
              _delegatedBookingsMap.remove(dateStr);
            } else {
              _bookedDates.remove(dateStr);
              _occupiedByOthers.remove(dateStr);
              _requestedDates.remove(dateStr);
            }
          }"""

content = content.replace(bad_remove, good_remove)

# Add the BottomSheet option for delegated
bad_bs = """                  else if (isElsewhere)
                    ListTile(
                      leading: Icon(Icons.person_off, color: Colors.orange.shade900),
                      title: Text('Libérer mon autre bureau (${_bookedElsewhereMap[dateStr] ?? "Ailleurs"})', style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text("Annule la réservation que vous avez faite sur cet autre bureau ce jour-là.", style: TextStyle(fontSize: 11)),
                      onTap: () => Navigator.pop(context, 'cancel_elsewhere'),
                    )"""

good_bs = bad_bs + """
                  else if (isDelegated)
                    ListTile(
                      leading: Icon(Icons.group, color: Colors.purple.shade900),
                      title: Text('Annuler la réservation pour ${_delegatedBookingsMap[dateStr] ?? "un collègue"}', style: TextStyle(color: Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text("Libère la place réservée pour votre collègue.", style: TextStyle(fontSize: 11)),
                      onTap: () => Navigator.pop(context, 'cancel_delegated'),
                    )"""

content = content.replace(bad_bs, good_bs)
content = content.replace(bad_bs.replace("Libérer", "LibÃ©rer").replace("réservation", "rÃ©servation").replace("là", "lÃ "), good_bs.replace("Libérer", "LibÃ©rer").replace("réservation", "rÃ©servation").replace("là", "lÃ ").replace("collègue", "collÃ¨gue"))

bad_bs_action = """      if (action == 'cancel_elsewhere') {
        _quickAction(day, true, 'Ailleurs');
      } else if (action == 'cancel') {"""

good_bs_action = """      if (action == 'cancel_elsewhere') {
        _quickAction(day, true, 'Ailleurs');
      } else if (action == 'cancel_delegated') {
        _quickAction(day, true, 'Délégué');
      } else if (action == 'cancel') {"""

content = content.replace(bad_bs_action, good_bs_action)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)