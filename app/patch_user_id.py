import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = "Future<({Set<String> here, Map<String, String> elsewhere, Map<String, String> delegated})> getMyReservations(\n        String token, String workspaceId) async {"
good1 = "Future<({Set<String> here, Map<String, String> elsewhere, Map<String, String> delegated, String? myUserId})> getMyReservations(\n        String token, String workspaceId) async {"

bad2 = """          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final bookings = data['bookings'] as List? ?? [];
            final Set<String> here = {};
            final Map<String, String> elsewhere = {};
            final Map<String, String> delegated = {};
            
            for (final b in bookings) {"""
            
good2 = """          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final bookings = data['bookings'] as List? ?? [];
            final Set<String> here = {};
            final Map<String, String> elsewhere = {};
            final Map<String, String> delegated = {};
            String? foundUserId;
            
            for (final b in bookings) {
              if (foundUserId == null && b['creator'] != null && b['creator']['id'] != null) {
                foundUserId = b['creator']['id']?.toString();
              }"""
              
bad3 = "return (here: here, elsewhere: elsewhere, delegated: <String, String>{});"
good3 = "return (here: here, elsewhere: elsewhere, delegated: <String, String>{}, myUserId: foundUserId);"

bad4 = "return (here: <String>{}, elsewhere: <String, String>{}, delegated: <String, String>{});"
good4 = "return (here: <String>{}, elsewhere: <String, String>{}, delegated: <String, String>{}, myUserId: null);"

content = content.replace(bad1, good1).replace(bad2, good2).replace(bad3, good3).replace(bad4, good4)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)