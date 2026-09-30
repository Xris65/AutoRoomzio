with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

import re

bad = r"final resp = await http\.get\(Uri\.parse\(\"https://api\.my\.roomz\.io/users/current/bookings\"\), headers: \{\"Authorization\": \"Bearer \$token\", \"roomz-source-type\": \"MyRoomzWeb\"\}\);"
good = r"final floorId = await _storage.getFloorId(); final resp = await http.post(Uri.parse(\"https://api.my.roomz.io/floors/$floorId/workspaces/calendars?length=100&offset=0\"), headers: {\"Authorization\": \"Bearer $token\", \"roomz-source-type\": \"MyRoomzWeb\", \"Content-Type\": \"application/json\"}, body: jsonEncode({\"availableWorkspaceOnly\": false, \"date\": DateTime.now().toIso8601String().split('T').first, \"timeSlot\": \"FullDay\", \"tagIds\": [], \"workspaceType\": \"Desk\"}));"

content = re.sub(bad, good, content)
with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)