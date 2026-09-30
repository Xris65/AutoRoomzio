import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """                             if (organizerName != null && organizerName != creatorName) {
                                isDelegated = true;
                                final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                                final location = isMyDesk ? "Mon bureau" : "Autre bureau";
                                delegateName = "${wsId}|${organizerName}|${location}";
                             }"""
                             
good = """                             if (organizerName != null && organizerName != creatorName) {
                                isDelegated = true;
                                final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                                final location = isMyDesk ? "Mon bureau" : "Autre bureau";
                                final eventId = bookedTimeSlot['id']?.toString() ?? "";
                                final orgId = organizer['id']?.toString() ?? "";
                                delegateName = "${wsId}|${organizerName}|${location}|${eventId}|${orgId}";
                             }"""
content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)