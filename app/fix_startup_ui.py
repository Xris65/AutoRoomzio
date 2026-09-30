import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_ui = """                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('Nouveautés :', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    Text(releaseNotes, style: const TextStyle(fontSize: 13)),"""

good_ui = """                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(releaseNotes, style: const TextStyle(fontSize: 13)),"""

content = content.replace(bad_ui, good_ui)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)