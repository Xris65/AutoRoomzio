import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = r"await _api\.getWorkspaceOccupancy\(accessToken, workspaceId, floorId, visibleDates\)"
good1 = "await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, null)"
content = re.sub(bad1, good1, content)

bad2 = r"final occupiedDates = floorId != null \? await _api\.getWorkspaceOccupancy\(accessToken, workspaceId, floorId, visibleDates, null\) : <String, String>\{\};"
good2 = "final occResult = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, null) : (occupiedByOthers: <String, String>{}, delegatedBookings: <String, String>{});\n      final occupiedDates = occResult.occupiedByOthers;"
content = re.sub(bad2, good2, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)