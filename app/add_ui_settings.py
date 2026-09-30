import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

ui_settings_code = """
  // === UI Settings ===

  Future<void> saveShowAutomation(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_automation_card', show);
  }

  Future<bool> getShowAutomation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_automation_card') ?? true;
  }

  Future<void> saveShowStats(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_stats_card', show);
  }

  Future<bool> getShowStats() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_stats_card') ?? true;
  }
"""

content = content.replace("class StorageService {\n", "class StorageService {\n" + ui_settings_code)

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)