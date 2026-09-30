import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<bool> cancelReservation(
      String date, String token, String workspaceId) async {
    final response = await http.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode({
        "workspaceId": workspaceId,
        "localDate": date,
        "timeSlot": "FullDay",
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint("🧹 Cancelled $date");
      return true;
    } else {
      debugPrint("❌ cancelReservation ${response.statusCode} $date: ${response.body}");
      return false;
    }
  }"""
  
good = """  Future<bool> cancelReservation(
      String date, String token, String workspaceId) async {
    // First, try to find the exact booking ID from /users/current/bookings
    try {
      final getResp = await http.get(
        Uri.parse("$_apiBase/users/current/bookings"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        final bookings = data['bookings'] as List? ?? [];
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          final bWsId = b['workspaceId']?.toString();
          if (bDate == date && bWsId == workspaceId) {
            final bookingId = b['id']?.toString();
            if (bookingId != null) {
              // Try DELETE /bookings/{id}
              final delResp = await http.delete(
                Uri.parse("$_apiBase/bookings/$bookingId"),
                headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
              );
              if (delResp.statusCode == 200 || delResp.statusCode == 204) {
                return true;
              }
            }
          }
        }
      }
    } catch (_) {}
    
    // Fallback to original body-based DELETE which might cancel the wrong one
    final response = await http.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode({
        "workspaceId": workspaceId,
        "localDate": date,
        "timeSlot": "FullDay",
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    } else {
      return false;
    }
  }"""
content = re.sub(r"  Future<bool> cancelReservation\([\s\S]*?return false;\s*\}\s*\}", good, content)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)