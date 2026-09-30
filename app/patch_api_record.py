import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = "Future<WorkspaceOccupancyResult> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {"
good1 = "Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {"

bad2 = "return WorkspaceOccupancyResult(occupied, delegated);"
good2 = "return (occupiedByOthers: occupied, delegatedBookings: delegated);"

bad3 = "return MyReservationsResult(here, elsewhere, {});"
good3 = "return (here: here, elsewhere: elsewhere, delegated: <String, String>{});"

content = content.replace(bad1, good1).replace(bad2, good2).replace(bad3, good3)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)