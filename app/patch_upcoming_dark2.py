import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"leading: Icon\(\s*source == 'Ailleurs'.*?fontSize: _compactMode \? 10 : 12\),\s*\),"

good = """              leading: Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Icon(
                    source == 'Ailleurs' ? Icons.person : (source == 'Délégué' ? Icons.group : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending))),
                    color: source == 'Ailleurs' ? (isDark ? Colors.orange.shade300 : Colors.orange.shade900) : (source == 'Délégué' ? (isDark ? Colors.purple.shade300 : Colors.purple.shade900) : (source == 'Occupé' ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700) : (isBooked ? (isDark ? Colors.green.shade400 : Colors.green) : (isDark ? Colors.blue.shade300 : Colors.blue)))),
                  );
                }
              ),
              title: Text('$weekDayName ${date.day}/${date.month}'),
              subtitle: Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Text(
                    source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Délégué' ? 'Réservé pour ${item["name"]}' : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)'))),
                    style: TextStyle(color: source == 'Ailleurs' ? (isDark ? Colors.orange.shade300 : Colors.orange.shade900) : (source == 'Délégué' ? (isDark ? Colors.purple.shade300 : Colors.purple.shade900) : (source == 'Occupé' ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700) : (isBooked ? (isDark ? Colors.green.shade400 : Colors.green) : (isDark ? Colors.blue.shade300 : Colors.blue)))), fontSize: _compactMode ? 10 : 12),
                  );
                }
              ),"""

content = re.sub(bad, good, content, flags=re.DOTALL)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)