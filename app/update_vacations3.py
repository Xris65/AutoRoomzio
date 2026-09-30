with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

start_idx = content.find("const ListTile(\n                            leading: Icon(Icons.beach_access, color: Colors.orange)")
if start_idx != -1:
    end_idx = content.find("if (_vacations.isNotEmpty) const Divider(height: 1),", start_idx)
    
    new_ui = """SwitchListTile(
                            secondary: const Icon(Icons.beach_access, color: Colors.orange),
                            title: const Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                            value: _vacationsEnabled,
                            onChanged: (val) {
                              setState(() => _vacationsEnabled = val);
                              _storage.saveVacationsEnabled(val);
                            },
                          ),
                          if (_vacationsEnabled && _vacations.isNotEmpty) const Divider(height: 1),"""
                          
    content = content[:start_idx] + new_ui + content[end_idx + len("if (_vacations.isNotEmpty) const Divider(height: 1),"):]
    with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
else:
    print("Not found")