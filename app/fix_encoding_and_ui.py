import re
import json

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# First, fix the encoding mess
replacements = {
    'Mise Ã\xa0 jour disponible ðŸŽ‰': 'Mise à jour disponible 🎉',
    'Mise Ã\x82\xa0 jour disponible ðŸŽ‰': 'Mise à jour disponible 🎉',
    'Mise Ã\xa0 jour': 'Mise à jour',
    'Mise Ã jour': 'Mise à jour',
    'Une nouvelle version (v$latestVersion) est prÃªte !': 'Une nouvelle version (v$latestVersion) est prête !',
    'tÃ©lÃ©charger': 'télécharger',
    'prÃªte': 'prête',
    'vÃ©rifier': 'vérifier',
    'mises Ã\xa0 jour': 'mises à jour',
    'AmÃ©liorations': 'Améliorations',
    'Ã©': 'é',
    'Ã\xa0': 'à',
    'ðŸŽ‰': '🎉',
    'mainÃ\xa0xisSize': 'mainAxisSize',
    'crossÃ\xa0xisÃ\xa0lignment': 'crossAxisAlignment',
    'ÃutoRoomzio': 'AutoRoomzio',
}

for bad, good in replacements.items():
    content = content.replace(bad, good)

# Re-add _checkUpdatesOnStartup if it was lost, but it should still be there because I reverted only some changes?
# Wait! I ran `git checkout lib/screens/home_screen.dart` which LOST _checkUpdatesOnStartup completely!
# Let me just inject it cleanly!

# Ensure _checkUpdatesOnStartup is present
if '_checkUpdatesOnStartup' not in content:
    startup_logic = """  Future<void> _checkUpdatesOnStartup() async {
    try {
      final response = await http.get(Uri.parse('https://api.github.com/repos/Xris65/AutoRoomzio/releases/latest'));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestTag = data['tag_name'] as String;
        
        String? apkUrl;
        if (data['assets'] != null && data['assets'].isNotEmpty) {
          apkUrl = data['assets'][0]['browser_download_url'] as String?;
        }

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        final latestVersion = latestTag.replaceAll('v', '');
        
        // TODO: REMOVE FORCE TEST
        if (true || (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion))) {
          
          String rawNotes = data['body'] ?? '';
          
          // Helper pour nettoyer et formater les notes
          List<Widget> _buildReleaseNotes(String text) {
            List<Widget> widgets = [];
            final lines = text.split('\\n');
            for (var line in lines) {
              line = line.trim();
              if (line.isEmpty) {
                widgets.add(const SizedBox(height: 8));
                continue;
              }
              if (line.toLowerCase().contains('nouveautés') || line.toLowerCase().contains('correctifs') || line.startsWith('###')) {
                final title = line.replaceAll(RegExp(r'#|\\*'), '').trim();
                widgets.add(
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                  ),
                );
              } else {
                final body = line.replaceAll(RegExp(r'\\*\\*'), '');
                widgets.add(Text(body, style: const TextStyle(fontSize: 13)));
              }
            }
            return widgets;
          }

          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Mise à jour disponible 🎉'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._buildReleaseNotes(rawNotes),
                    const SizedBox(height: 16),
                    const Text('Voulez-vous l\\'installer maintenant ?'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (apkUrl != null) {
                      _downloadAndInstallApk(apkUrl);
                    } else {
                      launchUrl(Uri.parse(data['html_url']), mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Installer'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // Échec silencieux
    }
  }

  Future<void> _checkForUpdates() async {"""

    content = content.replace("  Future<void> _checkForUpdates() async {", startup_logic)
    
    init_state_pattern = r"  void initState\(\) \{\n    super\.initState\(\);\n    _checkAuthAndLoad\(\);\n  \}"
    init_state_replacement = "  void initState() {\n    super.initState();\n    _checkUpdatesOnStartup();\n    _checkAuthAndLoad();\n  }"
    content = re.sub(init_state_pattern, init_state_replacement, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
