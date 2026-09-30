import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_isnewer = """  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }"""

new_isnewer = """  bool _isNewer(String latest, String current) {
    return true; // TODO: REMOVE ME - FORCAGE POUR TEST
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }"""

content = content.replace(old_isnewer, new_isnewer)

# Also force bypass the string equality check
content = content.replace(
    "if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {",
    "if (true) { // TODO: REMOVE ME - FORCAGE POUR TEST"
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)