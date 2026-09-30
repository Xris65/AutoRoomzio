import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"                  if \(isDelegated\)\s*ListTile\(\s*leading: Icon\(Icons.group_off, color: Colors.purple.shade900\),\s*title: Text\('Annuler la délégation', style: TextStyle\(color: Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold\)\),"

good = """                  if (isDelegated)
                    ListTile(
                      leading: Icon(Icons.group_off, color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900),
                      title: Text('Annuler la délégation', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),"""

content = re.sub(bad, good, content, flags=re.DOTALL)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)