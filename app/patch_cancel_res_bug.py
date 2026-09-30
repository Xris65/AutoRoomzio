import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = "final bWsId = b['workspaceId']?.toString();"
good = "final bWsId = b['workspaceId']?.toString() ?? b['workspace']?['id']?.toString();"
content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)