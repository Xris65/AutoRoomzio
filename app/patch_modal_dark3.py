with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "final dLoc = dParts.length > 2" in line:
        # Re-write the ListTile properly
        lines[i+1] = "                  if (isDelegated)\n"
        lines[i+2] = "                    ListTile(\n"
        lines[i+3] = "                      leading: Icon(Icons.group_off, color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900),\n"
        lines[i+4] = "                      title: Text('Annuler la délégation', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),\n"
        lines[i+5] = "                      subtitle: Text(\"Annule la réservation faite pour $dName\" + (dLoc.isNotEmpty ? \" sur $dLoc\" : \"\") + \" ce jour-là.\", style: const TextStyle(fontSize: 11)),\n"
        lines[i+6] = "                      onTap: () => Navigator.pop(context, 'cancel_delegation'),\n"
        lines[i+7] = "                    );\n"
        print("Replaced properly!")
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)