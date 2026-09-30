import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """          for (final b in bookings) {
            if (b['type'] != 'Reserved') continue;
            final dateStr = b['eventDate']?.toString().split('T').first;"""

good = """          for (final b in bookings) {
            if (b['type'] != 'Reserved') continue;
            
            // Ignorer les réservations faites pour quelqu'un d'autre (Délégation)
            bool isForSomeoneElse = false;
            final creatorId = b['creator']?['id'] ?? b['creatorId'];
            final owner = b['owner'] ?? b['user'] ?? b['bookedFor'];
            if (owner != null && creatorId != null) {
              final ownerId = owner['id'];
              if (ownerId != null && ownerId != creatorId) {
                isForSomeoneElse = true;
              }
            }
            if (b['isDelegated'] == true) isForSomeoneElse = true;
            if (isForSomeoneElse) continue;

            final dateStr = b['eventDate']?.toString().split('T').first;"""

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)