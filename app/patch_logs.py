import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """    if (foundBookingId != null) {
       final altResponse = await http.delete(
         Uri.parse("$_apiBase/users/current/bookings/$foundBookingId"),
         headers: {
           ..._authHeaders(token),
           "roomz-source-type": "MyRoomzWeb",
         },
       );
       if (altResponse.statusCode == 200 || altResponse.statusCode == 204) {
         return true;
       }
    }

    debugPrint("❌ cancelReservation FAILED: ${response.statusCode} - ${response.body}");"""

good = """    if (foundBookingId != null) {
       debugPrint("⚠️ Try 3: DELETE /users/current/bookings/$foundBookingId");
       final altResponse = await http.delete(
         Uri.parse("$_apiBase/users/current/bookings/$foundBookingId"),
         headers: {
           ..._authHeaders(token),
           "roomz-source-type": "MyRoomzWeb",
         },
       );
       if (altResponse.statusCode == 200 || altResponse.statusCode == 204) {
         return true;
       }
       debugPrint("❌ Try 3 FAILED: ${altResponse.statusCode} - ${altResponse.body}");
    }

    debugPrint("❌ cancelReservation FAILED (Fallback body): ${response.statusCode} - ${response.body}");"""

content = content.replace(bad, good)

bad2 = """              // Try DELETE /bookings/{id}
              final delResp = await http.delete(
                Uri.parse("$_apiBase/bookings/$foundBookingId"),
                headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
              );
              if (delResp.statusCode == 200 || delResp.statusCode == 204) {
                debugPrint("✅ Cancelled by URL ID: $foundBookingId");
                return true;
              }"""
              
good2 = """              // Try DELETE /bookings/{id}
              debugPrint("⚠️ Try 1: DELETE /bookings/$foundBookingId");
              final delResp = await http.delete(
                Uri.parse("$_apiBase/bookings/$foundBookingId"),
                headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
              );
              if (delResp.statusCode == 200 || delResp.statusCode == 204) {
                debugPrint("✅ Cancelled by URL ID: $foundBookingId");
                return true;
              }
              debugPrint("❌ Try 1 FAILED: ${delResp.statusCode} - ${delResp.body}");"""

content = content.replace(bad2, good2)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)