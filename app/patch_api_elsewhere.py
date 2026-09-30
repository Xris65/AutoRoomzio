import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings, Set<String> delegatedHere, Set<String> delegatedElsewhere})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {"""
good = """  Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings, Set<String> delegatedHere, Set<String> delegatedElsewhere})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId, Map<String, String> elsewhereMap) async {"""
content = content.replace(bad, good)

bad_name = """                                final workspaceName = item['name']?.toString() ?? item['workspaceName']?.toString();
                                final location = isMyDesk ? 'Mon bureau' : (workspaceName ?? 'Autre bureau');"""
good_name = """                                final workspaceName = item['name']?.toString() ?? item['workspaceName']?.toString() ?? elsewhereMap[date];
                                final location = isMyDesk ? 'Mon bureau' : (workspaceName ?? 'Autre bureau');"""
content = content.replace(bad_name, good_name)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)