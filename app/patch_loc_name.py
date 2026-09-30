import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """                              final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                              final location = isMyDesk ? 'Mon bureau' : 'Autre bureau';"""
                              
good = """                              final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                              final workspaceName = item['name']?.toString() ?? item['workspaceName']?.toString();
                              final location = isMyDesk ? 'Mon bureau' : (workspaceName ?? 'Autre bureau');"""
                              
content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)