import re

with open('lib/screens/optimization_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update _PermissionTile
old_tile_def = """class _PermissionTile extends StatelessWidget {
  final String title;
  final String description;
  final bool? isOk;
  final VoidCallback onTap;
  final String actionLabel;
  final String? infoText;

  const _PermissionTile({
    super.key,
    required this.title,
    required this.description,
    this.isOk,
    required this.onTap,
    required this.actionLabel,
    this.infoText,
  });"""
new_tile_def = """class _PermissionTile extends StatelessWidget {
  final String title;
  final String description;
  final bool? isOk;
  final VoidCallback onTap;
  final String actionLabel;
  final String? infoText;
  final String? infoImage;

  const _PermissionTile({
    super.key,
    required this.title,
    required this.description,
    this.isOk,
    required this.onTap,
    required this.actionLabel,
    this.infoText,
    this.infoImage,
  });"""
content = content.replace(old_tile_def, new_tile_def)

# 2. Update _PermissionTile build method
old_dialog = """                      builder: (ctx) => AlertDialog(
                        title: Text("Info : $title"),
                        content: Text(infoText!),
                        actions: ["""
new_dialog = """                      builder: (ctx) => AlertDialog(
                        title: Text("Info : $title"),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(infoText!),
                              if (infoImage != null) ...[
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.asset(infoImage!, fit: BoxFit.contain),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: ["""
content = content.replace(old_dialog, new_dialog)

# 3. Add infoImage to invocations
old_batt = """            _PermissionTile(
              title: "Optimisation de batterie",
              description: "Empêche Android de tuer l'application en arrière-plan.",
              isOk: !_isBatteryOptimized,
              onTap: _requestBattery,
              actionLabel: "Désactiver l'optimisation",
              infoText: "Dans l'écran qui va s'ouvrir, choisissez 'AutoRoomzio' et sélectionnez 'Pas de restriction' ou 'Non optimisée'.\\n\\nC'est indispensable pour que l'application puisse réserver votre place le matin en arrière-plan.",
            ),"""
new_batt = """            _PermissionTile(
              title: "Optimisation de batterie",
              description: "Empêche Android de tuer l'application en arrière-plan.",
              isOk: !_isBatteryOptimized,
              onTap: _requestBattery,
              actionLabel: "Désactiver l'optimisation",
              infoText: "Dans l'écran qui va s'ouvrir, choisissez 'AutoRoomzio' et sélectionnez 'Pas de restriction' ou 'Non optimisée'.\\n\\nC'est indispensable pour que l'application puisse réserver votre place le matin en arrière-plan.",
              infoImage: 'assets/images/battery.png',
            ),"""
content = content.replace(old_batt, new_batt)

old_auto = """            _PermissionTile(
              title: "Démarrage Automatique",
              description: "Requis (surtout Xiaomi, Huawei, Oppo) pour relancer l'automatisation après un redémarrage.",
              isOk: _isAutostartVerified,
              onTap: _requestAutoStart,
              actionLabel: "Vérifier l'autostart",
              infoText: "Certains téléphones bloquent le lancement des applications après un redémarrage.\\n\\nDans le menu qui va s'ouvrir, cherchez 'AutoRoomzio' et activez l'interrupteur pour l'autoriser à démarrer tout seul.",
            ),"""
new_auto = """            _PermissionTile(
              title: "Démarrage Automatique",
              description: "Requis (surtout Xiaomi, Huawei, Oppo) pour relancer l'automatisation après un redémarrage.",
              isOk: _isAutostartVerified,
              onTap: _requestAutoStart,
              actionLabel: "Vérifier l'autostart",
              infoText: "Certains téléphones bloquent le lancement des applications après un redémarrage.\\n\\nDans le menu qui va s'ouvrir, cherchez 'AutoRoomzio' et activez l'interrupteur pour l'autoriser à démarrer tout seul.",
              infoImage: 'assets/images/autostart.png',
            ),"""
content = content.replace(old_auto, new_auto)

with open('lib/screens/optimization_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)