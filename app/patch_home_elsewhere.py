import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = "final result = await _api.getWorkspaceOccupancy(token, workspaceId, floorId, datesToCheck, myUserId);"
good = "final result = await _api.getWorkspaceOccupancy(token, workspaceId, floorId, datesToCheck, myUserId, _bookedElsewhereMap);"

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)