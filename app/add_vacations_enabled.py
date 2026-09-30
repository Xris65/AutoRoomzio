import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add get/set for vacationsEnabled
ui_settings_code = """
  Future<void> saveVacationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vacations_enabled', enabled);
  }

  Future<bool> getVacationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('vacations_enabled') ?? true;
  }
"""

content = content.replace("Future<void> saveShowAutomation", ui_settings_code + "\n  Future<void> saveShowAutomation")

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)