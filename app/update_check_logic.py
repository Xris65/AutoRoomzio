import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        // TODO: REMOVE FORCE TEST
        if (true || (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion))) {
          
          String rawNotes = data['body'] ?? '';
          
          showDialog("""

good = """        final ignoredVersion = await _storage.getIgnoredUpdateVersion();

        if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion) && latestVersion != ignoredVersion) {
          
          String rawNotes = data['body'] ?? '';
          
          showDialog("""

content = content.replace(bad, good)

# Also add the Ignore button in the dialog
bad_actions = """              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {"""

good_actions = """              actions: [
                TextButton(
                  onPressed: () {
                    _storage.saveIgnoredUpdateVersion(latestVersion);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Ignorer cette version', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {"""

content = content.replace(bad_actions, good_actions)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)