import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"final occResult = floorId != null \? await _api\.getWorkspaceOccupancy\(accessToken, workspaceId, floorId, visibleDates, myUserId\) : \(occupiedByOthers: <String, String>\{\}, delegatedBookings: <String, String>\{\}\);\s*final occupiedDates = occResult\.occupiedByOthers;\s*_delegatedBookingsMap = occResult\.delegatedBookings;\s*if \(mounted\) ScaffoldMessenger\.of\(context\)\.showSnackBar\(SnackBar\(content: Text\('DEBUG: ID=\$myUserId \| Dels=\$\{\_delegatedBookingsMap\.length\}'\)\)\);\s*final bookedHere = myBookings\.here;\s*final bookedElsewhere = myBookings\.elsewhere;\s*for \(final d in _delegatedBookingsMap\.keys\) \{\s*bookedHere\.remove\(d\);\s*bookedElsewhere\.remove\(d\);\s*\}"

good = """        final occResult = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, myUserId) : (occupiedByOthers: <String, String>{}, delegatedBookings: <String, String>{}, delegatedHere: <String>{}, delegatedElsewhere: <String>{});
        final occupiedDates = occResult.occupiedByOthers;
        _delegatedBookingsMap = occResult.delegatedBookings;
        
        final bookedHere = myBookings.here;
        final bookedElsewhere = myBookings.elsewhere;
        
        for (final d in occResult.delegatedHere) {
           bookedHere.remove(d);
        }
        for (final d in occResult.delegatedElsewhere) {
           bookedElsewhere.remove(d);
        }"""

if re.search(bad, content):
    content = re.sub(bad, good, content)
else:
    print("MATCH FAILED")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)