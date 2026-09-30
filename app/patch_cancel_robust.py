import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """    final response = await http.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode(payload),
    );
    
    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    } else {
      debugPrint("❌ cancelReservation FAILED: ${response.statusCode} - ${response.body}");
      return false;
    }"""

good = """    var response = await http.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode(payload),
    );
    
    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    }
    
    // If it still fails, try one more endpoint format that some versions of the API use
    if (foundBookingId != null) {
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

    debugPrint("❌ cancelReservation FAILED: ${response.statusCode} - ${response.body}");
    return false;"""

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)