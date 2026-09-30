import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

fix_bypass_1 = """  bool _isNewer(String latest, String current) {"""
test_bypass_1 = """  bool _isNewer(String latest, String current) {
    return true; // TODO: REMOVE ME - FORCAGE POUR TEST"""
content = content.replace(fix_bypass_1, test_bypass_1, 1)

fix_bypass_2 = "if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {"
test_bypass_2 = "if (true) { // TODO: REMOVE ME - FORCAGE POUR TEST"
content = content.replace(fix_bypass_2, test_bypass_2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)