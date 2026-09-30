import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add WorkspaceOccupancyResult class
if "class WorkspaceOccupancyResult" not in content:
    content = content.replace("class MyReservationsResult {", "class WorkspaceOccupancyResult {\n  final Map<String, String> occupiedByOthers;\n  final Map<String, String> delegatedBookings;\n  WorkspaceOccupancyResult(this.occupiedByOthers, this.delegatedBookings);\n}\n\nclass MyReservationsResult {")

# Clean up getMyReservations
bad_my = """              // Check if it's delegated
              bool isDelegated = false;
              final creator = b['creator'];
              final organizer = b['organizer'];
              String targetName = "Quelqu'un";
              
              if (creator != null && organizer != null) {
                 if (creator['id'] != null && organizer['id'] != null && creator['id'] != organizer['id']) {
                    isDelegated = true;
                    targetName = organizer['name'] ?? targetName;
                 } else if (creator['name'] != null && organizer['name'] != null && creator['name'] != organizer['name']) {
                    isDelegated = true;
                    targetName = organizer['name'];
                 }
              }
              
              if (isDelegated) {
                 delegated[dateStr] = targetName;
              } else if (b['workspaceId']?.toString() == workspaceId) {
                here.add(dateStr);
              } else {
                elsewhere[dateStr] = b['workspace']?['name']?.toString() ?? "Ailleurs";
              }"""
              
good_my = """              if (b['workspaceId']?.toString() == workspaceId) {
                here.add(dateStr);
              } else {
                elsewhere[dateStr] = b['workspace']?['name']?.toString() ?? "Ailleurs";
              }"""
content = content.replace(bad_my, good_my)

bad_my_ret = """return MyReservationsResult(here, elsewhere, delegated);"""
good_my_ret = """return MyReservationsResult(here, elsewhere, {});"""
content = content.replace(bad_my_ret, good_my_ret)

# Modify getWorkspaceOccupancy
bad_occ = """Future<Map<String, String>> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates) async {
      final Map<String, String> occupied = {};"""
good_occ = """Future<WorkspaceOccupancyResult> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId) async {
      final Map<String, String> occupied = {};
      final Map<String, String> delegated = {};"""
content = content.replace(bad_occ, good_occ)

bad_occ_loop = """                  for (final item in items) {
                    if (item['workspaceId'] == workspaceId || item['id'] == workspaceId) {
                      // If the workspace is Reserved
                      if (item['status'] == 'Reserved') {
                        String name = "Quelqu'un d'autre";
                        final bookedTimeSlot = item['bookedTimeSlot'];
                        if (bookedTimeSlot != null) {
                            if (bookedTimeSlot['owner'] != null && bookedTimeSlot['owner']['name'] != null) {
                              name = bookedTimeSlot['owner']['name'];
                            } else if (bookedTimeSlot['user'] != null && bookedTimeSlot['user']['name'] != null) {
                              name = bookedTimeSlot['user']['name'];
                            } else if (bookedTimeSlot['bookedFor'] != null && bookedTimeSlot['bookedFor']['name'] != null) {
                              name = bookedTimeSlot['bookedFor']['name'];
                            } else if (bookedTimeSlot['creator'] != null) {
                              name = bookedTimeSlot['creator']['name'] ?? name;
                            }
                          }
                        occupied[date] = name;
                      }
                      break;
                    }
                  }"""
good_occ_loop = """                  for (final item in items) {
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
content = content.replace(bad_occ_loop, good_occ_loop)

bad_occ_ret = """return occupied;"""
good_occ_ret = """return WorkspaceOccupancyResult(occupied, delegated);"""
content = content.replace(bad_occ_ret, good_occ_ret)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)