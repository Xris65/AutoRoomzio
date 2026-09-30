import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """              actions: [
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
                ),"""

good = """              actions: [
                TextButton(
                  onPressed: () {
                    _storage.saveIgnoredUpdateVersion(latestVersion);
                    Navigator.pop(ctx);
                  },
                  child: Text('Ignorer cette version', style: TextStyle(color: Colors.red.shade400)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard'),
                ),"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)