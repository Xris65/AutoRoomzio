with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

start_idx = content.find("SwitchListTile(\n                              secondary: const Icon(Icons.beach_access, color: Colors.orange),")
if start_idx != -1:
    end_idx = content.find("if (_showAutomation && _vacations.isNotEmpty) const Divider(height: 1),", start_idx)
    if end_idx != -1:
        new_ui = """const ListTile(
                              leading: Icon(Icons.beach_access, color: Colors.orange),
                              title: Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                            ),
                            if (_vacations.isNotEmpty) const Divider(height: 1),"""
        
        # Also clean up the missing _vacationsEnabled which is causing errors now
        content = content[:start_idx] + new_ui + content[end_idx + len("if (_showAutomation && _vacations.isNotEmpty) const Divider(height: 1),"):]
        with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
            f.write(content)
    else:
        print("End not found")
else:
    print("Start not found")
