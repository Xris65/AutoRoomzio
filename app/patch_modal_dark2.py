with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "leading: Icon(Icons.group_off, color: Colors.purple.shade900)," in line:
        lines[i] = "                      leading: Icon(Icons.group_off, color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900),\n"
    if "title: Text('Annuler la " in line and "Colors.purple.shade900" in line:
        lines[i] = "                      title: Text('Annuler la délégation', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),\n"
        print("Replaced!")
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)