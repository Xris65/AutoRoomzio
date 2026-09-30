with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip = False
for i, line in enumerate(lines):
    if "SwitchListTile(" in line and "Icons.beach_access" in lines[i+1]:
        skip = True
        new_lines.append("                          const ListTile(\n")
        new_lines.append("                            leading: Icon(Icons.beach_access, color: Colors.orange),\n")
        new_lines.append("                            title: Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),\n")
        new_lines.append("                            subtitle: Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),\n")
        new_lines.append("                          ),\n")
        new_lines.append("                          if (_vacations.isNotEmpty) const Divider(height: 1),\n")
        continue
    
    if skip:
        if "if (_vacationsEnabled && _vacations.isNotEmpty) const Divider(height: 1)," in line:
            skip = False
        continue
    
    new_lines.append(line)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
