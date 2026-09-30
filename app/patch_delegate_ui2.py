with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "if (isDelegated)" in line and "Icons.group_off" in lines[i+2]:
        lines.insert(i, "                  final dParts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];\n                  final dName = dParts.length > 1 ? dParts[1] : 'votre collègue';\n                  final dLoc = dParts.length > 2 ? dParts[2] : '';\n")
        lines[i+7] = "                      subtitle: Text(\"Annule la réservation faite pour $dName\" + (dLoc.isNotEmpty ? \" sur $dLoc\" : \"\") + \" ce jour-là.\", style: const TextStyle(fontSize: 11)),\n"
        print("Replaced!")
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)