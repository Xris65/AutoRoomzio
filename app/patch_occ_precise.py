import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = "Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {"
good1 = "Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings, Set<String> delegatedHere, Set<String> delegatedElsewhere})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {"

bad2 = """      final Map<String, String> occupied = {};
      final Map<String, String> delegated = {};"""
good2 = """      final Map<String, String> occupied = {};
      final Map<String, String> delegated = {};
      final Set<String> delegatedHere = {};
      final Set<String> delegatedElsewhere = {};"""
      
bad3 = """                        if (isDelegated) {
                           delegated[date] = delegateName;
                        } else if (isMyDesk) {"""
good3 = """                        if (isDelegated) {
                           delegated[date] = delegateName;
                           if (isMyDesk) delegatedHere.add(date);
                           else delegatedElsewhere.add(date);
                        } else if (isMyDesk) {"""
                        
bad4 = "return (occupiedByOthers: occupied, delegatedBookings: delegated);"
good4 = "return (occupiedByOthers: occupied, delegatedBookings: delegated, delegatedHere: delegatedHere, delegatedElsewhere: delegatedElsewhere);"

content = content.replace(bad1, good1).replace(bad2, good2).replace(bad3, good3).replace(bad4, good4)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)