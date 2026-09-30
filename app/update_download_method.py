import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = r"  Future<void> _downloadAndInstallApk\(String url\) async \{[\s\S]*?  Future<void> _checkForUpdates\(\) async \{"

replacement = """  Future<void> _downloadAndInstallApk(String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadDialog(url: url),
    );
  }

  Future<void> _checkForUpdates() async {"""

content = re.sub(pattern, replacement, content)

# Remove the test bypass logic too!
test_bypass_1 = """  bool _isNewer(String latest, String current) {
    return true; // TODO: REMOVE ME - FORCAGE POUR TEST"""
fix_bypass_1 = """  bool _isNewer(String latest, String current) {"""
content = content.replace(test_bypass_1, fix_bypass_1)

test_bypass_2 = "if (true) { // TODO: REMOVE ME - FORCAGE POUR TEST"
fix_bypass_2 = "if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {"
content = content.replace(test_bypass_2, fix_bypass_2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)