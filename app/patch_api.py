import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = r"Future<\(\{Set<String> here, Map<String, String> elsewhere\}\)> getMyReservations.*?return \(here: <String>\{\}, elsewhere: <String, String>\{\}\);\s*\}"

good = """Future<({Set<String> here, Map<String, String> elsewhere, Map<String, String> delegated})> getMyReservations(
        String token, String workspaceId) async {
      try {
        final response = await http.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final bookings = data['bookings'] as List? ?? [];
          final Set<String> here = {};
          final Map<String, String> elsewhere = {};
          final Map<String, String> delegated = {};
          
          for (final b in bookings) {
            if (b['type'] != 'Reserved') continue;
            final dateStr = b['eventDate']?.toString().split('T').first;
            if (dateStr == null) continue;
            
            // Check if it's delegated
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
            
            final wsName = b['workspaceName']?.toString() ?? b['workspaceTitle']?.toString() ?? b['workspace']?['name']?.toString() ?? "Ailleurs";
            
            if (isDelegated) {
               delegated[dateStr] = "$targetName ($wsName)";
            } else if (b['workspaceId'] == workspaceId) {
              here.add(dateStr);
            } else {
              elsewhere[dateStr] = wsName;
            }
          }
          return (here: here, elsewhere: elsewhere, delegated: delegated);
        }
        debugPrint("❌ getMyReservations ${response.statusCode}");
      } catch (e) {
        debugPrint("❌ Exception getMyReservations: $e");
      }
      return (here: <String>{}, elsewhere: <String, String>{}, delegated: <String, String>{});
    }"""

content = re.sub(pattern, good, content, flags=re.DOTALL)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)
