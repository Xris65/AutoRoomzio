import re

# 1. Revert storage_service.dart
with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    storage = f.read()

storage = re.sub(r"  Future<void> saveVacationsEnabled\(bool enabled\) async \{[\s\S]*?return prefs\.getBool\('vacations_enabled'\) \?\? true;\n  \}\n", "", storage)

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(storage)


# 2. Modify home_screen.dart
with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    home = f.read()

# Remove _vacationsEnabled state
home = home.replace("  bool _vacationsEnabled = true;\n", "")
home = home.replace("      final vacsEnabled = await _storage.getVacationsEnabled();\n", "")
home = home.replace("        _vacationsEnabled = vacsEnabled;\n", "")

# Update calendar and _isVacation to use _showAutomation
home = home.replace("if (!_vacationsEnabled) return false;", "if (!_showAutomation) return false;")
home = home.replace("if (_vacationsEnabled) {", "if (_showAutomation) {")
home = home.replace("if (_vacationsEnabled) ..._vacations.map", "if (_showAutomation) ..._vacations.map")
home = home.replace("if (_vacationsEnabled) Padding(", "if (_showAutomation) Padding(")

# Remove the explicit toggle in UI
ui_toggle_start = home.find("                            SwitchListTile(\n                              secondary: const Icon(Icons.beach_access")
if ui_toggle_start != -1:
    ui_toggle_end = home.find("                            if (_showAutomation && _vacations.isNotEmpty) const Divider(height: 1),", ui_toggle_start)
    if ui_toggle_end != -1:
        new_ui = """                            const ListTile(
                              leading: Icon(Icons.beach_access, color: Colors.orange),
                              title: Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                            ),
                            if (_vacations.isNotEmpty) const Divider(height: 1),"""
        home = home[:ui_toggle_start] + new_ui + home[ui_toggle_end + len("                            if (_showAutomation && _vacations.isNotEmpty) const Divider(height: 1),"):]


# Revert settings toggle logic (don't save/change _vacationsEnabled)
old_settings_toggle = """                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                        _vacationsEnabled = false;
                        _storage.saveVacationsEnabled(false);
                      }"""
new_settings_toggle = """                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                      }"""
home = home.replace(old_settings_toggle, new_settings_toggle)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(home)