import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"final occResult = floorId != null \? await _api\.getWorkspaceOccupancy\(accessToken, workspaceId, floorId, visibleDates, null\) : \(occupiedByOthers: <String, String>\{\}, delegatedBookings: <String, String>\{\}\);\s*final occupiedDates = occResult\.occupiedByOthers;\s*final myBookings = await _api\.getMyReservations\(accessToken, workspaceId\);\s*final bookedHere = myBookings\.here;\s*final bookedElsewhere = myBookings\.elsewhere;"
        
good = """        final myBookings = await _api.getMyReservations(accessToken, workspaceId);
        final myUserId = myBookings.myUserId ?? await _api.getCurrentUserId(accessToken);
        
        final occResult = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, myUserId) : (occupiedByOthers: <String, String>{}, delegatedBookings: <String, String>{});
        final occupiedDates = occResult.occupiedByOthers;
        _delegatedBookingsMap = occResult.delegatedBookings;
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DEBUG: ID=$myUserId | Dels=${_delegatedBookingsMap.length}')));
        
        final bookedHere = myBookings.here;
        final bookedElsewhere = myBookings.elsewhere;
        
        for (final d in _delegatedBookingsMap.keys) {
           bookedHere.remove(d);
           bookedElsewhere.remove(d);
        }"""

if re.search(bad, content):
    content = re.sub(bad, good, content)
else:
    print("FAILED TO MATCH")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)