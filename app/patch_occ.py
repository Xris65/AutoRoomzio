import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_occ = r"Future<Map<String, String>> getWorkspaceOccupancy\(String token, String workspaceId, String floorId, List<String> dates\) async \{\s*final Map<String, String> occupied = \{\};\s*final client = http\.Client\(\);"

good_occ = """Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {
    final Map<String, String> occupied = {};
    final Map<String, String> delegated = {};
    final client = http.Client();"""

content = re.sub(bad_occ, good_occ, content)

bad_occ_loop = r"for \(final item in items\) \{[\s\S]*?occupied\[date\] = name;\s*\}\s*break;\s*\}\s*\}"
good_occ_loop = """for (final item in items) {
                    final isMyDesk = (item['workspaceId'] == workspaceId || item['id'] == workspaceId);
                    
                    if (item['status'] == 'Reserved') {
                      final bookedTimeSlot = item['bookedTimeSlot'];
                      if (bookedTimeSlot != null) {
                        final creator = bookedTimeSlot['creator'];
                        final organizer = bookedTimeSlot['organizer'];
                        
                        bool isDelegated = false;
                        String delegateName = "Quelqu'un";
                        
                        if (creator != null && organizer != null && myUserId != null && creator['id'] == myUserId) {
                           final organizerName = organizer['name'];
                           final creatorName = creator['name'];
                           if (organizerName != null && organizerName != creatorName) {
                              isDelegated = true;
                              delegateName = organizerName;
                           }
                        }
                        
                        if (isDelegated) {
                           delegated[date] = delegateName;
                        } else if (isMyDesk) {
                           String name = "Quelqu'un d'autre";
                           if (bookedTimeSlot['owner'] != null && bookedTimeSlot['owner']['name'] != null) {
                             name = bookedTimeSlot['owner']['name'];
                           } else if (bookedTimeSlot['user'] != null && bookedTimeSlot['user']['name'] != null) {
                             name = bookedTimeSlot['user']['name'];
                           } else if (bookedTimeSlot['bookedFor'] != null && bookedTimeSlot['bookedFor']['name'] != null) {
                             name = bookedTimeSlot['bookedFor']['name'];
                           } else if (creator != null) {
                             name = creator['name'] ?? name;
                           }
                           
                           // Don't mark as occupied by others if it's actually booked by US
                           if (creator == null || creator['id'] != myUserId) {
                             occupied[date] = name;
                           }
                        }
                      }
                    }
                  }"""
content = re.sub(bad_occ_loop, good_occ_loop, content)

bad_occ_ret = r"return occupied;"
good_occ_ret = "return (occupiedByOthers: occupied, delegatedBookings: delegated);"
content = re.sub(bad_occ_ret, good_occ_ret, content)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)