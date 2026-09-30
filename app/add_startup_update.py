import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

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
        
        // TODO: REMOVE FORCE TEST (On force à 'true' pour tester la popup)
        if (true || (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion))) {
          
          // Clean the body to keep only brief info if needed, or show as is.
          String releaseNotes = data['body'] ?? 'Améliorations et corrections diverses.';
          
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
                    const Text('Nouveautés :', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    Text(releaseNotes, style: const TextStyle(fontSize: 13)),
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
      // Échec silencieux si pas d'internet au démarrage
    }
  }

  Future<void> _checkForUpdates() async {"""

content = content.replace("  Future<void> _checkForUpdates() async {", startup_logic)

# Call it in initState
init_state_pattern = r"  void initState\(\) \{\n    super\.initState\(\);"
init_state_replacement = "  void initState() {\n    super.initState();\n    _checkUpdatesOnStartup();"
content = re.sub(init_state_pattern, init_state_replacement, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)