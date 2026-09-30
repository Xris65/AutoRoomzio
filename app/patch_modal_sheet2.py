with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "if (!isBooked && !isRequested)" in line and "isWeekendAndHidden" in lines[i+1]:
        lines.insert(i, """                if (isDelegated)
                  ListTile(
                    leading: Icon(Icons.group_off, color: Colors.purple.shade900),
                    title: Text('Annuler la délégation', style: TextStyle(color: Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text("Annule la réservation faite pour votre collègue ce jour-là.", style: TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(context, 'cancel_delegation'),
                  ),
""")
        print("Replaced!")
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)