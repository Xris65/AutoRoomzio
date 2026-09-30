import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

settings_marker = "  // === UI Settings ==="
new_settings = """  // === UI Settings ===

  Future<void> savePullToRefresh(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pull_to_refresh', enabled);
  }

  Future<bool> getPullToRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pull_to_refresh') ?? true;
  }
"""
content = content.replace(settings_marker, new_settings)

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)