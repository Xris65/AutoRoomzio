import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix calendar pred
content = content.replace("                      if (_vacationsEnabled) {\n                        if (_vacationsEnabled) {\n", "                      if (_vacationsEnabled) {\n")
# Clean any trailing stray closing bracket if it was added twice
# Let's just rewrite the block using find
start_idx = content.find("if (_vacationsEnabled) {")
end_idx = content.find("return true;", start_idx)
if start_idx != -1 and end_idx != -1:
    content = content[:start_idx] + """if (_vacationsEnabled) {
                        for (final v in _vacations) {
                          final start = DateTime(v.start.year, v.start.month, v.start.day);
                          final end = DateTime(v.end.year, v.end.month, v.end.day);
                          if (!normDay.isBefore(start) && !normDay.isAfter(end)) {
                            return false;
                          }
                        }
                      }
                      """ + content[end_idx:]


# Fix UI toggle
ui_start = content.find("                            const ListTile(\n                              leading: Icon(Icons.beach_access, color: Colors.orange),\n                              title: Text('Mes Cong")
if ui_start != -1:
    ui_end = content.find("if (_vacations.isNotEmpty) const Divider(height: 1),", ui_start)
    if ui_end != -1:
        new_ui = """                            SwitchListTile(
                              secondary: const Icon(Icons.beach_access, color: Colors.orange),
                              title: const Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                              value: _vacationsEnabled,
                              onChanged: (val) {
                                setState(() => _vacationsEnabled = val);
                                _storage.saveVacationsEnabled(val);
                              },
                            ),
                            if (_vacationsEnabled && _vacations.isNotEmpty) const Divider(height: 1),
"""
        content = content[:ui_start] + new_ui + content[ui_end + len("if (_vacations.isNotEmpty) const Divider(height: 1),"):]
else:
    print("UI start not found")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)