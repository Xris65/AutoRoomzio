import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        final bookings = data['bookings'] as List? ?? [];"""

good = """      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        // DUMP TO FILE
        try {
          // write to the same dir as the app
          final file = java.io.File... wait this is dart
        } catch (_) {}
        final bookings = data['bookings'] as List? ?? [];"""
        
# Actually, let's just use dart:io File inside api_service to dump!
good = """      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        try {
          final f = java_is_not_dart; // wait
        } catch (_) {}
        final bookings = data['bookings'] as List? ?? [];"""

# Better: Just print to debugPrint, the user already gave me the logs once!
# Wait, if I use debugPrint, they have to copy-paste the logs.
# Let's print the entire bookings JSON!
good = """      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        debugPrint("🔥 BOOKINGS DUMP: ${getResp.body}");
        final bookings = data['bookings'] as List? ?? [];"""

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)