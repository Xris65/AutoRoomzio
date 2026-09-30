import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """        String delegateName = "Quelqu'un";
        if (isDelegated) {
           final parts = _delegatedBookingsMap[dateStr]!.split('|');
           delegateName = parts.length > 1 ? parts[1] : parts[0];
        }"""
        
good1 = """        String delegateName = "Quelqu'un";
        String delegateLocation = "";
        if (isDelegated) {
           final parts = _delegatedBookingsMap[dateStr]!.split('|');
           delegateName = parts.length > 1 ? parts[1] : parts[0];
           if (parts.length > 2) delegateLocation = parts[2];
        }"""
content = content.replace(bad1, good1)

bad2 = """      if (isDelegated) {
        upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": delegateName});
      }"""
      
good2 = """      if (isDelegated) {
        upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": delegateName, "location": delegateLocation});
      }"""
content = content.replace(bad2, good2)

bad3 = r"source == 'Délégué' \? 'Réservé pour \$\{item\[\"name\"\]\}' :"
good3 = """source == 'Délégué' ? 'Réservé pour ${item["name"]}' + (item["location"] != null && item["location"].toString().isNotEmpty ? ' (${item["location"]})' : '') :"""
content = re.sub(bad3, good3, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)