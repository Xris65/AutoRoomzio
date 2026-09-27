import re

with open('lib/screens/optimization_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove auto_start_flutter import
content = content.replace("import 'package:auto_start_flutter/auto_start_flutter.dart';\n", "")

old_autostart = """  Future<void> _requestAutoStart() async {
    if (!Platform.isAndroid) return;
    
    try {
      final available = await isAutoStartAvailable;
      if (available == true) {
        await getAutoStartPermission();
        // Since we launched the popup, we can assume they verified it
        setState(() => _isAutostartVerified = true);
        final storage = StorageService();
        await storage.saveAutostartVerified(true);
      } else {
        // No OEM autostart menu found
        setState(() => _isAutostartVerified = true);
        final storage = StorageService();
        await storage.saveAutostartVerified(true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Votre téléphone ne nécessite pas de configuration d'autostart supplémentaire."),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("AutoStart Error: $e");
      // Fallback in case of error
      setState(() => _isAutostartVerified = true);
      final storage = StorageService();
      await storage.saveAutostartVerified(true);
    }
  }"""

new_autostart = """  Future<void> _requestAutoStart() async {
    if (!Platform.isAndroid) return;
    
    final intents = [
      {'package': 'com.miui.securitycenter', 'component': 'com.miui.permcenter.autostart.AutoStartManagementActivity'},
      {'package': 'com.huawei.systemmanager', 'component': 'com.huawei.systemmanager.optimize.process.ProtectActivity'},
      {'package': 'com.huawei.systemmanager', 'component': 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity'},
      {'package': 'com.coloros.safecenter', 'component': 'com.coloros.safecenter.permission.startup.StartupAppListActivity'},
      {'package': 'com.coloros.safecenter', 'component': 'com.coloros.safecenter.startupapp.StartupAppListActivity'},
      {'package': 'com.oppo.safe', 'component': 'com.oppo.safe.permission.startup.StartupAppListActivity'},
      {'package': 'com.iqoo.secure', 'component': 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity'},
      {'package': 'com.vivo.permissionmanager', 'component': 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity'},
      {'package': 'com.asus.mobilemanager', 'component': 'com.asus.mobilemanager.entry.FunctionActivity'},
      {'package': 'com.samsung.android.lool', 'component': 'com.samsung.android.sm.ui.battery.BatteryActivity'},
    ];

    bool launched = false;
    for (final intentDict in intents) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: intentDict['package'],
          componentName: intentDict['component'],
        );
        await intent.launch();
        launched = true;
        break;
      } catch (e) {
        debugPrint("Failed to launch intent ${intentDict['package']}: $e");
      }
    }

    if (!mounted) return;

    if (launched) {
      // Demander confirmation à l'utilisateur s'il l'a bien fait
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Vérification"),
          content: const Text("Avez-vous bien autorisé le démarrage automatique pour AutoRoomzio dans les paramètres qui viennent de s'ouvrir ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
          ],
        )
      );
      if (result == true) {
        setState(() => _isAutostartVerified = true);
        final storage = StorageService();
        await storage.saveAutostartVerified(true);
      }
    } else {
      // Aucun menu trouvé, pas besoin
      setState(() => _isAutostartVerified = true);
      final storage = StorageService();
      await storage.saveAutostartVerified(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Votre téléphone ne nécessite pas de configuration d'autostart supplémentaire."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }"""

# Since I modified the code, I need to make sure I add import android_intent back
content = "import 'package:android_intent_plus/android_intent.dart';\n" + content
content = content.replace(old_autostart, new_autostart)

with open('lib/screens/optimization_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)