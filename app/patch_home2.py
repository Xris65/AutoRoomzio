import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 4. Modify Calendar build day
content = re.sub(
    r'final isElsewhere = !isBooked && _bookedElsewhereMap\.containsKey\(dateStr\) && _showAllReservations;\s*final isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers\.containsKey\(dateStr\);',
    'final isElsewhere = !isBooked && _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;\n      final isDelegated = !isBooked && !isElsewhere && _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;\n      final isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);',
    content
)

content = re.sub(
    r'\} else if \(isElsewhere\) \{\s*bgColor = Colors\.orange\.shade200;\s*textColor = Colors\.orange\.shade900;\s*strikeThrough = false;\s*\} else if \(isOccupiedByOthers\) \{',
    '} else if (isElsewhere) {\n        bgColor = Colors.orange.shade200;\n        textColor = Colors.orange.shade900;\n        strikeThrough = false;\n      } else if (isDelegated) {\n        bgColor = Colors.purple.shade200;\n        textColor = Colors.purple.shade900;\n        strikeThrough = false;\n      } else if (isOccupiedByOthers) {',
    content
)

# 6. Home page upcoming bookings
content = re.sub(
    r'bool isElsewhere = _bookedElsewhereMap\.containsKey\(dateStr\);\s*bool isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers\.containsKey\(dateStr\);',
    'bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr);\n        bool isDelegated = _delegatedBookingsMap.containsKey(dateStr);\n        bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);',
    content
)

content = re.sub(
    r'if \(isElsewhere\) \{\s*if \(_showAllReservations\) \{\s*upcoming\.add\(\{"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap\[dateStr\]\}\);\s*\}\s*\} else if \(isOccupiedByOthers\) \{',
    'if (isElsewhere) {\n          if (_showAllReservations) {\n            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});\n          }\n        } else if (isDelegated) {\n          if (_showDelegatedReservations) {\n            upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": _delegatedBookingsMap[dateStr]});\n          }\n        } else if (isOccupiedByOthers) {',
    content
)

# Update the UI strings (we can just replace literally)
bad_ui = """source == 'Ailleurs' ? Icons.person : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending))"""
good_ui = """source == 'Ailleurs' ? Icons.person : (source == 'Délégué' ? Icons.group : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending)))"""
content = content.replace(bad_ui, good_ui)
content = content.replace(bad_ui.replace("Occupé", "OccupÃ©"), good_ui.replace("Occupé", "OccupÃ©").replace("Délégué", "DÃ©lÃ©guÃ©"))

bad_color = """source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue))"""
good_color = """source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Délégué' ? Colors.purple.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue)))"""
content = content.replace(bad_color, good_color)
content = content.replace(bad_color.replace("Occupé", "OccupÃ©"), good_color.replace("Occupé", "OccupÃ©").replace("Délégué", "DÃ©lÃ©guÃ©"))

bad_subtitle = """source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)'))"""
good_subtitle = """source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Délégué' ? 'Réservé pour ${item["name"]}' : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)')))"""
content = content.replace(bad_subtitle, good_subtitle)
# encoding fix
content = content.replace("source == 'Ailleurs' ? 'RÃ©servÃ© sur un autre bureau (${item[\"name\"] ?? \"Ailleurs\"})' : (source == 'OccupÃ©' ? 'Indisponible (rÃ©servÃ© par ${item[\"name\"] ?? \"qqn d\\'autre\"})' : (isBooked ? 'DÃ©jÃ  rÃ©servÃ©' : 'Sera rÃ©servÃ© (Automatique)'))", "source == 'Ailleurs' ? 'RÃ©servÃ© sur un autre bureau (${item[\"name\"] ?? \"Ailleurs\"})' : (source == 'DÃ©lÃ©guÃ©' ? 'RÃ©servÃ© pour ${item[\"name\"]}' : (source == 'OccupÃ©' ? 'Indisponible (rÃ©servÃ© par ${item[\"name\"] ?? \"qqn d\\'autre\"})' : (isBooked ? 'DÃ©jÃ  rÃ©servÃ©' : 'Sera rÃ©servÃ© (Automatique)')))")

bad_bg = """(source == 'Ailleurs' ? Colors.orange.withValues(alpha: 0.3) : (source == 'Occupé' ? Colors.grey.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1)))"""
good_bg = """(source == 'Ailleurs' ? Colors.orange.withValues(alpha: 0.3) : (source == 'Délégué' ? Colors.purple.withValues(alpha: 0.3) : (source == 'Occupé' ? Colors.grey.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1))))"""
content = content.replace(bad_bg, good_bg)
content = content.replace(bad_bg.replace("Occupé", "OccupÃ©"), good_bg.replace("Occupé", "OccupÃ©").replace("Délégué", "DÃ©lÃ©guÃ©"))


with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)