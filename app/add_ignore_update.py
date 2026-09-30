import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_methods = """  Future<void> saveIgnoredUpdateVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ignored_update_version', version);
  }

  Future<String?> getIgnoredUpdateVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ignored_update_version');
  }

"""

# Insert before savePullToRefresh
content = content.replace("  Future<void> savePullToRefresh", new_methods + "  Future<void> savePullToRefresh")

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)