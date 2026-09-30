import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove test bypass in _isNewer
test_bypass_1 = """  bool _isNewer(String latest, String current) {
    return true; // TODO: REMOVE ME - FORCAGE POUR TEST"""
fix_bypass_1 = """  bool _isNewer(String latest, String current) {"""
content = content.replace(test_bypass_1, fix_bypass_1)

# Remove test bypass in _checkForUpdates
test_bypass_2 = "if (true) { // TODO: REMOVE ME - FORCAGE POUR TEST"
fix_bypass_2 = "if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {"
content = content.replace(test_bypass_2, fix_bypass_2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)