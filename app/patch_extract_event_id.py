import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """            if (bDate == date && bWsId == workspaceId) {
              foundBookingId = b['id']?.toString();
              if (foundBookingId != null) {"""
              
good = """            if (bDate == date && bWsId == workspaceId) {
              foundBookingId = b['eventId']?.toString() ?? b['id']?.toString();
              if (foundBookingId != null) {
                // If it contains a slash (workspaceId/eventId), extract the second part
                if (foundBookingId!.contains('/')) {
                  foundBookingId = foundBookingId!.split('/')[1];
                }"""
                
content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)