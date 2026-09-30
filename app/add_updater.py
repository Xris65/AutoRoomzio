import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add json import if not present
if "import 'dart:convert';" not in content:
    content = content.replace("import 'dart:io';", "import 'dart:io';\nimport 'dart:convert';")

# Add _isNewer and _checkForUpdates methods
methods = """  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  Future<void> _checkForUpdates() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.blue)),
      );

      final response = await http.get(Uri.parse('https://api.github.com/repos/Xris65/AutoRoomzio/releases/latest'));
      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestTag = data['tag_name'] as String; // e.g. "v1.3.1"
        
        String? apkUrl;
        if (data['assets'] != null && data['assets'].isNotEmpty) {
          apkUrl = data['assets'][0]['browser_download_url'] as String?;
        }

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version; // e.g. "1.3.1"
        
        final latestVersion = latestTag.replaceAll('v', '');
        
        if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Mise à jour disponible 🎉'),
              content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\n\nVoulez-vous la télécharger et l\\'installer maintenant ?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (apkUrl != null) {
                      launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
                    } else {
                      launchUrl(Uri.parse(data['html_url']), mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Télécharger'),
                ),
              ],
            ),
          );
        } else {
          _showTopToast('Votre application est déjà à jour ! (v$currentVersion)', isSuccess: true);
        }
      } else {
        _showTopToast('Erreur serveur lors de la vérification.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTopToast('Impossible de vérifier les mises à jour (Pas de connexion)', isError: true);
      }
    }
  }

  Widget _buildSettingsTab() {"""

content = content.replace("  Widget _buildSettingsTab() {", methods)

# Add the button in the Settings Tab
old_button = """              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Code Source'),
                subtitle: const Text('Voir le projet sur GitHub', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                onTap: () async {
                  final url = Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),"""

new_button = """              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Code Source'),
                subtitle: const Text('Voir le projet sur GitHub', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                onTap: () async {
                  final url = Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.system_update_rounded, color: Colors.green),
                title: const Text('Rechercher des mises à jour', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                subtitle: const Text('Vérifier si une nouvelle version est disponible', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.download_rounded, size: 16, color: Colors.green),
                onTap: _checkForUpdates,
              ),"""

content = content.replace(old_button, new_button)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)