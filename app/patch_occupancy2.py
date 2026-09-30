import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"if \(bookedTimeSlot != null && bookedTimeSlot\['creator'\] != null\) \{\s*name = bookedTimeSlot\['creator'\]\['name'\] \?\? name;\s*\}"

good = """if (bookedTimeSlot != null) {
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

content = re.sub(bad, good, content)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)