import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        final myUserId = myBookings.myUserId ?? await _api.getCurrentUserId(accessToken);
        
        final occResult = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, myUserId) : (occupiedByOthers: <String, String>{}, delegatedBookings: <String, String>{});"""

good = """        final myUserId = myBookings.myUserId ?? await _api.getCurrentUserId(accessToken);
        
        final occResult = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, myUserId) : (occupiedByOthers: <String, String>{}, delegatedBookings: <String, String>{});
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DEBUG: ID=$myUserId | Dels=${occResult.delegatedBookings.length}'), duration: const Duration(seconds: 5)));"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)