import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<bool> cancelReservation(
      String date, String token, String workspaceId) async {"""
      
good = """  Future<bool> cancelReservation(
      String date, String token, String workspaceId, {String? eventId, String? forUserId}) async {"""
      
content = content.replace(bad, good)

bad2 = """    // First, try to find the exact booking ID from /users/current/bookings"""

good2 = """    // If we already have the exact eventId from the calendar, use it!
    if (eventId != null && eventId.isNotEmpty) {
      debugPrint("⚠️ Try 0: DELETE /bookings/$eventId");
      final delResp = await http.delete(
        Uri.parse("$_apiBase/bookings/$eventId"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (delResp.statusCode == 200 || delResp.statusCode == 204) {
        debugPrint("✅ Cancelled by eventId: $eventId");
        return true;
      }
      debugPrint("❌ Try 0 FAILED: ${delResp.statusCode} - ${delResp.body}");
      foundBookingId = eventId;
    }

    // First, try to find the exact booking ID from /users/current/bookings"""
    
content = content.replace(bad2, good2)

bad3 = """    final payload = {
      "workspaceId": workspaceId,
      "localDate": date,
      "timeSlot": "FullDay",
    };
    if (foundBookingId != null) {
      payload["id"] = foundBookingId;
    }"""
    
good3 = """    final payload = {
      "workspaceId": workspaceId,
      "localDate": date,
      "timeSlot": "FullDay",
    };
    if (foundBookingId != null && foundBookingId.isNotEmpty) {
      payload["id"] = foundBookingId;
    }
    if (forUserId != null && forUserId.isNotEmpty) {
      payload["forUserId"] = forUserId;
    }"""

content = content.replace(bad3, good3)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)