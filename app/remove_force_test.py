import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        // TODO: REMOVE FORCE TEST
        if (true || (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion))) {"""

good = """        final ignoredVersion = await _storage.getIgnoredUpdateVersion();
        
        if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion) && latestVersion != ignoredVersion) {"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)