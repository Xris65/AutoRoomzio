import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """    Future<bool> cancelBookingByDate(String token, String dateStr) async {
      try {
        final response = await http.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final bookings = data['bookings'] as List? ?? [];
          for (final b in bookings) {
            if (b['type'] != 'Reserved') continue;
            final bDate = b['eventDate']?.toString().split('T').first;
            if (bDate == dateStr) {
              final wsId = b['workspaceId']?.toString();
              if (wsId != null) {
                return await cancelReservation(dateStr, token, wsId);
              }
            }
          }
        }
      } catch (e) {"""

good = """    Future<bool> cancelBookingByDate(String token, String dateStr, {bool delegated = false}) async {
      try {
        final response = await http.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final bookings = data['bookings'] as List? ?? [];
          for (final b in bookings) {
            if (b['type'] != 'Reserved') continue;
            final bDate = b['eventDate']?.toString().split('T').first;
            if (bDate == dateStr) {
              bool isDeleg = false;
              final creator = b['creator'];
              final organizer = b['organizer'];
              if (creator != null && organizer != null) {
                 if (creator['id'] != null && organizer['id'] != null && creator['id'] != organizer['id']) isDeleg = true;
                 else if (creator['name'] != null && organizer['name'] != null && creator['name'] != organizer['name']) isDeleg = true;
              }
              
              if (isDeleg == delegated) {
                final wsId = b['workspaceId']?.toString();
                if (wsId != null) {
                  return await cancelReservation(dateStr, token, wsId);
                }
              }
            }
          }
        }
      } catch (e) {"""

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)