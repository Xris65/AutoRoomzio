import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """                             if (organizerName != null && organizerName != creatorName) {
                                isDelegated = true;
                                delegateName = organizerName;
                             }"""
good = """                             if (organizerName != null && organizerName != creatorName) {
                                isDelegated = true;
                                final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                                delegateName = "${wsId}|${organizerName}";
                             }"""
                             
content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)