import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

if "import 'package:open_filex/open_filex.dart';" not in content:
    content = content.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:path_provider/path_provider.dart';\nimport 'package:open_filex/open_filex.dart';"
    )

old_check = """  Future<void> _checkForUpdates() async {
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
              content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\\n\\nVoulez-vous la télécharger et l\\'installer maintenant ?'),
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
  }"""

new_check = """  Future<void> _downloadAndInstallApk(String url) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Téléchargement en cours...\\nVeuillez patienter.'),
            ],
          ),
        ),
      );

      final response = await http.get(Uri.parse(url));
      
      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/AutoRoomzio_update.apk');
        await file.writeAsBytes(response.bodyBytes);
        
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done) {
          if (mounted) _showTopToast('Erreur lors du lancement de l\\'installation.', isError: true);
        }
      } else {
        _showTopToast('Échec du téléchargement.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTopToast('Erreur de connexion.', isError: true);
      }
    }
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
        final currentVersion = packageInfo.version;
        
        final latestVersion = latestTag.replaceAll('v', '');
        
        if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Mise à jour disponible 🎉'),
              content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\\n\\nVoulez-vous la télécharger et l\\'installer maintenant ?'),
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
  }"""

content = content.replace(old_check, new_check)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)