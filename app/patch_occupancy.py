import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """                        if (bookedTimeSlot != null && bookedTimeSlot['creator'] != null) {
                          name = bookedTimeSlot['creator']['name'] ?? name;
                        }"""

good = """                        if (bookedTimeSlot != null) {
                          // Try to find the actual user rather than the creator if it was booked for someone else
                          if (bookedTimeSlot['owner'] != null && bookedTimeSlot['owner']['name'] != null) {
                            name = bookedTimeSlot['owner']['name'];
                          } else if (bookedTimeSlot['user'] != null && bookedTimeSlot['user']['name'] != null) {
                            name = bookedTimeSlot['user']['name'];
                          } else if (bookedTimeSlot['bookedFor'] != null && bookedTimeSlot['bookedFor']['name'] != null) {
                            name = bookedTimeSlot['bookedFor']['name'];
                          } else if (bookedTimeSlot['creator'] != null) {
                            name = bookedTimeSlot['creator']['name'] ?? name;
                          }
                        }"""

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)